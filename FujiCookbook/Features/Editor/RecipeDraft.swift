import Foundation

/// The editor's working copy of a recipe: every form field as a plain value, unpacked from the
/// model on entry and repacked on Save. Keeping the field ↔ settings round-trip in one value type
/// stops the view's state and the save path from drifting apart.
struct RecipeDraft: Equatable {
    // Metadata
    var name: String
    var cameraName: String
    var credit: String
    var notes: String
    var tagsText: String
    var isFavorite: Bool
    var modelID: String?   // nil == Generic (all fields)

    // Parameters
    //
    // Optional on purpose, every one of them — `RecipeSettings` uses `nil` for "this recipe
    // doesn't set the field", and a draft that can't hold that has to invent something on Save,
    // turning a four-field scan into a sixteen-field recipe of zeroes it never contained —
    // permanently, in SwiftData and in exported JSON. The two wire paths read the difference, so
    // this is never only a tidiness problem:
    //
    // - Push (`FujiPresetCodec.encode`): unset High ISO NR passes the slot's bytes through; 0
    //   writes 0.
    // - Develop (`FujiRawConvProfile.patch`): *every* field is written only when set, so the RAF
    //   keeps its as-shot sentinel — and that file's own comment says writing defaults into unset
    //   fields corrupts the conversion.
    //
    // So for the fields `init(from:)` leaves alone — white balance, the tones, Color, Sharpness,
    // High ISO NR, Clarity, Monochromatic Color — the editor shows "Not set" wherever the recipe
    // means it, and setting or clearing one is something the user does, not something opening the
    // form does for them. The six a recipe must carry a value for are defaulted there instead.
    //
    // `grainSize`, the WB shifts and `kelvin` stay non-optional: they live *inside* `GrainEffect`
    // and `WhiteBalance`, which only exist once their discriminator does. Here they are the
    // remembered value those structs get when one is created.
    var filmSim: FilmSimulation?
    var grainStrength: GrainStrength?
    var grainSize: GrainSize
    var colorChrome: EffectStrength?
    var colorChromeFXBlue: EffectStrength?
    var wbMode: WhiteBalanceMode?
    var wbShiftR: Int
    var wbShiftB: Int
    var kelvin: Int
    var dynamicRange: DynamicRange?
    var dRangePriority: DRangePriority?
    var highlightTone: Double?
    var shadowTone: Double?
    var color: Int?
    var sharpness: Int?
    var highISONR: Int?
    var clarity: Int?
    var monoWC: Int?
    var monoMG: Int?

    /// The recipe's values as the editor opened it, which ``hasChanges`` unpacks again to compare
    /// against. A copy of the values, not the `Recipe`, so ``hasChanges`` counts only edits made in
    /// the form, whatever writes to the `Recipe` while the editor is open; and not a `RecipeDraft`,
    /// because a struct can't hold a copy of itself.
    private let opened: Opened

    init(from recipe: Recipe) {
        self.init(opening: Opened(recipe))
    }

    private init(opening opened: Opened) {
        self.opened = opened
        let s = opened.settings
        name = opened.name
        cameraName = opened.cameraName ?? ""
        credit = opened.credit ?? ""
        notes = opened.notes
        tagsText = opened.tags.joined(separator: ", ")
        isFavorite = opened.isFavorite
        modelID = opened.modelID
        // Six fields a recipe must carry a value for, defaulted on the way into the editor rather
        // than migrated in the store: a recipe is a description of a look, and one that leaves a
        // field out would inherit the destination bank's — so the same recipe produces two looks
        // on two cameras and the push calls both "written and verified". The defaults are the
        // neutral reading of "no opinion": the effect is off, the camera decides the dynamic range,
        // and the film simulation is the one an empty bank is seeded with.
        //
        // Nothing is written back until the recipe is next saved, so a library nobody edits is
        // untouched — and the push applies the same defaults regardless, so the two always agree.
        filmSim = s.filmSimulation ?? .provia
        grainStrength = s.grain?.strength ?? .off
        grainSize = s.grain?.size ?? .small
        colorChrome = s.colorChromeEffect ?? .off
        colorChromeFXBlue = s.colorChromeFXBlue ?? .off
        wbMode = s.whiteBalance?.mode
        wbShiftR = s.whiteBalance?.shiftRed ?? 0
        wbShiftB = s.whiteBalance?.shiftBlue ?? 0
        kelvin = s.whiteBalance?.kelvin ?? 5500
        dynamicRange = s.dynamicRange ?? .auto
        dRangePriority = s.dRangePriority ?? .off
        highlightTone = s.highlightTone
        shadowTone = s.shadowTone
        color = s.color
        sharpness = s.sharpness
        highISONR = s.highISONR
        clarity = s.clarity
        monoWC = s.monochromaticColorWC
        monoMG = s.monochromaticColorMG
    }

