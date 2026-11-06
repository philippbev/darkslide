import Foundation

/// One way in which a recipe doesn't perfectly match the connected camera, with a plain-language
/// explanation of how the push will handle it. The user is warned before the push about fields the
/// connected camera does not support, and told how they'll be handled (skipped or clamped).
struct FieldCompatibilityIssue: Identifiable, Hashable {
    enum Kind: Hashable {
        case fieldUnsupported          // the body has no such control → skipped
        case filmSimulationUnsupported // the chosen film sim doesn't exist on this body → skipped
        /// The recipe has no film simulation at all. The encoder writes PROVIA/Standard for it, a
        /// substitution that has to raise an issue: a nil here is not "the user didn't ask"; it is
        /// the field a recipe is judged by, missing, and the push about to guess.
        case filmSimulationUnset
        /// The recipe carries this field, but the push deliberately doesn't write it, so the slot
        /// keeps whatever it already holds. Dynamic Range's case: the camera drives DR while D-Range
        /// Priority is on, and refuses every write to D190 until it is off.
        case notWritten
        case valueClamped(from: String, to: String)
        /// `valueClamped`, on Monochromatic Color's magenta–green axis.
        ///
        /// Its own kind for the reason `magentaGreenAxisUnsupported` is: `RecipeField.monochromaticColor`
        /// is one field covering two axes, so `field` cannot say which one was clamped, and
        /// `subject` names the axis the way the editor's rows do.
        case magentaGreenClamped(from: String, to: String)
        case ignoredForMonochrome      // Color/saturation written on a monochrome sim → ignored
        /// Monochromatic Color written on a simulation whose toning is fixed — Sepia. The mirror of
        /// `ignoredForMonochrome`: the camera greys both controls for Sepia (X-T50, 2026-09-20), so
        /// a recipe carrying a toning value for one has it written and silently ignored.
        case ignoredForFixedToning
        /// The recipe carries a magenta–green value and the body has only the warm–cool axis.
        ///
        /// Its own kind rather than `fieldUnsupported`, because the field *is* supported here.
        /// `RecipeField.monochromaticColor` is one field covering two axes, and the loop's
        /// `model.supports(field)` check is keyed on the field, so the X-T3 and X-T30 — the bodies
        /// with the warm–cool axis alone (`CameraModel.hasMagentaGreenAxis`) — pass that check with
        /// an MG value nothing else mentions. Saying "Monochromatic Color isn't supported" here
        /// would be false: the warm–cool axis is supported, and the recipe's WC value is written
        /// and honoured. Neither body is writable, so no push shows this; the Works With card
        /// (`RecipeCameraFit`) does, and the compare screen and the develop read the rule.
        case magentaGreenAxisUnsupported
        /// The recipe's white balance mode is not on this body's menu — Auto (White Priority) on an
        /// X100V, Kelvin on an X-M1. The field is supported; the mode is what the body lacks
        /// (`CameraModel.supportedWhiteBalanceModes`), and `FujiPresetCodec.encode` sends
        /// `wbModeToValue[mode]` regardless, so the push has to say the body may refuse it. The
        /// same shape as `magentaGreenAxisUnsupported`.
        case whiteBalanceModeUnsupported
    }

    let id = UUID()
    let field: RecipeField
    let kind: Kind
    let message: String

    /// What the issue's message and the results' "Clamped:" lists call the value it is about.
    var subject: String { Self.subject(field, kind) }

    /// The field's own name, except for the two Monochromatic Color clamps, which name their axis
    /// the way the editor's two rows do. Both axes can clamp in one push, and a list that names
    /// the field twice does not say which axis changed.
    static func subject(_ field: RecipeField, _ kind: Kind) -> String {
        switch kind {
        case .valueClamped where field == .monochromaticColor: return "\(field.displayName) (WC)"
        case .magentaGreenClamped: return "\(field.displayName) (MG)"
        default: return field.displayName
        }
    }
}

/// Compares a recipe against a camera model: the issues a push warns about, and the settings
/// clamped to the body's ranges.
enum RecipeCompatibility {

