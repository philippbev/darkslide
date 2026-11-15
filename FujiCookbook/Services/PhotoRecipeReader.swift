import Foundation
import ImageIO
import UIKit

/// The general EXIF facts about a photo that aren't part of a recipe — what the frame was, not
/// what it was processed with. Display-only: nothing here round-trips into `RecipeSettings`.
struct CameraSnapshot {
    var make: String?
    var model: String?
    var lens: String?
    var focalLength: Double?
    var focalLength35mm: Int?
    var fNumber: Double?
    var exposureTime: Double?
    var iso: Int?
    /// The EV the frame was shot at. Display-only: a photo's EV isn't a recipe setting, so it never
    /// becomes `RecipeSettings.exposureBias`.
    var exposureBias: Double?
    var captureDate: Date?
    var pixelWidth: Int?
    var pixelHeight: Int?
}

/// Whether `PhotoRecipeReader.read` found a usable Fujifilm recipe in this photo, and if not, why.
/// Any status other than `.found` still leaves `CameraSnapshot` readable: ImageIO reads it
/// independently of the MakerNote parse.
enum FujiRecipeStatus: Equatable {
    case found
    /// Not shot on a Fujifilm camera — there's no recipe to look for.
    case notFujifilm(make: String?)
    /// The EXIF is intact but the Fujifilm MakerNote tag itself is gone — stripped by an editor, a
    /// messaging app's re-compression, or similar.
    case noMakerNote
    /// A Fujifilm MakerNote is present but isn't in a shape this parser recognises.
    case unreadable
}

/// Everything `PhotoRecipeReader.read` produces from one JPEG: the recipe it decoded (if any), the
/// frame it belongs to, and enough provenance to explain both.
struct PhotoRecipeReading {
    var filename: String?
    var recipeStatus: FujiRecipeStatus
    /// Empty (`RecipeSettings()`) whenever `recipeStatus != .found`.
    var settings: RecipeSettings
    var camera: CameraSnapshot
    /// Resolved `CameraModel.id`, for `Recipe.authoredForModelID` on Save as New Recipe.
    var modelID: String?
    /// Fields the MakerNote carries that aren't part of a recipe (Crop Mode, Shutter Type).
    var extras: [(label: String, value: String)]
    /// Non-fatal notes about the read — an unmapped white-balance mode, an unreadable film
    /// simulation. Rendered inline, never as an alert: none of them stop the read from succeeding.
    var warnings: [String]
    /// Recipe and structural MakerNote tags for diagnostics; serial numbers are excluded.
    var rawTags: [(label: String, value: String)]
    /// Filtered extraction evidence, preserved in the recipe's unsupported fields on save.
    /// These observations are never consumed by a camera encoder as requested settings.
    var preservedMetadata: [String: JSONValue]
    var recordedWBShifts: [Int]?
    var proxy: UIImage?
}

/// Turns a Fujifilm JPEG into a `PhotoRecipeReading`. The deterministic counterpart to
/// `RecipeScanner`: that one sends a screenshot to an LLM and guesses at a recipe; this one reads
/// candidate settings from recorded metadata, retaining uncertainty when intent isn't recoverable.
enum PhotoRecipeReader {
    /// How to scale the recorded WB fine-tune pair. The app reads with `.automatic`; the explicit
    /// cases, which match the record's options of the same names, exist for parser tests.
    enum WBShiftScale: String, CaseIterable {
        case automatic, unknown, direct, times20, heuristic
    }

    /// Resolves `.automatic` to `.times20` for a body identified with certainty as X-Trans III or
    /// later, or GFX, and to `.unknown` otherwise; explicit policies pass through. ×20 beyond the
    /// bodies the record measured is app policy; the evidence and its limits are at
    /// `wbShiftScaleSource`. JPEG shift units are independent of PTP units.
    static func resolvedWBShiftScale(_ policy: WBShiftScale, cameraModel: String?) -> WBShiftScale {
        guard policy == .automatic else { return policy }
        return automaticWBShiftMapping(cameraModel: cameraModel) == nil ? .unknown : .times20
    }

