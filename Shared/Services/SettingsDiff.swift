import Foundation

// MARK: - Rows

/// How the compare screen buckets rows. Presentation, not logic — the engine tags each row and the
/// view decides what to do with the tag. Case order is the render order, and the order
/// `DiffRowID.allCases` is declared in.
enum DiffGroup: String, CaseIterable, Hashable {
    case base, tone, colour, detail, exposure

    var displayName: String {
        switch self {
        case .base: return "Base"
        case .tone: return "Tone"
        case .colour: return "Color"
        case .detail: return "Detail"
        case .exposure: return "Exposure"
        }
    }
}

/// One row of a settings comparison.
///
/// **Rows are not fields.** Three of the sixteen `RecipeField`s carry two independent controls, and
/// collapsing them loses the thing a comparison exists to say. `RecipeMatcher` already split White
/// Balance for this reason — "Auto R+1 B−1 vs Daylight R+1 B−1" and "Daylight R+1 B−1 vs Daylight
/// R0 B0" are different kinds of disagreement and one row cannot say which — and the same argument
/// applies twice more:
///
/// - **Monochromatic Color** is one control with two axes — the camera draws a single grid,
///   warm–cool against magenta–green (X-T50, 2026-09-20) — but their applicability is independent:
///   the X-T3 and X-T30 have the warm–cool axis alone (`CameraModel.hasMagentaGreenAxis`), so one
///   collapsed row on a body without it would have to claim a difference on a control that isn't
///   there.
/// - **Grain** is a strength and a size, where the size is absent on bodies without a size control
///   (`CameraModel.hasGrainSizeControl`) and meaningless when the strength is Off.
///
/// Declaration order is the canonical render order: by `group`, then by `RecipeField.allCases`
/// order within it, which is the order every other surface in the app already iterates.
enum DiffRowID: String, CaseIterable, Identifiable, Hashable {
    // Base
    case filmSimulation
    case monochromaticColorWC = "monochromaticColor.wc"
    case monochromaticColorMG = "monochromaticColor.mg"
    // Tone
    case dynamicRange
    case dRangePriority
    case highlightTone
    case shadowTone
    // Colour
    case colorChromeEffect
    case colorChromeFXBlue
    case whiteBalanceMode = "whiteBalance.mode"
    case whiteBalanceShift = "whiteBalance.shift"
    case color
    // Detail
    case grainStrength = "grain.strength"
    case grainSize = "grain.size"
    case sharpness
    case highISONR
    case clarity
    // Exposure
    case exposureBias
    case noiseReduction

    var id: String { rawValue }

    /// The field this row belongs to — what the body gate and the grouping are asked about. Several
    /// rows share one field, which is the whole point.
    var field: RecipeField {
        switch self {
        case .filmSimulation: return .filmSimulation
        case .monochromaticColorWC, .monochromaticColorMG: return .monochromaticColor
        case .dynamicRange: return .dynamicRange
        case .dRangePriority: return .dRangePriority
        case .highlightTone: return .highlightTone
        case .shadowTone: return .shadowTone
        case .colorChromeEffect: return .colorChromeEffect
        case .colorChromeFXBlue: return .colorChromeFXBlue
        case .whiteBalanceMode, .whiteBalanceShift: return .whiteBalance
        case .color: return .color
        case .grainStrength, .grainSize: return .grain
        case .sharpness: return .sharpness
        case .highISONR: return .highISONR
        case .clarity: return .clarity
        case .exposureBias: return .exposureBias
        case .noiseReduction: return .noiseReduction
        }
    }

    var group: DiffGroup {
        switch self {
        case .filmSimulation, .monochromaticColorWC, .monochromaticColorMG: return .base
        case .dynamicRange, .dRangePriority, .highlightTone, .shadowTone: return .tone
        case .colorChromeEffect, .colorChromeFXBlue, .whiteBalanceMode, .whiteBalanceShift, .color: return .colour
        case .grainStrength, .grainSize, .sharpness, .highISONR, .clarity: return .detail
        case .exposureBias, .noiseReduction: return .exposure
        }
    }

