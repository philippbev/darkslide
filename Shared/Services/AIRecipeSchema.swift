import Foundation

/// The JSON-schema fragment describing one recipe's fields, for the scanner's `extract_recipe`
/// tool. Every enum field is constrained to this app's stable raw values (see `RecipeEnums.swift`),
/// and every numeric field to the range its editor already enforces (``DefaultRanges``, and
/// `CameraModelRegistry`'s white-balance shift and Kelvin ranges).
enum AIRecipeSchema {

    /// What a screenshot has to show before a name becomes a credit.
    ///
    /// This is an enum rather than a sentence in the prompt because "a name is visible" and "this
    /// person made it" are different claims, and a repost carries the first without the second.
    /// There is deliberately no value for "unknown": a model that can't point at its evidence can't
    /// name a basis, and `AIRecipePayload` drops any credit that arrives without one.
    enum CreditBasis: String, CaseIterable {
        /// The recipe itself names its author — "Recipe by Northlight".
        case statedByLine = "STATED_BY_LINE"
        /// The poster's own caption claims it — "I made a recipe I can't stop using".
        case posterClaimedAuthorship = "POSTER_CLAIMED_AUTHORSHIP"
    }

    static func recipeProperties() -> [String: Any] {
        func opt(_ values: [String], _ description: String) -> [String: Any] {
            ["type": "string", "enum": values, "description": description]
        }
        func num(_ field: RecipeField, _ description: String) -> [String: Any] {
            bounded(DefaultRanges.range(for: field), description)
        }
        let strengths = EffectStrength.allCases.map(\.rawValue)
        let wbShift = CameraModelRegistry.whiteBalanceShiftRange
        return [
            "name": ["type": "string", "description": "Recipe title."],
            "filmSimulation": opt(FilmSimulation.allCases.map(\.rawValue), "Base film simulation."),
            "grainStrength": opt(GrainStrength.allCases.map(\.rawValue), "Grain effect strength."),
            "grainSize": opt(GrainSize.allCases.map(\.rawValue), "Grain size, if set."),
            "colorChromeEffect": opt(strengths, "Color Chrome Effect."),
            "colorChromeFXBlue": opt(strengths, "Color Chrome FX Blue."),
            "whiteBalanceMode": opt(WhiteBalanceMode.allCases.map(\.rawValue), "White balance mode."),
            "whiteBalanceShiftRed": bounded(wbShift, "WB Red–Cyan shift (R value)."),
            "whiteBalanceShiftBlue": bounded(wbShift, "WB Blue–Amber shift (B value)."),
            "whiteBalanceKelvin": bounded(CameraModelRegistry.kelvinRange,
                                          "Color temperature in Kelvin, if WB is a K value."),
            "dynamicRange": opt(DynamicRange.allCases.map(\.rawValue), "Dynamic range."),
            "dRangePriority": opt(DRangePriority.allCases.map(\.rawValue), "D-Range Priority."),
            "highlightTone": num(.highlightTone, "Highlight tone, e.g. -1."),
            "shadowTone": num(.shadowTone, "Shadow tone, e.g. -1."),
            "color": num(.color, "Color / saturation, e.g. +2."),
            "sharpness": num(.sharpness, "Sharpness, e.g. -2."),
            "clarity": num(.clarity, "Clarity, e.g. 0."),
            "highISONR": num(.highISONR, "High ISO NR, e.g. -4. Older bodies call it Noise Reduction."),
            "credit": ["type": "string",
                       "description": "Who made the recipe. Only ever set together with creditBasis."],
            "creditBasis": opt(CreditBasis.allCases.map(\.rawValue),
                               "What shows that `credit` names the recipe's author."),
            "notes": ["type": "string", "description": "Any extra free-text guidance or tips."],
            "tags": ["type": "array", "items": ["type": "string"], "description": "Optional tags."],
        ]
    }

    /// A numeric property fenced to the values the app will actually keep.
    ///
    /// The bounds are the camera-independent superset on purpose: a screenshot names no body, so
    /// that's the only honest constraint at scan time, and `CameraModel` narrows it later. They
    /// are a hint rather than a guarantee — no provider validates `minimum`/`maximum` on tool input
    /// — which is why `AIRecipePayload.toPortable` clamps the same ranges on the way back.
    private static func bounded(_ range: NumericRange, _ description: String) -> [String: Any] {
        // A fractional step is what makes a field non-integral, and those are exactly the fields
        // `AIRecipePayload` decodes as `Double`, so the two can't disagree.
        guard range.step.truncatingRemainder(dividingBy: 1) != 0 else {
            return ["type": "integer", "minimum": Int(range.min), "maximum": Int(range.max),
                    "description": description]
        }
        return ["type": "number", "minimum": range.min, "maximum": range.max,
                "multipleOf": range.step, "description": description]
    }
}