    private static func automaticWBShiftMapping(cameraModel: String?)
        -> (modelID: String, basis: String, source: String)? {
        guard let cameraModel else { return nil }
        let model: CameraModel
        switch CameraModelRegistry.shared.identify(productName: cameraModel) {
        case .exact(let identified), .alias(let identified, _): model = identified
        case .heuristic, .unlisted, .unknown: return nil
        }
        // An explicit allow-list, so a legacy body added to the registry isn't opted in.
        let modernSensors: Set<SensorGeneration> = [.xTransIII, .xTransIV, .xTransV, .gfx]
        let modernProcessors: Set<ProcessorGeneration> = [.xProcessorPro, .xProcessor4, .xProcessor5]
        guard model.id != CameraModelRegistry.demoModelID,
              modernSensors.contains(model.sensorGeneration), modernProcessors.contains(model.processor),
              model.id.hasPrefix("X") || model.id.hasPrefix("GFX") else { return nil }
        let basis: String
        switch model.id {
        case "X-T50", "X-T30": basis = "documented_model"
        case "X-H2": basis = "published_model"
        default: basis = "modern_camera_default"
        }
        return (model.id, basis, wbShiftScaleSource)
    }

    /// The reference's section on white balance scaling. It holds the evidence behind every basis
    /// above, with its limits, and links each upstream source at the revision it inspected.
    private static let wbShiftScaleSource =
        "https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/10-jpeg-recipes.md#white-balance-scaling"

    /// Synchronous and potentially slow on a large file (segment walk + ImageIO decode of a
    /// thumbnail), so callers run it off the main actor. Everything it returns is a value type
    /// (or, for `proxy`, a `UIImage` built off-thread), so crossing back is safe.
    ///
    /// Throws only when there's nothing at all to show: not a JPEG, a damaged one, or no EXIF in it
    /// (the errors `ExifParser.exifBlock` throws). After that, a MakerNote that is missing, foreign
    /// or malformed is recorded in `recipeStatus`, and `camera` still comes from ImageIO.
    static func read(_ data: Data, filename: String?, wbShiftScale: WBShiftScale = .automatic) throws -> PhotoRecipeReading {
        let block = try ExifParser.exifBlock(inJPEG: data)
        let make = ExifParser.make(in: block)
        let exifModel = ExifParser.model(in: block)
        let camera = cameraSnapshot(from: data, make: make, model: exifModel)

        var warnings: [String] = []
        var settings = RecipeSettings()
        var recipeExtras: [(label: String, value: String)] = []
        var rawTags: [(label: String, value: String)] = []
        var preservedMetadata: [String: JSONValue] = [:]
        var recordedWBShifts: [Int]?
        var recipeStatus: FujiRecipeStatus = .found
        var modelName = exifModel

        do {
            if let make, !make.uppercased().contains("FUJIFILM") {
                throw ExifError.notFujifilm(signature: nil, make: make)
            }
            let makerNoteRange = try ExifParser.makerNoteRange(in: block)
            let raw = try FujiMakerNote.parse(block.view, range: makerNoteRange)
            modelName = modelName ?? raw.strings[FujiMakerNote.Tag.fujiModel.rawValue]
                ?? raw.strings[FujiMakerNote.Tag.fujiModel2.rawValue]

            settings = decodeSettings(raw, warnings: &warnings, wbShiftScale: wbShiftScale,
                                      cameraModel: modelName)
            if settings == RecipeSettings() {
                warnings.append("The Fujifilm section is here but carries no recipe settings — some "
                    + "older bodies write a shorter version. Camera and exposure below still read fine.")
            }
            recipeExtras = extras(raw)
            rawTags = rawTagRows(raw)
            preservedMetadata = metadataToPreserve(raw, warnings: warnings, wbShiftScale: wbShiftScale,
                                                  cameraModel: modelName)
            recordedWBShifts = raw.lists[FujiMakerNote.Tag.whiteBalanceFineTune.rawValue]
        } catch let error as ExifError {
            switch error {
            case .notFujifilm(_, let camMake):
                // `camMake` is set when IFD0's own Make tag said something other than Fujifilm —
                // an unambiguous "wrong brand of camera". When it's nil, this came from
                // `FujiMakerNote.parse`'s signature check instead: the Make tag *did* say
                // Fujifilm, but the MakerNote itself isn't shaped like one, which is a corrupt or
                // foreign MakerNote rather than a real brand mismatch.
                recipeStatus = camMake != nil ? .notFujifilm(make: camMake) : .unreadable
            case .noMakerNote:
                recipeStatus = .noMakerNote
            case .notAJPEG, .unreadable, .malformedJPEG, .noExif, .malformedTIFF, .malformedMakerNote:
                recipeStatus = .unreadable
            }
        }

        // Any confidence will do here: this only seeds `authoredForModelID`, which decides nothing
        // about writing. A photo from a body the registry can't place gets no model.
        let modelID = modelName.flatMap { CameraModelRegistry.shared.identify(productName: $0).model?.id }

        return PhotoRecipeReading(
            filename: filename,
            recipeStatus: recipeStatus,
            settings: settings,
            camera: camera,
            modelID: modelID,
            extras: recipeExtras,
            warnings: warnings,
            rawTags: rawTags,
            preservedMetadata: preservedMetadata,
            recordedWBShifts: recordedWBShifts,
            // 1600 px on the long edge is enough for the Read Recipe preview.
            proxy: ImageDownsampler.downsample(data, maxLongEdge: 1600)
        )
    }