    /// The row's own name. Falls back to the field's for rows that are the whole field, so a
    /// display-name change in one place moves both.
    var label: String {
        switch self {
        case .monochromaticColorWC: return "Monochromatic Color · WC"
        case .monochromaticColorMG: return "Monochromatic Color · MG"
        case .whiteBalanceMode: return "White Balance"
        case .whiteBalanceShift: return "WB Shift"
        case .grainStrength: return "Grain Effect"
        case .grainSize: return "Grain Size"
        default: return field.displayName
        }
    }

    /// Whether this recipe states a value for the row.
    ///
    /// A plain nil check, deliberately. **Do not** reach for `RecipeCompatibility.isSet`: it reads an
    /// Off grain / chrome effect / D-Range Priority as absent, which answers "will the camera ignore
    /// this write" and is the opposite of what a comparison needs — an Off a user chose is a value,
    /// and `nil` against Off is the single most consequential difference this engine reports.
    func isSet(in s: RecipeSettings) -> Bool {
        switch self {
        case .filmSimulation: return s.filmSimulation != nil
        case .monochromaticColorWC: return s.monochromaticColorWC != nil
        case .monochromaticColorMG: return s.monochromaticColorMG != nil
        case .dynamicRange: return s.dynamicRange != nil
        case .dRangePriority: return s.dRangePriority != nil
        case .highlightTone: return s.highlightTone != nil
        case .shadowTone: return s.shadowTone != nil
        case .colorChromeEffect: return s.colorChromeEffect != nil
        case .colorChromeFXBlue: return s.colorChromeFXBlue != nil
        // The shift lives inside `WhiteBalance` and is non-optional there, so the struct's presence
        // is what decides both white-balance rows.
        case .whiteBalanceMode, .whiteBalanceShift: return s.whiteBalance != nil
        case .color: return s.color != nil
        case .grainStrength: return s.grain != nil
        case .grainSize: return s.grain?.size != nil
        case .sharpness: return s.sharpness != nil
        case .highISONR: return s.highISONR != nil
        case .clarity: return s.clarity != nil
        case .exposureBias: return s.exposureBias != nil
        case .noiseReduction: return s.noiseReduction != nil
        }
    }

    /// Whether two recipes agree on this row. Only ever asked when both sides are `.set`.
    func equal(_ a: RecipeSettings, _ b: RecipeSettings) -> Bool {
        switch self {
        case .filmSimulation: return a.filmSimulation == b.filmSimulation
        case .monochromaticColorWC: return a.monochromaticColorWC == b.monochromaticColorWC
        case .monochromaticColorMG: return a.monochromaticColorMG == b.monochromaticColorMG
        case .dynamicRange: return a.dynamicRange == b.dynamicRange
        case .dRangePriority: return a.dRangePriority == b.dRangePriority
        case .highlightTone: return Self.approximately(a.highlightTone, b.highlightTone)
        case .shadowTone: return Self.approximately(a.shadowTone, b.shadowTone)
        case .colorChromeEffect: return a.colorChromeEffect == b.colorChromeEffect
        case .colorChromeFXBlue: return a.colorChromeFXBlue == b.colorChromeFXBlue
        case .whiteBalanceMode:
            // The mode *is* the temperature when it uses one, so two Color Temperature recipes at
            // different Kelvin disagree here — and two Daylight recipes with different remembered
            // temperatures do not, because the camera never reads one.
            guard let x = a.whiteBalance, let y = b.whiteBalance, x.mode == y.mode else { return false }
            return !x.mode.usesKelvin || x.kelvin == y.kelvin
        case .whiteBalanceShift:
            guard let x = a.whiteBalance, let y = b.whiteBalance else { return false }
            return x.shiftRed == y.shiftRed && x.shiftBlue == y.shiftBlue
        case .color: return a.color == b.color
        case .grainStrength: return a.grain?.strength == b.grain?.strength
        case .grainSize: return a.grain?.size == b.grain?.size
        case .sharpness: return a.sharpness == b.sharpness
        case .highISONR: return a.highISONR == b.highISONR
        case .clarity: return a.clarity == b.clarity
        case .exposureBias: return Self.approximately(a.exposureBias, b.exposureBias)
        case .noiseReduction: return a.noiseReduction == b.noiseReduction
        }
    }

