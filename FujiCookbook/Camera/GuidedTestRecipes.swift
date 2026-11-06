import Foundation

/// The recipes the guided write pass pushes, and the check that says whether a tester's own recipe
/// would test anything.
///
/// **Why the app supplies the recipes.** A Camera Test needs a recipe that fills in *everything*:
/// when a recipe leaves a field unset, the encoder either writes a default or leaves the slot's own
/// value in place, and the read-back of either reports "written and verified" — a green checkmark
/// over a value the recipe never asked for. Asking a person for such a recipe is easy to read and hard to follow,
/// and a sparse recipe produces a page of confident nonsense rather than a visible failure.
/// Supplying the recipes removes the trap instead of warning about it.
///
/// The second reason is comparability. Everyone testing a given model pushes the *same bytes*, so
/// two reports from two X-T5s differ only where the cameras differ — which is the entire point of
/// collecting them.
///
/// Values are deliberately distinctive rather than tasteful: a field left at its default is a field
/// whose passthrough looks identical to its write. These get pushed into a slot and then offered
/// back out again by the restore step.
enum GuidedTestRecipes {

    struct TestRecipe: Identifiable, Equatable {
        /// Stable across builds — it is written into a stored session and a shared report.
        let id: String
        let name: String
        /// One line saying what this recipe is for, shown next to it when the tester picks.
        let purpose: String
        let settings: RecipeSettings

        /// What the camera will actually call the slot.
        func slotName(for model: CameraModel) -> String { model.sanitizedSlotName(from: name) }
    }

    /// The recipes for a body, in the order they are offered: four on a body with D-Range Priority,
    /// three on one without.
    ///
    /// Built against the model rather than hardcoded: a field the body doesn't have is omitted (so
    /// the push reports no skips that aren't findings), the film simulation comes from the body's
    /// own list, and every number is snapped into the body's range by `RecipeCompatibility.clamped`
    /// so nothing arrives at the push screen already flagged as needing clamping.
    static func canonical(for model: CameraModel) -> [TestRecipe] {
        [colour(for: model), monochrome(for: model), kelvin(for: model), priority(for: model)]
            .compactMap { $0 }
    }

    static func recipe(id: String, for model: CameraModel) -> TestRecipe? {
        canonical(for: model).first { $0.id == id }
    }

    /// Visual guidance uses the actual supplied settings, including older-model substitutions.
    /// It describes a likely look; the tester's observation does not verify each recipe setting.
    static func observationGuidance(for settings: RecipeSettings) -> String {
        guard let simulation = settings.filmSimulation else {
            return "Check that the photo displays normally, with no missing areas, stripes or obvious corruption."
        }
        var parts: [String]
        if simulation == .sepia {
            parts = ["Expect a brown-toned monochrome photo."]
        } else if simulation.isMonochrome {
            parts = ["Expect a monochrome photo using \(simulation.displayName)."]
            if (settings.monochromaticColorWC ?? 0) != 0 || (settings.monochromaticColorMG ?? 0) != 0 {
                parts.append("A slight tint is normal with this recipe's toning.")
            }
        } else {
            switch simulation {
            case .classicChrome:
                parts = ["Expect a colour photo. Classic Chrome usually gives restrained colours and defined shadows."]
            case .velvia:
                parts = ["Expect a colour photo with Velvia's vivid look."]
            default:
                parts = ["Expect a colour photo using \(simulation.displayName)."]
            }
            if settings.whiteBalance?.mode == .kelvin, let kelvin = settings.whiteBalance?.kelvin {
                parts.append("White balance is fixed at \(kelvin) K.")
            }
            parts.append("The scene and lighting affect colour and warmth.")
        }
        if let grain = settings.grain, grain.strength != .off {
            parts.append(grain.strength == .weak
                         ? "Grain may be subtle; zoom in to check it."
                         : "Zoom in to look for the added grain.")
        }
        if (settings.sharpness ?? 0) > 0 || (settings.clarity ?? 0) > 0 {
            parts.append("Edges and texture may look more pronounced.")
        }
        if let priority = settings.dRangePriority, priority != .off {
            parts.append("D-Range Priority adjusts bright and dark areas automatically, so contrast depends on the scene.")
        }
        parts.append("Check for missing areas, stripes or obvious corruption.")
        return parts.joined(separator: " ")
    }

    // MARK: The four

    /// The full colour field set: white balance shift, grain, the colour chrome pair, tone, colour,
    /// sharpness, noise reduction, clarity.
    private static func colour(for model: CameraModel) -> TestRecipe? {
        guard let sim = firstSupported([.classicChrome, .classicNeg, .provia], model) else { return nil }
        var s = RecipeSettings()
        s.filmSimulation = sim
        if model.supports(.grain) { s.grain = GrainEffect(strength: .weak, size: .small) }
        s.whiteBalance = WhiteBalance(mode: .daylight, shiftRed: 2, shiftBlue: -3, kelvin: nil)
        s.dynamicRange = .dr200
        set(&s, model, highlightTone: -0.5, shadowTone: 1, color: 2, sharpness: -1,
            highISONR: -2, clarity: 2)
        if model.supports(.colorChromeEffect) { s.colorChromeEffect = .strong }
        if model.supports(.colorChromeFXBlue) { s.colorChromeFXBlue = .weak }
        return TestRecipe(id: "colour", name: "CT Colour",
                          purpose: "Checks colour, white balance, grain, Dynamic Range and tone settings.",
                          settings: RecipeCompatibility.clamped(s, to: model))
    }