    // MARK: - Settings decode

    /// Interprets the MakerNote tags as recipe settings, appending to `warnings` the parser's
    /// issues and a note for each field it leaves unresolved. Tag interpretations follow the
    /// record: https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/10-jpeg-recipes.md#semantic-fields
    static func decodeSettings(_ raw: FujiMakerNote.Raw, warnings: inout [String],
                               wbShiftScale: WBShiftScale = .automatic,
                               cameraModel: String? = nil) -> RecipeSettings {
        var settings = RecipeSettings()
        warnings.append(contentsOf: raw.issues)

        // 0x1003 (Saturation) first: on a monochrome photo it carries the simulation itself (the
        // B&W / ACROS / Sepia family), and Color stays nil, since a monochrome recipe has no
        // saturation setting. Otherwise 0x1401 (FilmMode) gives the simulation, but only alongside
        // a recognised Color value: a missing or unknown 0x1003 leaves a monochrome override
        // unresolved, so FilmMode alone is only a candidate.
        let saturationTag = raw.ints[FujiMakerNote.Tag.saturation.rawValue]
        if let saturationTag, let monoSim = FujiMakerNote.monochromeSaturation[saturationTag] {
            settings.filmSimulation = monoSim
        } else {
            if let filmModeTag = raw.ints[FujiMakerNote.Tag.filmMode.rawValue] {
                if let sim = FujiMakerNote.filmModes[filmModeTag],
                   let saturationTag, FujiMakerNote.saturation[saturationTag] != nil {
                    settings.filmSimulation = sim
                } else {
                    warnings.append("The film simulation isn't certain from these tags. The recorded "
                        + "FilmMode is preserved, but wasn't used to limit recipe matching.")
                }
            }
            if let saturationTag {
                if let color = FujiMakerNote.saturation[saturationTag] {
                    settings.color = color
                } else {
                    warnings.append("Saturation (Color) couldn't be read from this file.")
                }
            }
        }

        if let sharpnessTag = raw.ints[FujiMakerNote.Tag.sharpness.rawValue] {
            settings.sharpness = FujiMakerNote.sharpness[sharpnessTag]
        }
        if let nrTag = raw.ints[FujiMakerNote.Tag.highISONoiseReduction.rawValue] {
            settings.highISONR = FujiMakerNote.highISONoiseReduction[nrTag]
        }
        if let clarityTag = raw.ints[FujiMakerNote.Tag.clarity.rawValue] {
            if (-5000...5000).contains(clarityTag), clarityTag.isMultiple(of: 1000) {
                settings.clarity = clarityTag / 1000
            } else {
                warnings.append("Clarity has an unknown recorded value and was left unspecified.")
            }
        }
        if let shadowTag = raw.ints[FujiMakerNote.Tag.shadowTone.rawValue] {
            settings.shadowTone = Double(-shadowTag) / 16
        }
        if let highlightTag = raw.ints[FujiMakerNote.Tag.highlightTone.rawValue] {
            settings.highlightTone = Double(-highlightTag) / 16
        }

        settings.grain = decodeGrain(raw, warnings: &warnings)
        settings.whiteBalance = decodeWhiteBalance(raw, warnings: &warnings,
            scale: resolvedWBShiftScale(wbShiftScale, cameraModel: cameraModel))
        settings.dynamicRange = decodeDynamicRange(raw, warnings: &warnings)
        settings.dRangePriority = decodeDRangePriority(raw, warnings: &warnings)
        if let priority = raw.ints[FujiMakerNote.Tag.dRangePriority.rawValue], priority == 0 || priority == 1 {
            settings.dynamicRange = nil
            settings.highlightTone = nil
            settings.shadowTone = nil
            warnings.append("D-Range Priority controlled this image's dynamic range and tones. Their "
                + "recorded values are preserved as observations, not independent recipe choices.")
        }

        if let effectTag = raw.ints[FujiMakerNote.Tag.colorChromeEffect.rawValue] {
            settings.colorChromeEffect = FujiMakerNote.effectStrengths[effectTag]
        }
        if let fxBlueTag = raw.ints[FujiMakerNote.Tag.colorChromeFXBlue.rawValue] {
            settings.colorChromeFXBlue = FujiMakerNote.effectStrengths[fxBlueTag]
        }
        if settings.filmSimulation?.hasMonochromaticColor == true,
           let wc = raw.ints[FujiMakerNote.Tag.bwAdjustment.rawValue] {
            settings.monochromaticColorWC = wc
        }
        if settings.filmSimulation?.hasMonochromaticColor == true,
           let mg = raw.ints[FujiMakerNote.Tag.bwMagentaGreen.rawValue] {
            settings.monochromaticColorMG = mg
        }

        // RecipeSettings.noiseReduction is the older name for High ISO NR, which `highISONR` above
        // already carries, so nothing is set here. The record names an older `0x100B`
        // NoiseReduction tag but gives it no decoding (zgrimz/fujifilm-ptp-reference
        // `docs/10-jpeg-recipes.md`).
        // exposureBias is never set either: the frame's EV is `CameraSnapshot.exposureBias`, read
        // from standard Exif (0x9204) in cameraSnapshot(from:make:model:).

        return settings
    }