    /// Tones and exposure compare within `RecipeMatcher.toneEpsilon` rather than exactly, for the
    /// same reason: the finest real step is 0.0625, and one value can arrive from the editor, a
    /// slot read, a file and the scanner at different precisions. Two rows that render identically
    /// must not read as different.
    private static func approximately(_ x: Double?, _ y: Double?) -> Bool {
        guard let x, let y else { return x == y }
        return abs(x - y) < RecipeMatcher.toneEpsilon
    }

    /// Whether this row applies, on this side, and why not when it doesn't.
    ///
    /// Every answer comes from `RecipeApplicability`. A row that needs a rule this doesn't have
    /// wants the rule added there, not a second opinion here.
    func applicability(in s: RecipeSettings, on model: CameraModel?) -> RecipeApplicability.Applicability {
        switch self {
        case .color:
            return RecipeApplicability.color(s, on: model)
        case .monochromaticColorWC:
            return RecipeApplicability.monochromaticColorWC(s, on: model)
        case .monochromaticColorMG:
            return RecipeApplicability.monochromaticColorMG(s, on: model)
        case .grainSize:
            return RecipeApplicability.grainSize(s, on: model)
        default:
            // The body gate, plus the D-Range Priority interlock for the three fields it drives.
            return RecipeApplicability.underPriority(field, in: s, on: model)
        }
    }
}

// MARK: - Presence

/// Why a side shows nothing for a row. Three states, because the two wire paths act on the
/// difference between them.
///
/// The push doesn't write an unset High ISO NR, so the camera slot keeps its own, where a 0 writes
/// 0; `FujiRawConvProfile.patch` writes every field only when set, so an unset field leaves the
/// RAF's as-shot sentinel alone. A screen that renders both as one dash hides exactly that.
/// `RecipeDraft` keeps the same distinction for every field without a neutral default.
enum Presence: Equatable, Hashable {
    /// The recipe states a value.
    case set
    /// The recipe deliberately states nothing.
    case unset
    /// The control does not apply here at all. The reason is `RecipeApplicability`'s, not a second
    /// vocabulary — there is one set of rules and this is how it reaches the screen.
    case notApplicable(RecipeApplicability.Reason)

    var applies: Bool {
        if case .notApplicable = self { return false }
        return true
    }
}

/// One side of one row, ready to render.
struct SideValue: Equatable, Hashable {
    /// Formatted for display, or nil when there is nothing to show.
    let display: String?
    let presence: Presence
}

enum DiffStatus: Equatable, Hashable {
    /// Both state a value, and they agree.
    case same
    /// Both state a value, and they disagree.
    case differs
    /// One states a value and the other deliberately states nothing.
    ///
    /// Its own status rather than a flavour of `.differs`, because it is a different sentence: a
    /// recipe with Clarity unset is not a recipe with Clarity 0, and the screen says "Not set" —
    /// the phrase `OptionalSliderRow` already teaches in the editor.
    case setOnlyInA, setOnlyInB
    /// Neither states a value. Hidden entirely, and counted nowhere.
    case neitherSet
    /// The control applies on one side only — two recipes on Classic Chrome and Acros disagree
    /// about whether Color is a control at all. A real and common row, not an edge case.
    case applicabilityDiffers
    /// The control applies to neither side. Hidden entirely.
    case neitherApplicable

    /// Whether this row is a difference the user should be shown.
    var isDifference: Bool {
        switch self {
        case .differs, .setOnlyInA, .setOnlyInB, .applicabilityDiffers: return true
        case .same, .neitherSet, .neitherApplicable: return false
        }
    }

    /// Whether this row appears in any view mode at all.
    var isVisible: Bool {
        switch self {
        case .neitherSet, .neitherApplicable: return false
        default: return true
        }
    }
}

struct DiffRow: Identifiable, Equatable, Hashable {
    let row: DiffRowID
    let a: SideValue
    let b: SideValue
    let status: DiffStatus

    var id: String { row.id }
    var label: String { row.label }
    var group: DiffGroup { row.group }
}