    /// What `init(from:)` reads from a recipe.
    private struct Opened: Equatable {
        let name: String
        let cameraName: String?
        let credit: String?
        let notes: String
        let tags: [String]
        let isFavorite: Bool
        let modelID: String?
        let settings: RecipeSettings

        init(_ recipe: Recipe) {
            name = recipe.name
            cameraName = recipe.cameraName
            credit = recipe.credit
            notes = recipe.notes
            tags = recipe.tags
            isFavorite = recipe.isFavorite
            modelID = recipe.authoredForModelID
            settings = recipe.settings
        }
    }

    /// Whether the form holds anything it didn't open with. Undoing an edit by hand clears it, so
    /// the editor asks before discarding only when there is something to lose. The comparison is
    /// of the form's fields, including the values hidden rows remember (a Kelvin temperature with
    /// no white balance mode), so it errs towards asking.
    var hasChanges: Bool { self != RecipeDraft(opening: opened) }

    // MARK: Model-derived context (drives field filtering and ranges)

    var model: CameraModel? { modelID.flatMap { CameraModelRegistry.shared.model(withID: $0) } }
    var fields: Set<RecipeField> { model?.supportedFields ?? Set(RecipeField.allCases) }
    var filmOptions: [FilmSimulation] { model?.supportedFilmSimulations ?? FilmSimulation.allCases.map { $0 } }
    /// The draft's own film simulation rather than the saved recipe's, so the form re-filters as
    /// soon as the picker changes. The rule itself lives in `RecipeApplicability`.
    var isMono: Bool { RecipeApplicability.isMonochrome(filmSim) }
    /// The Monochromatic Color magenta–green stepper row, hidden on the bodies with the warm–cool
    /// axis alone (`RecipeApplicability.hasMagentaGreenAxis`). Display only: the repack keeps
    /// `monoMG` regardless, so a value read from a bank survives a Save.
    var showMG: Bool { RecipeApplicability.hasMagentaGreenAxis(on: model) }
    /// The draft's white balance mode where the camera profile's menu lacks it — the Auto
    /// priorities on an X100V, Kelvin on an X-M1 — or nil. Display only: Save keeps the mode, as
    /// the push does, so `changesOnSave` says nothing about it and the footer does.
    var unsupportedWhiteBalanceMode: WhiteBalanceMode? {
        guard let wbMode, let model, !model.supports(whiteBalanceMode: wbMode) else { return nil }
        return wbMode
    }
    /// Whether the Monochromatic Color axes exist for this draft's simulation. Narrower than
    /// ``isMono`` — Sepia is monochrome and already toned, and the camera greys the control.
    var showMonochromaticColor: Bool { RecipeApplicability.hasMonochromaticColor(filmSim) }
    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The slot name this recipe gets if the user doesn't type one — shown as the field's grey
    /// placeholder. Derived from the draft's own `name` rather than the saved recipe's stored
    /// default, so it tracks live as the Name field is typed instead of showing a stale value (a
    /// brand-new recipe would otherwise sit on "New Recipe" for the whole editing session).
    var generatedSlotName: String {
        CameraSlotName.generate(from: name, fallback: filmSim?.displayName)
    }

    func range(_ field: RecipeField) -> NumericRange {
        model?.range(for: field) ?? DefaultRanges.range(for: field)
    }

    // MARK: Repack

