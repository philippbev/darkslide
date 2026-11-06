import Foundation

/// What one camera does with a recipe's settings: runs them as written, needs a change, or cannot
/// run the recipe at all. Read off `RecipeCompatibility.analyze` and the applicability rules, never
/// off an issue's message text — those are the push's wording, and this is not the push.
///
/// Three verdicts of the *requested settings*. Whether the body can be written over USB is a
/// separate capability (`CameraModel.writeSupport`) this type does not touch: a read-only X-T3 can
/// still run a recipe its menus can express.
struct RecipeCameraFit: Equatable, Identifiable {

    /// Worst last, so a fit's verdict is the maximum over its changes.
    enum Verdict: Int, Comparable, CaseIterable {
        case worksAsWritten
        case worksWithChanges
        case notAvailable

        static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One thing the camera would do differently from what the recipe asks.
    enum Change: Hashable {
        /// The base film simulation is not on this body. Nothing substitutes for it.
        case filmSimulationMissing(FilmSimulation)
        /// The body has no such control, and the recipe sets it to something other than neutral.
        case fieldMissing(RecipeField)
        /// The value lies outside the body's range or off its step. `subject` names the field, or
        /// the toning axis, the way the editor's rows do.
        case clamped(subject: String, from: String, to: String)
        /// A magenta–green toning value on a body with the warm–cool axis alone.
        case magentaGreenAxisMissing
        /// Grain with a requested size on a body whose grain has strength only. The camera keeps
        /// the strength; the size has nowhere to go.
        case grainSizeFixed
        /// A white balance mode the body's menu lacks. Nothing substitutes for it: the user picks
        /// another mode, and until then the push sends this one and the body may refuse it.
        case whiteBalanceModeMissing(WhiteBalanceMode)

        var verdict: Verdict {
            switch self {
            case .filmSimulationMissing: return .notAvailable
            case .fieldMissing, .clamped, .magentaGreenAxisMissing, .grainSizeFixed, .whiteBalanceModeMissing:
                return .worksWithChanges
            }
        }
    }

    /// A recipe-wide reason the check is partial. Not about any one body, so never a verdict.
    enum Caveat: Hashable, CaseIterable {
        /// No film simulation: the one setting a recipe is judged by is missing.
        case noFilmSimulation
        /// Fields the app kept verbatim because it cannot model them; it cannot check them either.
        case preservedFields
    }

    let model: CameraModel
    let changes: [Change]
    /// Numeric fields the recipe sets to something other than neutral, which the body has, and
    /// which the registry carries no range for — the X-Trans I and II entries, whose manuals print
    /// the controls without values. Nothing is known to differ, so these move no verdict; the card
    /// says the check could not reach them.
    let unverifiedRanges: [RecipeField]

    var verdict: Verdict { changes.map(\.verdict).max() ?? .worksAsWritten }
    var id: CameraModel.ID { model.id }

    init(_ settings: RecipeSettings, on model: CameraModel) {
        self.model = model
        var changes = RecipeCompatibility.analyze(settings, for: model)
            .compactMap { Self.change(for: $0, in: settings, on: model) }
        // The push never warns about this one: the codec folds size into the `0xD195` composite
        // and the camera refuses nothing. The card still owes the user the fact that a Large grain
        // has nowhere to go on a strength-only body.
        // Through the rule, not the flag: the rule asks whether the body has grain at all first, so
        // a body without the control reports "No Grain Effect" alone, not a fixed size as well.
        if Self.requestsAGrainSize(settings),
           RecipeApplicability.grainSize(settings, on: model).reason == .noGrainSizeControl {
            changes.append(.grainSizeFixed)
        }
        self.changes = changes
        unverifiedRanges = Self.numericFields.filter { field in
            model.supports(field) && model.range(for: field) == nil
                && RecipeCompatibility.isSet(field, in: settings) && !Self.isNeutral(field, in: settings)
        }
    }

    /// The fields a range can bound, in the parameter table's order.
    private static let numericFields: [RecipeField] = [
        .highlightTone, .shadowTone, .color, .sharpness, .highISONR, .clarity, .monochromaticColor
    ]

    /// Every body but the Demo Camera, in registry order.
    static func fits(_ settings: RecipeSettings, across models: [CameraModel]) -> [RecipeCameraFit] {
        models.filter { $0.id != CameraModelRegistry.demoModelID }
            .map { RecipeCameraFit(settings, on: $0) }
    }

    /// Why the check is partial for this recipe, in display order; empty when it is whole.
    static func caveats(for settings: RecipeSettings, hasPreservedFields: Bool) -> [Caveat] {
        var caveats: [Caveat] = []
        if settings.filmSimulation == nil { caveats.append(.noFilmSimulation) }
        if hasPreservedFields { caveats.append(.preservedFields) }
        return caveats
    }

    // MARK: - Mapping

