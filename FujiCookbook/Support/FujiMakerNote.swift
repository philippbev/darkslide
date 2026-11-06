import Foundation

/// The Fujifilm MakerNote: header, tag table, and the raw value mappings, as ExifTool documents
/// them (<https://exiftool.org/TagNames/FujiFilm.html>, the most complete, most cross-checked
/// reference for this format); the ExifTool version it follows is pinned in
/// zgrimz/fujifilm-ptp-reference `docs/10-jpeg-recipes.md#evidence-and-source-revision`. Produces
/// raw, still-Fuji-domain values; `PhotoRecipeReader` is what turns them into `RecipeSettings`.
///
/// **This is not `FujiEncoding`.** The MakerNote numbers the same settings differently from the
/// PTP encoding `FujiEncoding` writes to the camera (here film simulation is 0x000…0xb00 and grain
/// 0/32/64). The two come from independent sources, and that is what makes the closed loop a
/// check: a recipe developed in the camera and read back from the JPEG's MakerNote confirms the
/// push only while this file never reaches for `FujiEncoding`.
enum FujiMakerNote {

    /// Recipe-bearing (and a few display-only) tags, named as ExifTool names them so the
    /// diagnostics dump and an `exiftool -FujiFilm:all` comparison read side by side.
    enum Tag: UInt16 {
        case serialNumber = 0x0010
        case sharpness = 0x1001
        case whiteBalance = 0x1002
        case saturation = 0x1003
        case colorTemperature = 0x1005
        case whiteBalanceFineTune = 0x100A
        case highISONoiseReduction = 0x100E
        case clarity = 0x100F
        case shadowTone = 0x1040
        case highlightTone = 0x1041
        case grainEffectRoughness = 0x1047
        case colorChromeEffect = 0x1048
        case bwAdjustment = 0x1049
        case bwMagentaGreen = 0x104B
        case grainEffectSize = 0x104C
        case cropMode = 0x104D
        case colorChromeFXBlue = 0x104E
        case shutterType = 0x1050
        case filmMode = 0x1401
        case dynamicRangeSetting = 0x1402
        case developmentDynamicRange = 0x1403
        case dRangePriority = 0x1443
        case dRangePriorityAuto = 0x1444
        case dRangePriorityFixed = 0x1445
        case fujiModel = 0x1447
        case fujiModel2 = 0x1448
    }

    /// Every tag this parser recognises, before interpretation. Flat and untyped on purpose: the
    /// diagnostics dump renders it directly, and it keeps the mapping step in `PhotoRecipeReader`
    /// readable — one dictionary lookup per tag instead of re-walking the IFD.
    struct Raw {
        var ints: [UInt16: Int] = [:]
        /// Multi-component entries — today only 0x100A (WhiteBalanceFineTune, Red then Blue).
        var lists: [UInt16: [Int]] = [:]
        var strings: [UInt16: String] = [:]
        /// Every entry this file doesn't have a case for, kept for the diagnostics dump.
        var unmapped: [(tag: UInt16, type: TIFFType, count: Int)] = []
        /// Filtered structural and numeric evidence, kept separately from interpreted settings.
        /// No serials, arbitrary text, or unknown tag payloads enter a saved recipe.
        var observations: [Observation] = []
        var issues: [String] = []
    }

    struct Observation {
        var tag: UInt16
        var type: TIFFType
        var count: Int
        var status: String
        var values: [Int]?

        var json: JSONValue {
            var value: [String: JSONValue] = [
                "tag": .string(String(format: "0x%04X", tag)),
                "type": .number(Double(type.rawValue)),
                "count": .number(Double(count)),
                "status": .string(status)
            ]
            if let values { value["rawValues"] = .array(values.map { .number(Double($0)) }) }
            return .object(value)
        }
    }

    private static let signature: [UInt8] = Array("FUJIFILM".utf8)