    /// The monochrome path: the toning axes the body actually has, and the camera refusing colour —
    /// which is correct behaviour worth seeing reported as such.
    private static func monochrome(for model: CameraModel) -> TestRecipe? {
        guard let sim = firstSupported([.acrosR, .monochromeR, .acros, .monochrome], model) else { return nil }
        var s = RecipeSettings()
        s.filmSimulation = sim
        if model.supports(.grain) { s.grain = GrainEffect(strength: .strong, size: .large) }
        s.whiteBalance = WhiteBalance(mode: .auto, shiftRed: -1, shiftBlue: 2, kelvin: nil)
        s.dynamicRange = .dr100
        set(&s, model, highlightTone: 1, shadowTone: 0.5, color: nil, sharpness: 1,
            highISONR: -1, clarity: -2)
        // Per *axis*, not per field. Monochromatic Color is one `RecipeField` covering two axes,
        // and gating both on `supports(.monochromaticColor)` would put a magenta–green value into
        // the recipe on a body with the warm–cool axis alone (the X-T3 and X-T30, per
        // `RecipeApplicability.hasMagentaGreenAxis`) — the confident-but-wrong write this file exists to
        // avoid producing. Every other body with the control has both axes, and the GFX100S read
        // this recipe's MG −1 back from its own menu (fw 2.13). `RecipeCompatibility` warns about
        // the same field-for-axis confusion; both read `RecipeApplicability` so they cannot disagree.
        if model.supports(.monochromaticColor) {
            s.monochromaticColorWC = 2
            if RecipeApplicability.hasMagentaGreenAxis(on: model) { s.monochromaticColorMG = -1 }
        }
        // Colour is left unset on purpose, not by omission: the camera ignores saturation on a
        // monochrome simulation, and a recipe that sets it anyway makes the push report an advisory
        // that has nothing to do with the body.
        return TestRecipe(id: "mono", name: "CT Mono",
                          purpose: "Checks a monochrome recipe, toning and grain.",
                          settings: RecipeCompatibility.clamped(s, to: model))
    }

    /// The three values that are their own special cases on the wire: a colour temperature (only
    /// valid in Kelvin mode), DR Auto (a sentinel rather than a percentage, measured on one body and
    /// one firmware), and grain Off (which the X-T50 accepts as one value and reports as another).
    private static func kelvin(for model: CameraModel) -> TestRecipe? {
        // A body without Kelvin white balance — the X-M1 — has no temperature to write, and a
        // recipe that set one would warn about itself on the push screen.
        guard model.supports(whiteBalanceMode: .kelvin),
              let sim = firstSupported([.velvia, .astia, .provia], model) else { return nil }
        var s = RecipeSettings()
        s.filmSimulation = sim
        if model.supports(.grain) { s.grain = .off }
        s.whiteBalance = WhiteBalance(mode: .kelvin, shiftRed: 1, shiftBlue: -1, kelvin: 5600)
        s.dynamicRange = .auto
        set(&s, model, highlightTone: 2, shadowTone: 2, color: -2, sharpness: 2,
            highISONR: 1, clarity: -1)
        if model.supports(.colorChromeEffect) { s.colorChromeEffect = .off }
        if model.supports(.colorChromeFXBlue) { s.colorChromeFXBlue = .off }
        return TestRecipe(id: "kelvin", name: "CT Kelvin",
                          purpose: "Checks 5600 K white balance, DR Auto and grain Off.",
                          settings: RecipeCompatibility.clamped(s, to: model))
    }