    /// The change behind one push issue, or nil where the issue is about the recipe rather than the
    /// body. Exhaustive on purpose: a new issue kind has to decide what it means here.
    static func change(for issue: FieldCompatibilityIssue, in settings: RecipeSettings,
                       on model: CameraModel) -> Change? {
        switch issue.kind {
        case .filmSimulationUnsupported:
            return settings.filmSimulation.map(Change.filmSimulationMissing)
        case .fieldUnsupported:
            // A neutral value, or a control that does nothing for this recipe anyway (toning on a
            // colour simulation or Sepia, Color on a monochrome one), changes nothing whether or
            // not the body has the control. Without this, a Sepia recipe carrying a toning value
            // would read differently on a body that ignores it and on one that lacks it.
            guard !isNeutral(issue.field, in: settings), bearsOnRecipe(issue.field, settings) else { return nil }
            return .fieldMissing(issue.field)
        case .valueClamped(let from, let to), .magentaGreenClamped(let from, let to):
            // Tones and Dynamic Range under an active D-Range Priority are not written on a body
            // that has the priority, so a clamp there changes nothing.
            if RecipeApplicability.fieldsUnderPriority.contains(issue.field),
               RecipeApplicability.priorityOverrides(settings, on: model) { return nil }
            return .clamped(subject: issue.subject, from: from, to: to)
        case .magentaGreenAxisUnsupported:
            return .magentaGreenAxisMissing
        case .whiteBalanceModeUnsupported:
            return settings.whiteBalance.map { .whiteBalanceModeMissing($0.mode) }
        case .filmSimulationUnset, .notWritten, .ignoredForMonochrome, .ignoredForFixedToning:
            // The recipe's own business, the same on every body: not a fit question.
            return nil
        }
    }

    /// A value the camera would render no differently from the control's absence. The push's
    /// `isSet` deliberately counts a 0 as set (it is a write); the fit asks whether it matters.
    static func isNeutral(_ field: RecipeField, in s: RecipeSettings) -> Bool {
        switch field {
        case .highlightTone: return (s.highlightTone ?? 0) == 0
        case .shadowTone: return (s.shadowTone ?? 0) == 0
        case .color: return (s.color ?? 0) == 0
        case .sharpness: return (s.sharpness ?? 0) == 0
        case .highISONR: return (s.highISONR ?? 0) == 0
        case .clarity: return (s.clarity ?? 0) == 0
        case .exposureBias: return (s.exposureBias ?? 0) == 0
        case .noiseReduction: return (s.noiseReduction ?? 0) == 0
        case .monochromaticColor:
            return (s.monochromaticColorWC ?? 0) == 0 && (s.monochromaticColorMG ?? 0) == 0
        case .grain: return (s.grain?.strength ?? .off) == .off
        case .colorChromeEffect: return (s.colorChromeEffect ?? .off) == .off
        case .colorChromeFXBlue: return (s.colorChromeFXBlue ?? .off) == .off
        case .dRangePriority: return (s.dRangePriority ?? .off) == .off
        case .filmSimulation, .whiteBalance, .dynamicRange: return false
        }
    }

    /// Whether the control would do anything for this recipe on a body that has it. Asked of the
    /// recipe alone, so the answer is the same on every body.
    static func bearsOnRecipe(_ field: RecipeField, _ s: RecipeSettings) -> Bool {
        switch field {
        case .monochromaticColor: return RecipeApplicability.hasMonochromaticColor(s)
        case .color: return !RecipeApplicability.isMonochrome(s)
        // In no body's field set — a shooting suggestion, and the older name for High ISO NR that
        // a recipe keeps only beside its `highISONR` — not controls a body could lack, so they
        // cannot tell one body from another.
        case .exposureBias, .noiseReduction: return false
        case .filmSimulation, .grain, .colorChromeEffect, .colorChromeFXBlue, .whiteBalance,
             .dynamicRange, .dRangePriority, .highlightTone, .shadowTone, .sharpness, .highISONR,
             .clarity:
            return true
        }
    }

    /// Grain on, with a size the author chose. A size with the strength Off means nothing, and a
    /// strength-only recipe (size nil) is exactly what a strength-only body stores.
    private static func requestsAGrainSize(_ s: RecipeSettings) -> Bool {
        guard let grain = s.grain, grain.strength != .off else { return false }
        return grain.size != nil
    }
}

extension Array where Element == RecipeCameraFit {
    /// Groups in `Verdict` order, worst last, empty groups dropped; each fit appears once.
    func groupedByVerdict() -> [(verdict: RecipeCameraFit.Verdict, fits: [RecipeCameraFit])] {
        RecipeCameraFit.Verdict.allCases.compactMap { verdict in
            let fits = filter { $0.verdict == verdict }
            return fits.isEmpty ? nil : (verdict, fits)
        }
    }
}