    /// Parse a MakerNote sitting at `range` inside `view` (the whole file). `range.lowerBound` is
    /// the MakerNote's own start — the "FUJIFILM" signature, then a little-endian IFD offset
    /// relative to that same start, then a normal IFD, always little-endian regardless of the
    /// outer TIFF's order. Both facts fall out of building a second `TIFFBlock` at this base, so
    /// the walker that reads the file's main Exif block reads this one too.
    static func parse(_ view: ByteView, range: Range<Int>) throws -> Raw {
        let makerNoteStart = range.lowerBound
        guard makerNoteStart >= 0, range.upperBound <= view.count, range.count >= 12 else {
            throw ExifError.malformedMakerNote
        }
        guard view.matches(signature, at: makerNoteStart) else {
            let found = view.ascii(at: makerNoteStart, count: 8)
            throw ExifError.notFujifilm(signature: found, make: nil)
        }
        let little = view.reordered(.little)
        guard let ifdOffset = little.u32(at: makerNoteStart + 8), ifdOffset >= 12 else {
            throw ExifError.malformedMakerNote
        }
        let block = TIFFBlock(view: little, base: makerNoteStart, end: range.upperBound,
                              ifd0Offset: Int(ifdOffset))
        let entries = try block.ifd(at: block.ifd0Offset, hasNextPointer: false)
        let counts = Dictionary(grouping: entries, by: \.tag).mapValues(\.count)
        let integerTypes: Set<TIFFType> = [.byte, .short, .long, .sbyte, .undefined, .sshort, .slong]

        var raw = Raw()
        for entry in entries {
            // Serials and model text are not recipe evidence. Model text remains available for
            // identifying the source body, but never enters the portable metadata record.
            if entry.tag == Tag.serialNumber.rawValue { continue }
            guard let known = Tag(rawValue: entry.tag) else {
                raw.unmapped.append((entry.tag, entry.type, entry.count))
                raw.observations.append(Observation(tag: entry.tag, type: entry.type, count: entry.count,
                                                    status: "not_exported", values: nil))
                continue
            }
            if known == .fujiModel || known == .fujiModel2 {
                if counts[entry.tag] == 1, entry.type == .ascii, entry.count <= 256,
                   let text = block.string(entry) { raw.strings[entry.tag] = text }
                continue
            }
            let numeric = integerTypes.contains(entry.type)
            let values = numeric && entry.count <= 8 ? block.ints(entry) : []
            let valid = numeric && entry.count == (known == .whiteBalanceFineTune ? 2 : 1)
                && (known != .whiteBalanceFineTune || entry.type == .slong)
                && values.count == entry.count
            let status = counts[entry.tag] != 1 ? "ambiguous" : (valid ? "recorded" : "malformed")
            raw.observations.append(Observation(tag: entry.tag, type: entry.type, count: entry.count,
                                                status: status, values: values.isEmpty ? nil : values))
            guard status == "recorded" else {
                let label = String(format: "0x%04X", entry.tag)
                let issue = "Metadata tag \(label) is \(status) and wasn't used as a recipe setting."
                if !raw.issues.contains(issue) { raw.issues.append(issue) }
                continue
            }
            switch known {
            case .whiteBalanceFineTune:
                raw.lists[entry.tag] = values
            case .serialNumber, .fujiModel, .fujiModel2:
                break
            case .bwAdjustment, .bwMagentaGreen:
                // ExifTool reads these two as int8 whatever type the entry declares; read the first
                // byte as signed to match.
                if let range = try? block.valueRange(of: entry), let value = little.i8(at: range.lowerBound) {
                    raw.ints[entry.tag] = Int(value)
                }
            default:
                raw.ints[entry.tag] = values.first
            }
        }
        return raw
    }

    // MARK: - Value tables (as ExifTool's FujiFilm tag reference documents them)

    /// 0x1001 Sharpness. PrintHex values, not a linear scale — −1 (0x82) and +1 (0x84) sit off the
    /// otherwise-sequential 0x00…0x06 run.
    static let sharpness: [Int: Int] = [
        0x00: -4, 0x01: -3, 0x02: -2, 0x82: -1, 0x03: 0, 0x84: 1, 0x04: 2, 0x05: 3, 0x06: 4
    ]