    /// The settings Save writes. A field is kept only where the profile has it and the draft holds
    /// a value, so Save never writes values the recipe didn't set.
    func assembleSettings() -> RecipeSettings {
        var s = RecipeSettings()
        s.filmSimulation = filmSim
        if fields.contains(.grain), let grainStrength {
            s.grain = GrainEffect(strength: grainStrength,
                                  size: (grainStrength != .off
                                         && RecipeApplicability.hasGrainSizeControl(on: model)) ? grainSize : nil)
        }
        if fields.contains(.colorChromeEffect) { s.colorChromeEffect = colorChrome }
        if fields.contains(.colorChromeFXBlue) { s.colorChromeFXBlue = colorChromeFXBlue }
        if fields.contains(.whiteBalance), let wbMode {
            s.whiteBalance = WhiteBalance(mode: wbMode, shiftRed: wbShiftR, shiftBlue: wbShiftB,
                                          kelvin: wbMode.usesKelvin ? kelvin : nil)
        }
        if fields.contains(.dynamicRange) { s.dynamicRange = dynamicRange }
        if fields.contains(.dRangePriority) { s.dRangePriority = dRangePriority }
        if fields.contains(.highlightTone) { s.highlightTone = highlightTone.map { range(.highlightTone).clamp($0) } }
        if fields.contains(.shadowTone) { s.shadowTone = shadowTone.map { range(.shadowTone).clamp($0) } }
        if fields.contains(.color) && !isMono { s.color = color.map { Int(range(.color).clamp(Double($0))) } }
        if fields.contains(.sharpness) { s.sharpness = sharpness.map { Int(range(.sharpness).clamp(Double($0))) } }
        if fields.contains(.highISONR) { s.highISONR = highISONR.map { Int(range(.highISONR).clamp(Double($0))) } }
        if fields.contains(.clarity) { s.clarity = clarity.map { Int(range(.clarity).clamp(Double($0))) } }
        // Toning is the one numeric field Save does not clamp. Its range is an operational cap on
        // the bodies that use `CameraModelRegistry.rangesModern` rather than a measurement, and a value
        // read from a bank is the camera's own; the push and the develop clamp at write time and
        // say so. The MG axis is kept even where its row is hidden, for the same reason.
        if fields.contains(.monochromaticColor) && showMonochromaticColor {
            s.monochromaticColorWC = monoWC
            s.monochromaticColorMG = monoMG
        }
        return s
    }

    // MARK: What Save changes under this profile

    /// One thing Save does to a setting because of the camera profile: drops a field the body has
    /// no control for, or changes a value to fit the body — a clamp to its range, or a grain size a
    /// strength-only body cannot keep.
    enum ProfileChange: Equatable {
        case dropped(RecipeField, value: String)
        case changed(RecipeField, from: String, to: String)
    }

    /// What Save would do to the draft's values under the chosen profile that it would not do
    /// under Generic. Computed by running the same `assembleSettings()` both ways and comparing
    /// the rendered rows, so the notice and the Save cannot disagree. Empty for Generic, and for a
    /// profile that takes every value as entered. A neutral value on a body without the control —
    /// a Clarity of 0, toning at 0 — is not listed: dropping it changes no look.
    func changesOnSave() -> [ProfileChange] {
        guard model != nil else { return [] }
        var generic = self
        generic.modelID = nil
        let wideSettings = generic.assembleSettings()
        let narrow = Dictionary(uniqueKeysWithValues:
            RecipeSettingsFormatter.rows(for: assembleSettings()).map { ($0.field, $0.value) })
        return RecipeSettingsFormatter.rows(for: wideSettings).compactMap { row in
            guard let after = narrow[row.field] else {
                if RecipeCameraFit.isNeutral(row.field, in: wideSettings) { return nil }
                return .dropped(row.field, value: row.value)
            }
            return after == row.value ? nil : .changed(row.field, from: row.value, to: after)
        }
    }

    /// Write the draft's fields and settings back to the recipe. Staged photos are committed
    /// separately (`PhotoDraft.commit`), and the caller stamps `recipe.touch()`.
    func apply(to recipe: Recipe) {
        recipe.setSettings(assembleSettings())
        // `setName` also trims newlines — a pasted name otherwise keeps its trailing newline.
        recipe.setName(name)
        // The field holds the override only; empty means "use the generated default". Sanitized,
        // not just trimmed: the live filter leaves spacing alone, and `sanitize` puts it in the
        // form the camera stores.
        let override = CameraSlotName.sanitize(cameraName)
        recipe.cameraName = override.isEmpty ? nil : override
        let trimmedCredit = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.credit = trimmedCredit.isEmpty ? nil : trimmedCredit
        recipe.notes = notes
        recipe.tags = tagsText.split(whereSeparator: { $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        recipe.isFavorite = isFavorite
        recipe.authoredForModelID = modelID
    }
}
