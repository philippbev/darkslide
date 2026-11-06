import XCTest
@testable import FujiCookbook

/// What a field-by-field comparison of two recipes says.
///
/// The engine's whole job is to be honest about three different kinds of nothing: a value the
/// recipe deliberately doesn't state, a control the body doesn't have, and a control this recipe's
/// own settings switch off. Collapsing any two of them is the failure mode these tests exist for —
/// the push and the develop both act on the difference between the first and the others.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/07-cameras.md#effect-controls-in-the-menus`, and `docs/03-encodings.md#0xd19c-color-temperature`.
@MainActor
final class SettingsDiffTests: XCTestCase {

    private let registry = CameraModelRegistry.shared
    private var modernBody: CameraModel { registry.demoModel }

    // MARK: The row set

    /// Sixteen fields, nineteen rows, and the split is exact: every field is covered, and no row
    /// belongs to two of them.
    func testTheNineteenRowsCoverEverySixteenFieldsExactlyOnce() {
        XCTAssertEqual(DiffRowID.allCases.count, 19)
        XCTAssertEqual(Set(DiffRowID.allCases.map(\.field)), Set(RecipeField.allCases),
                       "every field has at least one row")
        XCTAssertEqual(Set(DiffRowID.allCases.map(\.id)).count, 19, "row ids are unique")

        let split = Dictionary(grouping: DiffRowID.allCases, by: \.field).filter { $0.value.count > 1 }
        XCTAssertEqual(Set(split.keys), [.monochromaticColor, .grain, .whiteBalance],
                       "exactly three fields split, and these are they")
    }

    /// Declaration order is render order: grouped, and in `RecipeField.allCases` order within each
    /// group, which is the order every other surface in the app iterates.
    func testRowsAreGroupedAndOrderedByTheFieldEnumWithinEachGroup() {
        let groups = DiffRowID.allCases.map(\.group)
        var runs: [String] = []
        for g in groups.map(\.rawValue) where runs.last != g {
            XCTAssertFalse(runs.contains(g), "\(g) appears in two separate runs")
            runs.append(g)
        }
        XCTAssertEqual(runs, DiffGroup.allCases.map(\.rawValue), "groups appear once each, in declared order")

        let order = Dictionary(uniqueKeysWithValues: RecipeField.allCases.enumerated().map { ($1, $0) })
        for group in DiffGroup.allCases {
            let indices = DiffRowID.allCases.filter { $0.group == group }.map { order[$0.field]! }
            XCTAssertEqual(indices, indices.sorted(), "\(group.rawValue) is in field order")
        }
    }

    // MARK: Agreement and difference

    func testTwoIdenticalRecipesDifferOnNothingAndEveryRowIsSame() {
        let rows = SettingsDiff.rows(side(full), side(full))
        XCTAssertTrue(rows.allSatisfy { $0.status == .same || !$0.status.isVisible },
                      "no visible row differs: " + rows.filter { $0.status.isDifference }.map(\.id).joined(separator: ", "))
        let s = SettingsDiff.summary(rows)
        XCTAssertEqual(s.differing, 0)
        XCTAssertEqual(s.same, s.comparable)
    }

    /// Tones and exposure compare within an epsilon, as `RecipeMatcher` does: the same value can
    /// arrive at different precisions, and a row that renders "+0.3 EV → +0.3 EV" must not be a
    /// difference.
    func testTonesAndExposureCompareWithinAnEpsilonRatherThanExactly() {
        let a = RecipeSettings(filmSimulation: .provia, highlightTone: 2.0, exposureBias: 0.33)
        let b = RecipeSettings(filmSimulation: .provia, highlightTone: 2.01, exposureBias: 0.3333)
        let rows = SettingsDiff.rows(side(a), side(b))
        XCTAssertEqual(row("highlightTone", rows).status, .same, "inside the epsilon")
        XCTAssertEqual(row("exposureBias", rows).status, .same, "a third of a stop at two precisions")
        var c = b
        c.highlightTone = 2.5
        XCTAssertEqual(row("highlightTone", SettingsDiff.rows(side(a), side(c))).status, .differs,
                       "half a step apart is a real difference")
    }

    func testARealDifferenceIsReportedOnThatRowAndNoOther() {
        var other = full
        other.clarity = 4
        let rows = SettingsDiff.rows(side(full), side(other))
        XCTAssertEqual(rows.filter { $0.status == .differs }.map(\.id), ["clarity"])
        XCTAssertEqual(row("clarity", rows).a.display, "+3")
        XCTAssertEqual(row("clarity", rows).b.display, "+4")
    }