    /// 0x1002 WhiteBalance. Fuji's "Cloudy" is this app's `.shade`.
    static let whiteBalanceModes: [Int: WhiteBalanceMode] = [
        0x0: .auto, 0x1: .autoWhitePriority, 0x2: .autoAmbiencePriority,
        0x100: .daylight, 0x200: .shade,
        0x300: .fluorescent1, 0x301: .fluorescent2, 0x302: .fluorescent3,
        0x400: .incandescent, 0x600: .underwater,
        0xff0: .kelvin
        // 0x500 Flash and 0xf00–0xf04 Custom 1–5 have no counterpart in this app's model — a custom
        // white balance is a measurement stored on one camera, not a recipe parameter. A photo
        // reporting one is handled by `PhotoRecipeReader` as an unmapped mode, not a lookup failure.
    ]

    /// 0x1003 Saturation, the non-monochrome half. Kept separate from `monochromeSaturation`
    /// because which table applies is a branch `PhotoRecipeReader` makes explicitly — mixing them
    /// into one dictionary would hide that 0x1003 does double duty.
    static let saturation: [Int: Int] = [
        0x000: 0, 0x080: 1, 0x100: 2, 0x0c0: 3, 0x0e0: 4,
        0x180: -1, 0x400: -2, 0x4c0: -3, 0x4e0: -4
    ]

    /// 0x1003's other half: when Saturation carries one of these codes, the photo is monochrome and
    /// this — not 0x1401 FilmMode — is the film simulation. Order matters at the call site: check
    /// this table before falling back to `filmModes`.
    static let monochromeSaturation: [Int: FilmSimulation] = [
        0x300: .monochrome, 0x301: .monochromeR, 0x302: .monochromeYe, 0x303: .monochromeG,
        0x310: .sepia,
        0x500: .acros, 0x501: .acrosR, 0x502: .acrosYe, 0x503: .acrosG
    ]

    /// 0x1401 FilmMode — the colour simulations. Values are `PrintHex`; note they do not align
    /// with `FujiEncoding.filmSimToByte`, which is a different, PTP-only encoding (see the type
    /// doc comment).
    static let filmModes: [Int: FilmSimulation] = [
        0x000: .provia, 0x120: .astia, 0x200: .velvia, 0x400: .velvia,
        0x500: .proNegStd, 0x501: .proNegHi, 0x600: .classicChrome, 0x700: .eterna,
        0x800: .classicNeg, 0x900: .eternaBleachBypass, 0xa00: .nostalgicNeg, 0xb00: .realaAce
    ]

    /// 0x100E High ISO NR (maps to `RecipeSettings.highISONR`).
    static let highISONoiseReduction: [Int: Int] = [
        0x000: 0, 0x180: 1, 0x100: 2, 0x1c0: 3, 0x1e0: 4,
        0x280: -1, 0x200: -2, 0x2c0: -3, 0x2e0: -4
    ]

    /// 0/32/64 → Off/Weak/Strong: 0x1048 Color Chrome Effect and 0x104E Color Chrome FX Blue as
    /// `EffectStrength`, 0x1047 Grain Roughness as `GrainStrength`.
    static let effectStrengths: [Int: EffectStrength] = [0: .off, 32: .weak, 64: .strong]
    static let grainStrengths: [Int: GrainStrength] = [0: .off, 32: .weak, 64: .strong]
    /// 0x104C GrainEffectSize. 0 ("Off") deliberately has no entry: it means no size was set, which
    /// `PhotoRecipeReader` reads as `nil` — matching `GrainEffect.off`, whose `size` is also `nil`.
    static let grainSizes: [Int: GrainSize] = [16: .small, 32: .large]

    static let cropModes: [Int: String] = [
        0: "n/a", 1: "Full-frame on GFX", 2: "Sports Finder Mode",
        4: "Electronic Shutter 1.25x Crop", 8: "Digital Tele-Conv"
    ]

    static let shutterTypes: [Int: String] = [
        0: "Mechanical", 1: "Electronic", 2: "Electronic (long shutter speed)",
        3: "Electronic Front Curtain"
    ]

    /// 0x1445 DRangePriorityFixed — only meaningful when 0x1443 (DRangePriority) is Fixed (1).
    /// When 0x1443 is Auto (0), `RecipeSettings.dRangePriority` is simply `.auto`: the app's model
    /// has no "Auto, but weak" distinction, so 0x1444 (DRangePriorityAuto) has nothing to map to
    /// and is display-only, surfaced through `rawTags` rather than a table here.
    static let dRangePriorityFixedStrengths: [Int: DRangePriority] = [1: .weak, 2: .strong]
}