    private static func decodeGrain(_ raw: FujiMakerNote.Raw, warnings: inout [String]) -> GrainEffect? {
        guard let roughnessTag = raw.ints[FujiMakerNote.Tag.grainEffectRoughness.rawValue],
              let strength = FujiMakerNote.grainStrengths[roughnessTag] else { return nil }
        if strength == .off {
            // A body reporting Off never has a meaningful size — GrainEffect.off keeps size nil,
            // and RecipeMatcher's grain rule treats any Off/Off pair as a match regardless of size.
            return GrainEffect(strength: .off, size: nil)
        }
        let sizeTag = raw.ints[FujiMakerNote.Tag.grainEffectSize.rawValue]
        if sizeTag == 0 {
            warnings.append("Grain strength is nonzero but its recorded size is Off. Grain was left "
                + "unspecified, and both recorded values are preserved.")
            return nil
        }
        return GrainEffect(strength: strength, size: sizeTag.flatMap { FujiMakerNote.grainSizes[$0] })
    }

    private static func decodeWhiteBalance(_ raw: FujiMakerNote.Raw, warnings: inout [String],
                                           scale: WBShiftScale) -> WhiteBalance? {
        guard let modeTag = raw.ints[FujiMakerNote.Tag.whiteBalance.rawValue] else { return nil }
        guard let mode = FujiMakerNote.whiteBalanceModes[modeTag] else {
            warnings.append((0xf00...0xf04).contains(modeTag)
                ? "This photo was shot with a custom (measured) white balance, which a recipe can't "
                    + "carry. Its slot identity is preserved in the metadata, but wasn't included in matching."
                : "White balance couldn't be matched to a mode this app models. Its recorded value is "
                    + "preserved in the metadata, but wasn't included in matching.")
            return nil
        }

        guard let shifts = raw.lists[FujiMakerNote.Tag.whiteBalanceFineTune.rawValue], shifts.count == 2 else {
            warnings.append("WB shifts are missing or malformed. White balance was left unspecified; "
                + "the recorded mode is preserved in the metadata.")
            return nil
        }
        let divisor: Int
        switch scale {
        case .automatic, .unknown:
            warnings.append("White balance couldn't be recovered for this camera. The recorded "
                + "values are preserved in the metadata, and white balance was left unspecified.")
            return nil
        case .direct: divisor = 1
        case .times20: divisor = 20
        case .heuristic:
            divisor = shifts.contains(where: { abs($0) > 9 }) ? 20 : 1
        }
        guard shifts.allSatisfy({ $0.isMultiple(of: divisor) && (-9...9).contains($0 / divisor) }) else {
            warnings.append("WB shifts don't form whole steps within −9…+9. "
                + "White balance was left unspecified, and the raw pair is preserved.")
            return nil
        }
        if scale == .heuristic {
            warnings.append("WB shifts use an inferred scale. This is an interpretation of the values, "
                + "not a verified rule for this camera.")
        }
        let kelvin = mode.usesKelvin ? raw.ints[FujiMakerNote.Tag.colorTemperature.rawValue] : nil
        guard !mode.usesKelvin || (kelvin ?? 0) > 0 else {
            warnings.append("The Kelvin white balance has no usable temperature and was left unspecified.")
            return nil
        }
        return WhiteBalance(mode: mode, shiftRed: shifts[0] / divisor, shiftBlue: shifts[1] / divisor, kelvin: kelvin)
    }