    /// D-Range Priority on, and the film simulation that follows the processor rather than the sensor.
    ///
    /// The priority is a highlight-and-shadow curve the camera drives itself: with it on, the body
    /// sets Dynamic Range, Highlight Tone and Shadow Tone and refuses every write to them, so this
    /// recipe leaves all three unset and the codec skips them (`FujiPresetCodec.encode`). Auto is the
    /// value worth confirming — `0x8000`, the one with the high bit, measured on the X-T50 alone.
    /// It is ISO-gated like Dynamic Range: at base ISO the camera refuses the write and the push
    /// says why, which is itself the finding on a body whose base ISO isn't the X-T50's 125.
    ///
    /// The film simulation is the other half. The three recipes above reach Classic Chrome, ACROS
    /// and Velvia, none of which is in doubt on any body; REALA ACE is what the X-T30 III and X-M5
    /// were promoted on — a sim the registry gives them because of their processor, not their
    /// sensor — and nothing else in the write pass ever writes it. Only bodies that have the
    /// priority get this recipe; the others keep three rather than a fourth that tests nothing.
    private static func priority(for model: CameraModel) -> TestRecipe? {
        guard model.supports(.dRangePriority),
              let sim = firstSupported([.realaAce, .nostalgicNeg, .eterna, .provia], model) else { return nil }
        var s = RecipeSettings()
        s.filmSimulation = sim
        s.dRangePriority = .auto
        if model.supports(.grain) { s.grain = GrainEffect(strength: .strong, size: .small) }
        s.whiteBalance = WhiteBalance(mode: .shade, shiftRed: -2, shiftBlue: 3, kelvin: nil)
        set(&s, model, highlightTone: nil, shadowTone: nil, color: -1, sharpness: 3,
            highISONR: 2, clarity: 3)
        if model.supports(.colorChromeEffect) { s.colorChromeEffect = .weak }
        if model.supports(.colorChromeFXBlue) { s.colorChromeFXBlue = .strong }
        return TestRecipe(id: "priority", name: "CT Priority",
                          purpose: "Checks D-Range Priority Auto and \(sim.displayName). The camera controls the range and tones.",
                          settings: RecipeCompatibility.clamped(s, to: model))
    }

    // MARK: Authoring check

    /// The fields whose unset value can't show that the recipe reached the camera, so a read-back
    /// verifies a value nobody chose.
    ///
    /// Two kinds. Unset, High ISO NR is passed through from the slot's own bytes, and Monochromatic
    /// Color and a Kelvin temperature are not sent at all (`FujiPresetCodec.encode`): nothing is
    /// written, so nothing can fail. Film simulation, Dynamic Range and grain are written as
    /// defaults (PROVIA, Auto, Off), which are also what a bank is likely to hold already, so a
    /// read-back that matches says little about the push. They are skipped altogether on a slot
    /// that never reported them (`FujiPresetCodec.defaultsNotWrittenForSilentRead`).
    ///
    /// The other fields the encoder writes a *default* into when unset (clarity, the colour chrome
    /// pair, the white balance shifts, tone, colour, sharpness) are not listed: a default is a
    /// weaker test than a distinctive value, but it is still a real write with a real read-back, so
    /// it can fail.
    static func unauthoredFields(_ s: RecipeSettings, model: CameraModel) -> [RecipeField] {
        var fields: [RecipeField] = []
        if s.filmSimulation == nil { fields.append(.filmSimulation) }
        // Under a priority the codec skips Dynamic Range — the camera drives it — so leaving it out
        // of such a recipe is not a gap. The same rule
        // the codec applies at `FujiPresetCodec.defaultsNotWrittenForSilentRead`.
        if s.dynamicRange == nil, (s.dRangePriority ?? .off) == .off { fields.append(.dynamicRange) }
        // A body without the control has no grain to leave unauthored: the X-Trans I and II.
        if model.supports(.grain), s.grain == nil { fields.append(.grain) }
        if model.supports(.highISONR), s.highISONR.flatMap({ FujiEncoding.nrEncode[$0] }) == nil {
            fields.append(.highISONR)
        }
        // Zero tests a real write; only an absent write leaves the bank's own toning in place.
        let toning = FujiPresetCodec.toningValuesToWrite(s, model: model)
        if RecipeApplicability.monochromaticColorWC(s, on: model).applies,
           toning.warmCool == nil, toning.magentaGreen == nil {
            fields.append(.monochromaticColor)
        }
        // Colour temperature rides on the white balance mode: in Kelvin mode with no temperature,
        // the mode is written and the temperature the picture is actually made at is not.
        if let wb = s.whiteBalance, wb.mode == .kelvin, (wb.kelvin ?? 0) <= 0 {
            fields.append(.whiteBalance)
        }
        return fields
    }

    // MARK: Helpers

    private static func firstSupported(_ candidates: [FilmSimulation], _ model: CameraModel) -> FilmSimulation? {
        candidates.first { model.supports(filmSimulation: $0) }
            ?? model.supportedFilmSimulations.first
    }

    /// Assign the numeric fields this body actually has. Setting one it doesn't would make the push
    /// screen warn about a field the recipe had no business carrying.
    private static func set(_ s: inout RecipeSettings, _ model: CameraModel,
                            highlightTone: Double?, shadowTone: Double?, color: Int?,
                            sharpness: Int?, highISONR: Int?, clarity: Int?) {
        if model.supports(.highlightTone) { s.highlightTone = highlightTone }
        if model.supports(.shadowTone) { s.shadowTone = shadowTone }
        if model.supports(.color) { s.color = color }
        if model.supports(.sharpness) { s.sharpness = sharpness }
        if model.supports(.highISONR) { s.highISONR = highISONR }
        if model.supports(.clarity) { s.clarity = clarity }
    }
}