    /// The decision the whole model turns on. An unset field is a different instruction to the
    /// camera than that field set to zero — the push omits the property and the slot keeps its own.
    func testAnUnsetFieldIsNotTheSameAsThatFieldSetToZero() {
        let unset = RecipeSettings(filmSimulation: .classicChrome)
        let zero = RecipeSettings(filmSimulation: .classicChrome, clarity: 0)

        let r = row("clarity", SettingsDiff.rows(side(unset), side(zero)))
        XCTAssertEqual(r.status, .setOnlyInB, "unset against 0 is a difference, not agreement")
        XCTAssertEqual(r.a.presence, .unset)
        XCTAssertNil(r.a.display, "an unset side renders no value")
        XCTAssertEqual(r.b.display, "+0")
        XCTAssertTrue(r.status.isDifference)
    }

    func testAFieldNeitherSideSetsAppearsInNoViewModeAndNoCount() {
        let bare = RecipeSettings(filmSimulation: .classicChrome)
        let rows = SettingsDiff.rows(side(bare), side(bare))
        let clarity = row("clarity", rows)
        XCTAssertEqual(clarity.status, .neitherSet)
        XCTAssertFalse(clarity.status.isVisible, "hidden in both view modes")
        XCTAssertFalse(clarity.status.isDifference)

        let s = SettingsDiff.summary(rows)
        XCTAssertGreaterThan(s.neitherSet, 0)
        XCTAssertEqual(s.comparable, s.differing + s.same, "neitherSet is outside the denominator")
    }

    /// The soft-Off equivalence is `RecipeMatcher`'s, for photo matching, and it must never reach
    /// here: a recipe that leaves a chrome effect or grain nil has not said "Off".
    func testTheSoftOffEquivalenceDoesNotReachTheDiff() {
        let unset = RecipeSettings(filmSimulation: .classicChrome)
        let off = RecipeSettings(filmSimulation: .classicChrome, grain: GrainEffect(strength: .off, size: nil),
                                 colorChromeEffect: .off, colorChromeFXBlue: .off, dRangePriority: .off)
        let rows = SettingsDiff.rows(side(unset), side(off))
        for id in ["grain.strength", "colorChromeEffect", "colorChromeFXBlue", "dRangePriority"] {
            XCTAssertEqual(row(id, rows).status, .setOnlyInB, "\(id): nil is not Off")
        }
    }

    // MARK: Applicability

    func testClassicChromeAgainstAcrosMakesColorAndMonoRowsApplicabilityDiffers() {
        let colour = RecipeSettings(filmSimulation: .classicChrome, color: 2)
        let mono = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 1)
        let rows = SettingsDiff.rows(side(colour), side(mono))