    /// Issues that should be surfaced to the user before a push, in display order.
    static func analyze(_ settings: RecipeSettings, for model: CameraModel) -> [FieldCompatibilityIssue] {
        var issues: [FieldCompatibilityIssue] = []

        if settings.filmSimulation == nil {
            issues.append(.init(field: .filmSimulation, kind: .filmSimulationUnset,
                message: "This recipe has no film simulation, so PROVIA / Standard will be written. Set one if that isn't the look you want."))
        }

        if let sim = settings.filmSimulation, !model.supports(filmSimulation: sim) {
            issues.append(.init(field: .filmSimulation, kind: .filmSimulationUnsupported,
                message: "“\(sim.displayName)” doesn't exist on \(model.displayName). The camera will keep its current film simulation for this slot."))
        }

        // White balance mode availability: the Auto priorities, Kelvin and Underwater are per body.
        // Only where the body has the field at all — a body without white balance reports that
        // once, in the loop below.
        if let wb = settings.whiteBalance, model.supports(.whiteBalance), !model.supports(whiteBalanceMode: wb.mode) {
            issues.append(.init(field: .whiteBalance, kind: .whiteBalanceModeUnsupported,
                message: whiteBalanceModeMessage(wb.mode, on: model)))
        }

        for field in RecipeField.allCases {
            guard isSet(field, in: settings) else { continue }

            if !model.supports(field) {
                // Monochromatic color & color are conditionally relevant; still report as skipped.
                issues.append(.init(field: field, kind: .fieldUnsupported,
                    message: "\(field.displayName) isn't supported on \(model.displayName) and will be skipped."))
                continue
            }

            // Monochromatic Color's clamps are each gated on their axis's rule rather than on the
            // body alone. On a colour simulation or Sepia the push writes no toning at all
            // (`FujiPresetCodec.toningValuesToWrite`), so there is no written value to clamp.
            // `clamped(_:to:)` still clamps both axes there, which changes nothing on the camera.
            if field != .monochromaticColor || RecipeApplicability.monochromaticColorWC(settings, on: model).applies,
               let issue = clampIssue(field, numericValue(field, in: settings), on: model,
                                      kind: FieldCompatibilityIssue.Kind.valueClamped) {
                issues.append(issue)
            }

            // `numericValue` reads Monochromatic Color's warm–cool axis, so magenta–green needs a
            // check of its own. On a body with the warm–cool axis alone `.magentaGreenAxisUnsupported` below
            // describes the MG value, clamp included, so a clamp issue there would say it twice.
            // Raised next to the warm–cool clamp, so the two axes read together.
            if field == .monochromaticColor,
               RecipeApplicability.monochromaticColorMG(settings, on: model).applies,
               let issue = clampIssue(field, settings.monochromaticColorMG.map(Double.init), on: model,
                                      kind: FieldCompatibilityIssue.Kind.magentaGreenClamped) {
                issues.append(issue)
            }
        }

        // Dynamic Range and D-Range Priority are one control on the camera: with D-Range Priority
        // on, the body drives Dynamic Range and refuses every write to D190. The editor won't let
        // the two be authored together, but a recipe imported from a bank — or saved by an older
        // build — can still hold both, so the push has to say which one wins.
        //
        // Worded after the editor's Dynamic Range and tone footers, so the two screens tell one story.
        if RecipeApplicability.priorityOverrides(settings, on: model) {
            // All three, because D-Range Priority *is* a highlight-and-shadow curve: the camera
            // drives the tones as well as the range and refuses every write to them (X-T50 fw 1.32,
            // 2026-09-18). One issue per field, so the results screen names what it actually
            // skipped rather than making the reader infer it from one sentence. Iterated in
            // `allCases` order rather than over the set, so the issue order is stable.
            for field in RecipeField.allCases
            where RecipeApplicability.fieldsUnderPriority.contains(field) && isSet(field, in: settings) {
                issues.append(.init(field: field, kind: .notWritten,
                    message: "The camera sets Dynamic Range, Highlight Tone and Shadow Tone while D-Range Priority is on, so this recipe's \(field.displayName) won't be written."))
            }
        }

        // The converse — a recipe setting a dynamic range turns D-Range Priority off, because DR
        // mode is what it is asserting — is deliberately **not** an issue here. `analyze` sees the
        // recipe and the model, never the slot, so it could only ever say "if the slot has D-Range
        // Priority on, it will be turned off": a warning about something that usually will not
        // happen, on most recipes anybody writes. The push says it when it actually does it, and
        // the D-Range Priority row on the results screen shows the write either way.

        // Color written on a monochrome film sim is ignored by the camera.
        // The `!= 0` is messaging, not applicability: a neutral saturation changes nothing either
        // way, so there is nothing to warn about. `RecipeApplicability.color` deliberately has no
        // such notion — it answers whether the control applies, never whether the value matters.
        if RecipeApplicability.isMonochrome(settings), settings.color != nil, settings.color != 0 {
            issues.append(.init(field: .color, kind: .ignoredForMonochrome,
                message: "Color (saturation) has no effect on monochrome film simulations and will be ignored."))
        }

        // The converse, on the one simulation that is monochrome and still has no toning to set.
        // Same `!= 0` reading as above: a zero changes nothing either way, so there is nothing to
        // warn about.
        if RecipeApplicability.isMonochrome(settings), !RecipeApplicability.hasMonochromaticColor(settings),
           model.supports(.monochromaticColor),
           (settings.monochromaticColorWC ?? 0) != 0 || (settings.monochromaticColorMG ?? 0) != 0,
           let sim = settings.filmSimulation {
            issues.append(.init(field: .monochromaticColor, kind: .ignoredForFixedToning,
                message: "\(sim.displayName) is already toned, so \(RecipeField.monochromaticColor.displayName) has no effect and will be ignored."))
        }

        // The magenta–green axis, on a body that has only the warm–cool one — the X-T3 and X-T30.
        // The editor hides this row there (`RecipeDraft.showMG`) and keeps the value, so a recipe
        // authored on Generic, or read from one of their banks, reaches here carrying one.
        //
        // `.noMagentaGreenAxis` is the one reason worth a message of its own. The composed rule's
        // other two answers are already covered: `.bodyLacksField` is the loop's `.fieldUnsupported`
        // above, and `.notMonochrome` is a colour recipe carrying mono toning, which no kind here
        // describes and which this is not the place to start.
        //
        // Gated on a **non-zero** MG, because that is the only MG `FujiPresetCodec.toningValuesToWrite`
        // sends to a body without the axis — the same rule as `ignoredForMonochrome`'s `!= 0`, and
        // the reason a neutral 0 warns about nothing: there is no write to describe.
        //
        // The value named is the one the push encodes, from `clamped(_:to:)`, with the recipe's own
        // beside it when they differ. The axis is named as the editor's row names it.
        if let mg = settings.monochromaticColorMG, mg != 0,
           RecipeApplicability.monochromaticColorMG(settings, on: model).reason == .noMagentaGreenAxis {
            let sent = clamped(settings, to: model).monochromaticColorMG ?? mg
            let clampNote = sent == mg ? "" : ", clamped from \(RecipeSettingsFormatter.tone(Double(mg)))"
            issues.append(.init(field: .monochromaticColor, kind: .magentaGreenAxisUnsupported,
                message: "\(model.displayName) has Monochromatic Color's warm–cool axis only; "
                       + "Fujifilm's manual lists no magenta–green axis for it. The push still sends "
                       + "\(RecipeField.monochromaticColor.displayName) (MG) "
                       + "\(RecipeSettingsFormatter.tone(Double(sent)))\(clampNote), so this body may "
                       + "refuse it and report the push as partly applied."))
        }

        return issues
    }