// MARK: - Sides

/// One side of a comparison: the settings, plus the two things that decide what they *mean* —
/// where they came from, and which body they are read against.
struct DiffSide: Equatable {
    let settings: RecipeSettings
    /// The body this side's applicability is evaluated against. nil == Generic, every field.
    let model: CameraModel?
    /// What the header calls this side. "Sunday Chrome", "Slot C1", "This photo".
    let label: String
    let origin: Origin

    /// Where a side came from. Resolving `model` from it is a decision per case, not an obvious
    /// default: a recipe's body is the one it was authored for, while a **slot's** is the body in
    /// your hand, because a slot's values are facts about that camera.
    enum Origin: Equatable, Hashable {
        /// `Recipe.uuid` — never `persistentModelID`, which mutates on first autosave.
        case recipe(UUID)
        case slot(index: Int)
        /// A `PortableRecipe` being imported.
        case incoming
        /// EXIF-decoded, via `PhotoRecipeReader`.
        case photo
    }
}

// MARK: - Counts

/// The counts the summary line reads from.
///
/// It reads against `comparable`, never the row count. "3 of 19 differ" when four rows are mono-only
/// is wrong; "3 of 15 differ · 4 don't apply to both" is right.
struct DiffSummary: Equatable, Hashable {
    let differing: Int
    let same: Int
    /// `differing + same` — the denominator.
    let comparable: Int
    let notApplicable: Int
    /// Hidden, and not mentioned.
    let neitherSet: Int
}

// MARK: - The engine

/// A field-by-field comparison of two recipes.
///
/// Pure and synchronous: no view layer, no SwiftData, no camera. Compute once per pair and keep
/// the rows in state, as `RecipeCompareView` does, rather than inside a SwiftUI `body`.
enum SettingsDiff {

    /// Every row, in canonical order, including the ones no view mode shows — the caller filters,
    /// so that toggling between "differences" and "all settings" never recomputes.
    static func rows(_ a: DiffSide, _ b: DiffSide) -> [DiffRow] {
        DiffRowID.allCases.map { row in
            let sideA = value(row, in: a)
            let sideB = value(row, in: b)
            return DiffRow(row: row, a: sideA, b: sideB,
                           status: status(row, sideA.presence, sideB.presence, a.settings, b.settings))
        }
    }

    static func summary(_ rows: [DiffRow]) -> DiffSummary {
        var differing = 0, same = 0, notApplicable = 0, neitherSet = 0
        for row in rows {
            switch row.status {
            case .differs, .setOnlyInA, .setOnlyInB: differing += 1
            case .same: same += 1
            case .applicabilityDiffers, .neitherApplicable: notApplicable += 1
            case .neitherSet: neitherSet += 1
            }
        }
        return DiffSummary(differing: differing, same: same, comparable: differing + same,
                           notApplicable: notApplicable, neitherSet: neitherSet)
    }

    // MARK: Per side

    private static func value(_ row: DiffRowID, in side: DiffSide) -> SideValue {
        let applicability = row.applicability(in: side.settings, on: side.model)
        if let reason = applicability.reason {
            // Nothing to show, whatever the recipe happens to store. A value behind an inapplicable
            // control is not a value the camera will ever read.
            return SideValue(display: nil, presence: .notApplicable(reason))
        }
        guard row.isSet(in: side.settings) else {
            return SideValue(display: nil, presence: .unset)
        }
        return SideValue(display: RecipeSettingsFormatter.valueString(forRow: row, in: side.settings),
                         presence: .set)
    }

    private static func status(_ row: DiffRowID,
                               _ a: Presence, _ b: Presence,
                               _ sa: RecipeSettings, _ sb: RecipeSettings) -> DiffStatus {
        switch (a, b) {
        case (.notApplicable, .notApplicable): return .neitherApplicable
        case (.notApplicable, _), (_, .notApplicable): return .applicabilityDiffers
        case (.unset, .unset): return .neitherSet
        case (.set, .unset): return .setOnlyInA
        case (.unset, .set): return .setOnlyInB
        case (.set, .set): return row.equal(sa, sb) ? .same : .differs
        }
    }
}