        XCTAssertEqual(row("color", rows).status, .applicabilityDiffers)
        XCTAssertEqual(row("color", rows).b.presence, .notApplicable(.monochrome))
        XCTAssertNil(row("color", rows).b.display, "an inapplicable side renders no value")
        for id in ["monochromaticColor.wc", "monochromaticColor.mg"] {
            XCTAssertEqual(row(id, rows).status, .applicabilityDiffers, id)
            XCTAssertEqual(row(id, rows).a.presence, .notApplicable(.notMonochrome), id)
        }
    }

    func testAcrosAgainstMonochromeHidesTheColorRowFromBothViewModes() {
        let a = RecipeSettings(filmSimulation: .acros)
        let b = RecipeSettings(filmSimulation: .monochrome)
        let color = row("color", SettingsDiff.rows(side(a), side(b)))
        XCTAssertEqual(color.status, .neitherApplicable)
        XCTAssertFalse(color.status.isVisible)
    }

    /// Sepia hides both, as `RecipeApplicabilityTests` pins (the Color half is open in the record).
    /// The diff holds no opinion of its own —
    /// it reads `RecipeApplicability` — so this moved when that did.
    func testSepiaHidesBothColorAndMonochromaticColor() {
        let sepia = RecipeSettings(filmSimulation: .sepia, monochromaticColorWC: 1)
        let rows = SettingsDiff.rows(side(sepia), side(sepia))
        XCTAssertEqual(row("color", rows).a.presence, .notApplicable(.monochrome))
        XCTAssertEqual(row("monochromaticColor.wc", rows).a.presence, .notApplicable(.fixedToning),
                       "a stored toning value is still not shown — the control does not exist")
        XCTAssertNil(row("monochromaticColor.wc", rows).a.display)
        XCTAssertEqual(row("monochromaticColor.wc", rows).status, .neitherApplicable)
    }

    func testGrainSizeIsNotApplicableWhenEitherSideHasGrainOff() {
        let on = RecipeSettings(filmSimulation: .provia, grain: GrainEffect(strength: .weak, size: .large))
        let off = RecipeSettings(filmSimulation: .provia, grain: GrainEffect(strength: .off, size: .small))
        let rows = SettingsDiff.rows(side(on), side(off))
        XCTAssertEqual(row("grain.size", rows).b.presence, .notApplicable(.grainOff))
        XCTAssertEqual(row("grain.size", rows).status, .applicabilityDiffers)
        XCTAssertEqual(row("grain.strength", rows).status, .differs, "the strength still compares")
    }

    func testGrainSizeIsNotApplicableOnAnXProcessorProBody() throws {
        let pro = try XCTUnwrap(registry.models.first { $0.processor == .xProcessorPro })
        let s = RecipeSettings(filmSimulation: .provia, grain: GrainEffect(strength: .weak, size: .large))
        let rows = SettingsDiff.rows(side(s, pro), side(s, modernBody))
        XCTAssertEqual(row("grain.size", rows).a.presence, .notApplicable(.noGrainSizeControl))
        XCTAssertEqual(row("grain.size", rows).status, .applicabilityDiffers)
    }

    func testTheMagentaGreenAxisIsNotApplicableOnTheXT3() throws {
        let singleAxis = try XCTUnwrap(registry.model(withID: "X-T3"))
        let twoAxisXProcessor4 = try XCTUnwrap(registry.model(withID: "X-T4"))
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 1)
        let rows = SettingsDiff.rows(side(s, singleAxis), side(s, modernBody))
        XCTAssertEqual(row("monochromaticColor.mg", rows).a.presence, .notApplicable(.noMagentaGreenAxis))
        XCTAssertEqual(row("monochromaticColor.wc", rows).status, .same, "the warm–cool axis is on both")
        let both = SettingsDiff.rows(side(s, twoAxisXProcessor4), side(s, modernBody))
        XCTAssertEqual(row("monochromaticColor.mg", both).status, .same, "the X-T4 has the axis, processor or not")
    }

    func testDRangePriorityOnMakesTheRangeAndBothTonesNotApplicable() {
        let s = RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400, dRangePriority: .strong,
                               highlightTone: 2, shadowTone: -1)
        let rows = SettingsDiff.rows(side(s), side(s))
        for id in ["dynamicRange", "highlightTone", "shadowTone"] {
            XCTAssertEqual(row(id, rows).status, .neitherApplicable, id)
            XCTAssertEqual(row(id, rows).a.presence, .notApplicable(.underPriority), id)
        }
        XCTAssertEqual(row("dRangePriority", rows).status, .same, "the priority itself still compares")
    }

    func testAPriorityOnOneSideOnlyMakesThoseRowsApplicabilityDiffers() {
        let on = RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400, dRangePriority: .strong, highlightTone: 2)
        var off = on
        off.dRangePriority = .off
        let rows = SettingsDiff.rows(side(on), side(off))
        XCTAssertEqual(row("dynamicRange", rows).status, .applicabilityDiffers)
        XCTAssertEqual(row("dynamicRange", rows).b.display, "DR400", "the unaffected side still shows its value")
        XCTAssertEqual(row("highlightTone", rows).status, .applicabilityDiffers)
    }

    func testABodyThatLacksClarityMakesThatRowNotApplicableOnThatSideOnly() throws {
        let old = try XCTUnwrap(registry.models.first { !$0.supports(.clarity) })
        let s = RecipeSettings(filmSimulation: .provia, clarity: 3)
        let rows = SettingsDiff.rows(side(s, old), side(s, modernBody))
        XCTAssertEqual(row("clarity", rows).a.presence, .notApplicable(.bodyLacksField))
        XCTAssertEqual(row("clarity", rows).status, .applicabilityDiffers)
    }

    // MARK: White balance

    func testWhiteBalanceModeAndShiftAreSeparateRows() {
        let a = RecipeSettings(whiteBalance: WhiteBalance(mode: .auto, shiftRed: 1, shiftBlue: -1, kelvin: nil))
        let b = RecipeSettings(whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 1, shiftBlue: -1, kelvin: nil))
        let rows = SettingsDiff.rows(side(a), side(b))
        XCTAssertEqual(row("whiteBalance.mode", rows).status, .differs)
        XCTAssertEqual(row("whiteBalance.shift", rows).status, .same,
                       "the same shift under two modes is still the same shift")
        XCTAssertEqual(row("whiteBalance.shift", rows).a.display, "R+1 B−1")
    }

    func testAKelvinModeRendersTheTemperatureInPlaceOfTheModeName() {
        let a = RecipeSettings(whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 0, shiftBlue: 0, kelvin: 5500))
        let b = RecipeSettings(whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 0, shiftBlue: 0, kelvin: 7000))
        let rows = SettingsDiff.rows(side(a), side(b))
        XCTAssertEqual(row("whiteBalance.mode", rows).a.display, "5500K")
        XCTAssertEqual(row("whiteBalance.mode", rows).status, .differs)
    }

    /// A stored temperature outside Color Temperature mode is not a value the camera reads, so two
    /// Daylight recipes agree however they differ on it.
    func testAStoredTemperatureIsIgnoredOutsideColorTemperatureMode() {
        let a = RecipeSettings(whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 0, shiftBlue: 0, kelvin: 5500))
        let b = RecipeSettings(whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 0, shiftBlue: 0, kelvin: 7000))
        XCTAssertEqual(row("whiteBalance.mode", SettingsDiff.rows(side(a), side(b))).status, .same)
    }

    // MARK: Counts and symmetry

    func testDifferingPlusSameEqualsComparable() {
        var other = full
        other.clarity = 0
        other.sharpness = nil
        let s = SettingsDiff.summary(SettingsDiff.rows(side(full), side(other)))
        XCTAssertEqual(s.comparable, s.differing + s.same)
        XCTAssertGreaterThan(s.differing, 0)
    }

    func testComparableAndNotApplicableAndNeitherSetAccountForEveryRow() {
        let mono = RecipeSettings(filmSimulation: .acros, dynamicRange: .dr400, dRangePriority: .strong)
        let rows = SettingsDiff.rows(side(mono), side(full))
        let s = SettingsDiff.summary(rows)
        XCTAssertEqual(s.comparable + s.notApplicable + s.neitherSet, rows.count,
                       "every row lands in exactly one bucket")
    }

    func testSwappingTheSidesMirrorsEveryStatusAndLeavesTheCountsAlone() {
        var other = full
        other.clarity = nil
        other.color = 4
        other.filmSimulation = .acros

        let forward = SettingsDiff.rows(side(full), side(other))
        let back = SettingsDiff.rows(side(other), side(full))
        XCTAssertEqual(forward.count, back.count)

        for (f, b) in zip(forward, back) {
            XCTAssertEqual(f.id, b.id)
            XCTAssertEqual(f.a, b.b, "\(f.id): side A forward is side B backward")
            XCTAssertEqual(f.b, b.a, "\(f.id): side B forward is side A backward")
            switch f.status {
            case .setOnlyInA: XCTAssertEqual(b.status, .setOnlyInB, f.id)
            case .setOnlyInB: XCTAssertEqual(b.status, .setOnlyInA, f.id)
            default: XCTAssertEqual(b.status, f.status, f.id)
            }
        }
        XCTAssertEqual(SettingsDiff.summary(forward), SettingsDiff.summary(back))
    }

    // MARK: Rendering is total

    /// No row ever renders a value it should not have, and every `.set` row renders something. A nil
    /// display on a `.set` row would put an em dash where a value belongs, which is the one glyph
    /// reserved for "the camera will not show you this control".
    func testEveryRowRendersAStringWhenSetAndNothingWhenNot() {
        for settings in [full, RecipeSettings(), .neutral,
                         RecipeSettings(filmSimulation: .acros, monochromaticColorWC: -2, monochromaticColorMG: 3),
                         RecipeSettings(filmSimulation: .provia, grain: GrainEffect(strength: .off, size: nil))] {
            for model in [nil, modernBody] as [CameraModel?] {
                for r in SettingsDiff.rows(side(settings, model), side(settings, model)) {
                    switch r.a.presence {
                    case .set:
                        XCTAssertNotNil(r.a.display, "\(r.id) is set but renders nothing")
                        XCTAssertFalse(r.a.display!.isEmpty, "\(r.id) renders an empty string")
                    case .unset, .notApplicable:
                        XCTAssertNil(r.a.display, "\(r.id) renders a value it has no business showing")
                    }
                }
            }
        }
    }

    // MARK: Fixtures

    private var full: RecipeSettings {
        RecipeSettings(filmSimulation: .classicChrome,
                       grain: GrainEffect(strength: .weak, size: .small),
                       colorChromeEffect: .strong, colorChromeFXBlue: .weak,
                       whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 1, shiftBlue: -2, kelvin: nil),
                       dynamicRange: .dr400, dRangePriority: .off,
                       highlightTone: 1.5, shadowTone: -1, color: 2, sharpness: 1,
                       highISONR: -2, clarity: 3, exposureBias: 0.3, noiseReduction: 0)
    }

    private func side(_ s: RecipeSettings, _ model: CameraModel? = nil) -> DiffSide {
        DiffSide(settings: s, model: model, label: "Side", origin: .recipe(UUID()))
    }

    private func row(_ id: String, _ rows: [DiffRow]) -> DiffRow {
        rows.first { $0.id == id }!
    }
}