    /// A copy of `settings` with every numeric field clamped to the model's range, so nothing is
    /// written outside the camera's supported ranges.
    ///
    /// `droppingUnsupportedFilmSimulation` exists because the push and the develop need opposite
    /// things from the same drop. The codec writes PROVIA for a recipe with no film simulation, so
    /// on a push the drop would substitute a second look nobody chose; the push therefore keeps
    /// the unsupported sim and lets `FujiPresetCodec.encode` recognise it, which is where the bytes
    /// are decided anyway. The develop wants it dropped: `FujiRawConvProfile.patch` writes whatever
    /// sim it is handed straight into the profile, with no support check of its own.
    static func clamped(_ settings: RecipeSettings, to model: CameraModel,
                        droppingUnsupportedFilmSimulation: Bool = true) -> RecipeSettings {
        var s = settings
        if droppingUnsupportedFilmSimulation,
           let sim = s.filmSimulation, !model.supports(filmSimulation: sim) { s.filmSimulation = nil }
        func clampInt(_ value: Int?, _ field: RecipeField) -> Int? {
            guard let value, let range = model.range(for: field) else { return value }
            return Int(range.clamp(Double(value)))
        }
        func clampDouble(_ value: Double?, _ field: RecipeField) -> Double? {
            guard let value, let range = model.range(for: field) else { return value }
            return range.clamp(value)
        }
        s.highlightTone = clampDouble(s.highlightTone, .highlightTone)
        s.shadowTone = clampDouble(s.shadowTone, .shadowTone)
        s.color = clampInt(s.color, .color)
        s.sharpness = clampInt(s.sharpness, .sharpness)
        s.highISONR = clampInt(s.highISONR, .highISONR)
        s.clarity = clampInt(s.clarity, .clarity)
        s.monochromaticColorWC = clampInt(s.monochromaticColorWC, .monochromaticColor)
        s.monochromaticColorMG = clampInt(s.monochromaticColorMG, .monochromaticColor)
        return s
    }

