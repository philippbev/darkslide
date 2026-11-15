import Foundation

/// Whether a control applies to a recipe at all — on a given body, under that recipe's own
/// settings. The one place that answers it.
///
/// The editor filters its form with it, `RecipeSettingsFormatter` annotates the read-only table, and
/// `RecipeCompatibility` warns before a push — three surfaces that
/// must agree. A screen that hides a control the camera *does* show, or shows one it will silently
/// ignore, is a lie about the hardware, and copies of a rule drift.
///
/// **Evaluation order is part of the contract: the body gate runs first.** A control the body does
/// not have is inapplicable whatever the settings say, so `bodyProvides` is consulted before any
/// settings-derived rule. The composed rules below already do this; a caller assembling its own
/// composition must too, or it will report `.monochrome` for a control that was never there.
///
/// **What deliberately is *not* here:**
///
/// - **The soft-Off equivalence.** `RecipeMatcher.softOffEnumRow` treats a recipe with no Color
///   Chrome Effect as agreeing with a photo whose value is Off, and `grainRow` does the same for
///   grain. That is correct for photo matching — AI scans and recipe files leave these fields nil
///   when they don't mention them, while a photo always yields a real value — and wrong everywhere
///   else, where nil and Off are two different instructions to the camera. It stays a
///   `RecipeMatcher`-local policy.
/// - **"Off means unset."** `RecipeCompatibility.isSet` reads an Off grain / chrome effect /
///   D-Range Priority as absent, which answers "will the camera ignore this write" rather than
///   "does this control apply". It stays there.
/// - **Whether a value is worth mentioning.** `RecipeCompatibility` raises no monochrome issue for
///   a Color of 0, because a neutral saturation changes nothing either way. That is messaging
///   policy, not applicability.
///
/// Applicability is about the control, never about the value in it.
enum RecipeApplicability {

    /// Why a control does not apply.
    ///
    /// One case per rule, so a surface can say *why* a control is missing rather than only that it
    /// is — an em dash with no reason behind it is indistinguishable from a bug.
    enum Reason: Equatable, Hashable {
        /// Color, on a monochrome simulation (Sepia included — see `FilmSimulation.isMonochrome`).
        case monochrome
        /// Monochromatic Color, on a colour simulation.
        case notMonochrome
        /// Monochromatic Color, on a simulation that is already toned — Sepia.
        case fixedToning
        /// The Monochromatic Color magenta–green axis, on a body with the warm–cool axis alone —
        /// the X-T3 and X-T30.
        case noMagentaGreenAxis
        /// Grain Size, when grain strength is Off.
        case grainOff
        /// Grain Size, on a body with a strength control only (`CameraModel.hasGrainSizeControl`).
        case noGrainSizeControl
        /// Dynamic Range / Highlight Tone / Shadow Tone, with D-Range Priority on.
        case underPriority
        /// The body has no such control at all.
        case bodyLacksField
    }

    /// Applies, or does not and says why. `applies` is what most callers read.
    struct Applicability: Equatable, Hashable {
        let reason: Reason?

        var applies: Bool { reason == nil }

        static let yes = Applicability(reason: nil)
        static func no(_ reason: Reason) -> Applicability { Applicability(reason: reason) }
    }

    // MARK: - Primitives

    // Facts, composed by the rules below. Separate because each caller composes them slightly
    // differently — the editor asks for the magenta–green axis on its own, while the repack asks
    // for the axis *and* monochrome *and* the field — and a caller that can forward its exact
    // expression is a caller that cannot drift.

    /// Whether this recipe's film simulation is a monochrome one.
    ///
    /// Sepia counts, because `FilmSimulation.isMonochrome` counts it: Sepia hides Color. It has no
    /// Monochromatic Color to show either — see ``hasMonochromaticColor``, the narrower set.
    static func isMonochrome(_ s: RecipeSettings) -> Bool {
        isMonochrome(s.filmSimulation)
    }

    /// The same rule where the caller holds a loose simulation rather than whole settings — the
    /// editor's draft, which re-filters its form as the picker changes.
    static func isMonochrome(_ sim: FilmSimulation?) -> Bool {
        sim?.isMonochrome ?? false
    }

    /// Whether this recipe's simulation exposes the Monochromatic Color axes at all.
    ///
    /// Narrower than ``isMonochrome``: Sepia is monochrome and still has no toning to adjust, which
    /// the camera shows by greying the control (X-T50, 2026-09-20).
    static func hasMonochromaticColor(_ s: RecipeSettings) -> Bool {
        hasMonochromaticColor(s.filmSimulation)
    }

    /// The same rule where the caller holds a loose simulation rather than whole settings.
    static func hasMonochromaticColor(_ sim: FilmSimulation?) -> Bool {
        sim?.hasMonochromaticColor ?? false
    }