/// The flat JSON shape of one recipe as the `extract_recipe` tool call produces it, before mapping
/// to the app's typed enums.
struct AIRecipePayload: Codable {
    var name: String?
    var filmSimulation: String?
    var grainStrength: String?
    var grainSize: String?
    var colorChromeEffect: String?
    var colorChromeFXBlue: String?
    var whiteBalanceMode: String?
    var whiteBalanceShiftRed: Int?
    var whiteBalanceShiftBlue: Int?
    var whiteBalanceKelvin: Int?
    var dynamicRange: String?
    var dRangePriority: String?
    var highlightTone: Double?
    var shadowTone: Double?
    var color: Int?
    var sharpness: Int?
    var clarity: Int?
    var highISONR: Int?
    /// Not in the schema. A model may still answer under the older name, and `RecipeSettings`
    /// folds the value into `highISONR`; dropping the property would drop the reading instead.
    var noiseReduction: Int?
    var credit: String?
    var creditBasis: String?
    var notes: String?
    var tags: [String]?

    func toPortable(fallbackName: String) -> PortableRecipe {
        // `noiseReduction` is set only through the initialiser, which reads a lone one as the High
        // ISO NR it names on older bodies.
        var s = RecipeSettings(highISONR: clamped(highISONR, to: .highISONR),
                               noiseReduction: clamped(noiseReduction, to: .highISONR))
        s.filmSimulation = option(filmSimulation)
        if let strength: GrainStrength = option(grainStrength) {
            let size: GrainSize? = option(grainSize)
            s.grain = GrainEffect(strength: strength, size: strength == .off ? nil : size)
        }
        s.colorChromeEffect = option(colorChromeEffect)
        s.colorChromeFXBlue = option(colorChromeFXBlue)
        if let mode: WhiteBalanceMode = option(whiteBalanceMode) {
            let shift = CameraModelRegistry.whiteBalanceShiftRange
            s.whiteBalance = WhiteBalance(
                mode: mode,
                shiftRed: clamped(whiteBalanceShiftRed, to: shift) ?? 0,
                shiftBlue: clamped(whiteBalanceShiftBlue, to: shift) ?? 0,
                kelvin: mode.usesKelvin
                    ? clamped(whiteBalanceKelvin, to: CameraModelRegistry.kelvinRange) : nil)
        }
        s.dynamicRange = option(dynamicRange)
        s.dRangePriority = option(dRangePriority)
        s.highlightTone = clamped(highlightTone, to: .highlightTone)
        s.shadowTone = clamped(shadowTone, to: .shadowTone)
        s.color = clamped(color, to: .color)
        s.sharpness = clamped(sharpness, to: .sharpness)
        s.clarity = clamped(clarity, to: .clarity)

        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTags = (tags ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return PortableRecipe(
            name: trimmedName.isEmpty ? fallbackName : trimmedName,
            credit: attributedCredit,
            authoredForModel: nil,
            notes: notes?.isEmpty == false ? notes : nil,
            tags: cleanTags.isEmpty ? nil : cleanTags,
            settings: s,
            unsupportedFields: nil,
            photos: nil
        )
    }

    /// The credit to keep, or nil when nothing in the screenshot claimed authorship.
    ///
    /// A visible handle is not a byline. The same screenshot shape carries the person who wrote the
    /// recipe and the person who merely reposted it, and crediting the wrong one is a worse failure
    /// than leaving a recipe unattributed — so the name survives only when the model could say what
    /// made it a credit. An absent or unrecognized basis drops it.
    private var attributedCredit: String? {
        guard creditBasis.flatMap(AIRecipeSchema.CreditBasis.init(rawValue:)) != nil else { return nil }
        let trimmed = (credit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Fence a model-supplied number to what the app will keep.
    ///
    /// The tool schema asks for these bounds but nothing enforces them, so a "+2" misread as "+20"
    /// arrives looking exactly like a real reading, and the review editor's slider would silently
    /// pin it rather than show that it was impossible. Clamping rather than dropping matches what
    /// `RecipeCompatibility` and `RecipeDraft` already do wherever a number arrives from outside;
    /// it also rounds to the field's step, which is the common case (a tone read as 1.3).
    private func clamped(_ value: Double?, to field: RecipeField) -> Double? {
        value.map { DefaultRanges.range(for: field).clamp($0) }
    }

    private func clamped(_ value: Int?, to field: RecipeField) -> Int? {
        clamped(value, to: DefaultRanges.range(for: field))
    }

    private func clamped(_ value: Int?, to range: NumericRange) -> Int? {
        value.map { Int(range.clamp(Double($0)).rounded()) }
    }

    /// Map a raw string to a typed recipe enum, tolerating either the stable raw value or the
    /// human-readable display name (case-insensitive) in case the model returns a label.
    private func option<T: RecipeOption>(_ raw: String?) -> T? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let exact = T(rawValue: raw) { return exact }
        return T.allCases.first {
            $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame
            || $0.displayName.caseInsensitiveCompare(raw) == .orderedSame
        }
    }
}