    private static func decodeDynamicRange(_ raw: FujiMakerNote.Raw, warnings: inout [String]) -> DynamicRange? {
        guard let settingTag = raw.ints[FujiMakerNote.Tag.dynamicRangeSetting.rawValue] else { return nil }
        if settingTag == 0x000 { return .auto }
        if settingTag == 1, let developedTag = raw.ints[FujiMakerNote.Tag.developmentDynamicRange.rawValue] {
            switch developedTag {
            case 100: return .dr100
            case 200: return .dr200
            case 400: return .dr400
            default: break
            }
        }
        switch settingTag {
        case 0x100: return .dr100
        case 0x201: return .dr400
        default:
            warnings.append(settingTag == 0x200
                ? "The JPEG records legacy Wide1 (230%), which isn't a portable DR200 setting. Dynamic range was left unspecified."
                : "Dynamic range couldn't be recovered as a recipe choice. Its recorded values are preserved in the metadata.")
            return nil
        }
    }

    /// Absence is unknown. Auto's selected strength remains an observation, never a Fixed choice.
    private static func decodeDRangePriority(_ raw: FujiMakerNote.Raw, warnings: inout [String]) -> DRangePriority? {
        guard let modeTag = raw.ints[FujiMakerNote.Tag.dRangePriority.rawValue] else { return nil }
        if modeTag == 0 { return .auto }
        guard modeTag == 1, let fixedTag = raw.ints[FujiMakerNote.Tag.dRangePriorityFixed.rawValue],
              let strength = FujiMakerNote.dRangePriorityFixedStrengths[fixedTag] else {
            warnings.append("D-Range Priority is unresolved and was left unspecified; its recorded values are preserved.")
            return nil
        }
        return strength
    }