    /// The Monochromatic Color magenta–green axis: the registry's per-body fact
    /// (`CameraModel.hasMagentaGreenAxis`), from Fujifilm's manuals. Not a processor rule — the
    /// X-Processor 4 bodies from the X-Pro3 on have both axes, and a GFX100S read MG −1 back from
    /// its own menu (fw 2.13, 2026-09-15); only the X-T3 and X-T30 have the warm–cool axis alone.
    ///
    /// Confirmed on an X-T50, 2026-09-20: on ACROS the control is a two-axis grid, warm–cool
    /// against magenta–green, reading `WC 0 MG 0`.
    ///
    /// No body means Generic, which shows the whole superset.
    static func hasMagentaGreenAxis(on model: CameraModel?) -> Bool {
        model?.hasMagentaGreenAxis ?? true
    }

    /// Whether the body has a grain *size* control at all. A per-body registry fact
    /// (`CameraModel.hasGrainSizeControl`), not a processor rule: the X-Processor Pro bodies have
    /// strength only, and so do the X-T3 and X-T30 on X-Processor 4. No body means Generic, which
    /// has the control.
    static func hasGrainSizeControl(on model: CameraModel?) -> Bool {
        model?.hasGrainSizeControl ?? true
    }

    /// The body gate, and the first question every rule asks. No body means Generic — every field.
    static func bodyProvides(_ field: RecipeField, on model: CameraModel?) -> Applicability {
        guard let model else { return .yes }
        return model.supports(field) ? .yes : .no(.bodyLacksField)
    }

    /// The fields a D-Range Priority takes over — exactly these three, and the same three the
    /// editor greys and the push withholds (`RecipeCompatibility`'s `.notWritten`).
    static let fieldsUnderPriority: Set<RecipeField> = [.dynamicRange, .highlightTone, .shadowTone]

    /// Whether this recipe's priority is on for the body it is read against.
    ///
    /// With D-Range Priority on, the camera drives Dynamic Range, Highlight Tone and Shadow Tone
    /// itself and refuses every write to them (X-T50 fw 1.32, 2026-09-18: a full-field push under a
    /// Strong priority had `D19D` and `D19E` refused and everything else written, `D190` not
    /// attempted; an X-H2 account has all three refused. zgrimz/fujifilm-ptp-reference
    /// `docs/04-custom-slots.md#why-a-write-is-refused`).
    ///
    /// A body without the field never receives the priority — the push drops it — so on that body
    /// the range and tones are written as chosen and there is nothing to override. No body means no
    /// gate.
    static func priorityOverrides(_ s: RecipeSettings, on model: CameraModel?) -> Bool {
        priorityOverrides(s.dRangePriority, on: model)
    }

    /// The same rule where the caller holds a loose priority rather than whole settings.
    static func priorityOverrides(_ priority: DRangePriority?, on model: CameraModel?) -> Bool {
        (priority ?? .off) != .off && (model?.supports(.dRangePriority) ?? true)
    }

    // MARK: - Rules

    // The body gate first, then the settings-derived gates.

    /// Color (saturation). Not applicable on a monochrome simulation — the camera ignores the
    /// write.
    static func color(_ s: RecipeSettings, on model: CameraModel?) -> Applicability {
        let body = bodyProvides(.color, on: model)
        guard body.applies else { return body }
        return isMonochrome(s) ? .no(.monochrome) : .yes
    }

    /// Monochromatic Color, warm–cool axis. Monochrome simulations with adjustable toning only:
    /// Sepia's toning is fixed.
    static func monochromaticColorWC(_ s: RecipeSettings, on model: CameraModel?) -> Applicability {
        let body = bodyProvides(.monochromaticColor, on: model)
        guard body.applies else { return body }
        // Two different noes: a colour simulation has no monochrome toning, and Sepia's is fixed.
        guard isMonochrome(s) else { return .no(.notMonochrome) }
        return hasMonochromaticColor(s) ? .yes : .no(.fixedToning)
    }

    /// Monochromatic Color, magenta–green axis: everything the warm–cool axis needs, and a body
    /// that has the axis on top.
    static func monochromaticColorMG(_ s: RecipeSettings, on model: CameraModel?) -> Applicability {
        let wc = monochromaticColorWC(s, on: model)
        guard wc.applies else { return wc }
        return hasMagentaGreenAxis(on: model) ? .yes : .no(.noMagentaGreenAxis)
    }

    /// Grain Size. Two settings-derived gates after the body's: a size is meaningless with the
    /// strength Off, and the older bodies have no size control to set.
    static func grainSize(_ s: RecipeSettings, on model: CameraModel?) -> Applicability {
        let body = bodyProvides(.grain, on: model)
        guard body.applies else { return body }
        if (s.grain?.strength ?? .off) == .off { return .no(.grainOff) }
        return hasGrainSizeControl(on: model) ? .yes : .no(.noGrainSizeControl)
    }

    /// Any field, under the D-Range Priority interlock. The three fields the priority drives are
    /// not applicable while it is on; the other rows are unaffected — measured, not assumed
    /// (X-T50 fw 1.32, 2026-09-18).
    static func underPriority(_ field: RecipeField, in s: RecipeSettings, on model: CameraModel?) -> Applicability {
        let body = bodyProvides(field, on: model)
        guard body.applies else { return body }
        guard fieldsUnderPriority.contains(field), priorityOverrides(s, on: model) else { return .yes }
        return .no(.underPriority)
    }
}