    /// The one sentence the push warning and the editor's White Balance footer both use for a mode
    /// the body's menu lacks, so the two screens tell one story.
    static func whiteBalanceModeMessage(_ mode: WhiteBalanceMode, on model: CameraModel) -> String {
        "\(model.displayName) has no \(mode.displayName) white balance; Fujifilm's manual lists no such mode for it. The push still sends it, so this body may refuse it and report the push as partly applied."
    }

    // MARK: - Helpers

    /// Whether a field carries a value in these settings. A numeric 0 is set (it is a write); an
    /// Off grain, Color Chrome effect or D-Range Priority is not.
    static func isSet(_ field: RecipeField, in s: RecipeSettings) -> Bool {
        switch field {
        case .filmSimulation: return s.filmSimulation != nil
        case .monochromaticColor: return s.monochromaticColorWC != nil || s.monochromaticColorMG != nil
        case .grain: return s.grain != nil && s.grain != .off
        case .colorChromeEffect: return s.colorChromeEffect != nil && s.colorChromeEffect != .off
        case .colorChromeFXBlue: return s.colorChromeFXBlue != nil && s.colorChromeFXBlue != .off
        case .whiteBalance: return s.whiteBalance != nil
        case .dynamicRange: return s.dynamicRange != nil
        case .dRangePriority: return s.dRangePriority != nil && s.dRangePriority != .off
        case .highlightTone: return s.highlightTone != nil
        case .shadowTone: return s.shadowTone != nil
        case .color: return s.color != nil
        case .sharpness: return s.sharpness != nil
        case .highISONR: return s.highISONR != nil
        case .clarity: return s.clarity != nil
        case .exposureBias: return s.exposureBias != nil
        case .noiseReduction: return s.noiseReduction != nil
        }
    }

    /// The issue for a value outside the model's range, or nil when it is inside or absent.
    private static func clampIssue(_ field: RecipeField, _ raw: Double?, on model: CameraModel,
                                   kind: (_ from: String, _ to: String) -> FieldCompatibilityIssue.Kind)
        -> FieldCompatibilityIssue? {
        guard let raw, let range = model.range(for: field) else { return nil }
        let clamped = range.clamp(raw)
        guard abs(clamped - raw) > 0.0001 else { return nil }
        let from = RecipeSettingsFormatter.tone(raw)
        let to = RecipeSettingsFormatter.tone(clamped)
        let kind = kind(from, to)
        return .init(field: field, kind: kind,
            message: "\(FieldCompatibilityIssue.subject(field, kind)) \(from) is outside \(model.displayName)'s range; it will be clamped to \(to).")
    }

    private static func numericValue(_ field: RecipeField, in s: RecipeSettings) -> Double? {
        switch field {
        case .highlightTone: return s.highlightTone
        case .shadowTone: return s.shadowTone
        case .color: return s.color.map(Double.init)
        case .sharpness: return s.sharpness.map(Double.init)
        case .highISONR: return s.highISONR.map(Double.init)
        case .clarity: return s.clarity.map(Double.init)
        case .monochromaticColor: return s.monochromaticColorWC.map(Double.init)
        default: return nil
        }
    }
}