    static func metadataToPreserve(_ raw: FujiMakerNote.Raw, warnings: [String],
                                   wbShiftScale: WBShiftScale,
                                   cameraModel: String? = nil) -> [String: JSONValue] {
        let resolved = resolvedWBShiftScale(wbShiftScale, cameraModel: cameraModel)
        let mapping = wbShiftScale == .automatic ? automaticWBShiftMapping(cameraModel: cameraModel) : nil
        var metadata: [String: JSONValue] = [
            "schema": .string("fuji-cookbook-jpeg-observations/1"),
            "mappingSource": .string("fujifilm-ptp-reference JPEG mappings; ExifTool 13.55"),
            "whiteBalanceShiftPolicy": .string(wbShiftScale.rawValue),
            "resolvedWhiteBalanceShiftScale": .string(resolved.rawValue),
            "whiteBalanceShiftBasis": .string(mapping?.basis
                ?? (wbShiftScale == .automatic ? "unresolved" : "explicit_policy")),
            "tags": .array(raw.observations.map(\.json)),
            "warnings": .array(warnings.map(JSONValue.string))
        ]
        if let mapping {
            metadata["whiteBalanceShiftModel"] = .string(mapping.modelID)
            metadata["whiteBalanceShiftSource"] = .string(mapping.source)
        }
        return ["jpegRecipeMetadata": .object(metadata)]
    }

    // MARK: - Extras (not part of a recipe, but worth showing)

    private static func extras(_ raw: FujiMakerNote.Raw) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let cropTag = raw.ints[FujiMakerNote.Tag.cropMode.rawValue],
           let crop = FujiMakerNote.cropModes[cropTag], crop != "n/a" {
            rows.append(("Crop Mode", crop))
        }
        if let shutterTag = raw.ints[FujiMakerNote.Tag.shutterType.rawValue],
           let shutter = FujiMakerNote.shutterTypes[shutterTag] {
            rows.append(("Shutter Type", shutter))
        }
        return rows
    }

    // MARK: - Diagnostics

    private static func rawTagRows(_ raw: FujiMakerNote.Raw) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        for (tag, value) in raw.ints.sorted(by: { $0.key < $1.key }) {
            rows.append((PTPHex.code(tag), "\(value)"))
        }
        for (tag, values) in raw.lists.sorted(by: { $0.key < $1.key }) {
            rows.append((PTPHex.code(tag), values.map(String.init).joined(separator: ", ")))
        }
        for (tag, text) in raw.strings.sorted(by: { $0.key < $1.key }) {
            rows.append((PTPHex.code(tag), text))
        }
        for entry in raw.unmapped.sorted(by: { $0.tag < $1.tag }) {
            rows.append((PTPHex.code(entry.tag), "\(entry.type.debugName) × \(entry.count), unmapped"))
        }
        return rows
    }

    // MARK: - General EXIF via ImageIO

    private static func cameraSnapshot(from data: Data, make: String?, model: String?) -> CameraSnapshot {
        var snapshot = CameraSnapshot(make: make, model: model)
        if let pixelSize = ImageDownsampler.pixelSize(of: data) {
            snapshot.pixelWidth = Int(pixelSize.width)
            snapshot.pixelHeight = Int(pixelSize.height)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let all = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return snapshot
        }
        let exif = all[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = all[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        snapshot.lens = (exif[kCGImagePropertyExifLensModel] as? String)
        snapshot.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        snapshot.focalLength35mm = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.intValue
        snapshot.fNumber = exif[kCGImagePropertyExifFNumber] as? Double
        snapshot.exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Any], let first = isoArray.first as? NSNumber {
            snapshot.iso = first.intValue
        }
        snapshot.exposureBias = exif[kCGImagePropertyExifExposureBiasValue] as? Double
        snapshot.captureDate = (exif[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(Self.exifDateFormatter.date(from:))

        if snapshot.make == nil { snapshot.make = tiff[kCGImagePropertyTIFFMake] as? String }
        if snapshot.model == nil { snapshot.model = tiff[kCGImagePropertyTIFFModel] as? String }
        return snapshot
    }

    /// Exif dates are "yyyy:MM:dd HH:mm:ss" — not ISO 8601, so `ISO8601DateFormatter` won't parse it.
    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
