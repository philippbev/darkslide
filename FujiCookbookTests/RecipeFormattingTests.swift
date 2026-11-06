import XCTest
@testable import FujiCookbook

/// What the read-only screens say about a recipe under a D-Range Priority.
///
/// The editor greys Dynamic Range, Highlight Tone and Shadow Tone out while the priority is on,
/// because the camera drives all three and refuses the recipe's values for them. Six screens
/// render a recipe through `RecipeSettingsFormatter.rows(for:)` with no editor in sight — the
/// detail view, the share extension's card, the Kitchen's read, the Camera Test's push preview
/// and its menu comparison, the recommender's summary — and until the note existed every one of
/// them showed "Dynamic Range: DR400" under a Strong priority as a choice the camera would honour.
@MainActor
final class RecipeFormattingTests: XCTestCase {

    private let registry = CameraModelRegistry.shared

    private func value(_ field: RecipeField, in s: RecipeSettings, model: CameraModel? = nil) -> String? {
        RecipeSettingsFormatter.rows(for: s, model: model).first { $0.field == field }?.value
    }

    private let note = RecipeSettingsFormatter.priorityNote

    // MARK: The three rows

    func testTheThreeFieldsThePriorityDrivesSaySoAndNothingElseDoes() {
        let s = RecipeSettings(filmSimulation: .classicChrome, dynamicRange: .dr400,
                               dRangePriority: .strong, highlightTone: 2, shadowTone: -1, color: 3)
        XCTAssertEqual(value(.dynamicRange, in: s), "DR400 · \(note)")
        XCTAssertEqual(value(.highlightTone, in: s), "+2 · \(note)")
        XCTAssertEqual(value(.shadowTone, in: s), "−1 · \(note)")
        XCTAssertEqual(value(.dRangePriority, in: s), "Strong")
        XCTAssertEqual(value(.color, in: s), "+3")
        XCTAssertEqual(value(.filmSimulation, in: s), FilmSimulation.classicChrome.displayName)
    }

    /// The note is the wire truth, so it has to say what the wire does: the same three fields
    /// `RecipeCompatibility` withholds from a push under a priority, no more and no fewer.
    func testTheNotedFieldsAreTheOnesThePushWithholds() {
        let s = RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400, dRangePriority: .weak,
                               highlightTone: 1, shadowTone: 1, color: 1, sharpness: 1, clarity: 1)
        let withheld = Set(RecipeCompatibility.analyze(s, for: registry.demoModel)
            .filter { if case .notWritten = $0.kind { return true } else { return false } }.map(\.field))
        let noted = Set(RecipeSettingsFormatter.rows(for: s, model: registry.demoModel)
            .filter { $0.value.hasSuffix(note) }.map(\.field))
        XCTAssertEqual(noted, withheld)
        XCTAssertEqual(noted, RecipeApplicability.fieldsUnderPriority)
    }

    func testEveryPriorityButOffOverrides() {
        for drp in DRangePriority.allCases where drp != .off {
            let s = RecipeSettings(dynamicRange: .dr400, dRangePriority: drp)
            XCTAssertEqual(value(.dynamicRange, in: s), "DR400 · \(note)", drp.displayName)
        }
    }

    func testOffAndUnsetPrioritiesLeaveTheValuesBare() {
        XCTAssertEqual(value(.dynamicRange, in: RecipeSettings(dynamicRange: .dr400, dRangePriority: .off)), "DR400")
        XCTAssertEqual(value(.dynamicRange, in: RecipeSettings(dynamicRange: .dr400)), "DR400")
        XCTAssertEqual(value(.highlightTone, in: RecipeSettings(dRangePriority: .off, highlightTone: 2)), "+2")
        XCTAssertEqual(value(.shadowTone, in: RecipeSettings(shadowTone: -0.5)), "−0.5")
    }

    // MARK: The body gate

    /// A body without the field never receives the priority — the push drops it — so its range
    /// and tones are written exactly as chosen, and a note would be a lie on that screen.
    func testABodyWithoutThePriorityFieldShowsTheValuesAsChosen() throws {
        let genIII = try XCTUnwrap(registry.models.first { !$0.supports(.dRangePriority) },
                                   "the test needs a registry body without D-Range Priority")
        let s = RecipeSettings(dynamicRange: .dr400, dRangePriority: .strong, highlightTone: 2)
        XCTAssertEqual(value(.dynamicRange, in: s, model: genIII), "DR400")
        XCTAssertEqual(value(.highlightTone, in: s, model: genIII), "+2")
        XCTAssertNil(value(.dRangePriority, in: s, model: genIII), "the field itself is not shown for a body without it")

        let withField = try XCTUnwrap(registry.models.first { $0.supports(.dRangePriority) })
        XCTAssertEqual(value(.dynamicRange, in: s, model: withField), "DR400 · \(note)")
    }

    // MARK: The surfaces that copy the string

    /// The Camera Test snapshots what the app displayed for the tester's menu comparison. The note
    /// belongs in that snapshot: under the priority the camera drives those three items
    /// (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md#the-d-range-priority-interlock`), and a
    /// tester comparing "DR400" with the menu has nothing else to tell them why they differ.
    func testTheMenuComparisonSnapshotsTheNote() throws {
        let model = try XCTUnwrap(registry.models.first { $0.supports(.dRangePriority) })
        let slot = CameraSlot(index: 2, label: "C2", name: "Curve", isOccupied: true,
                              settings: RecipeSettings(filmSimulation: .provia, dynamicRange: .dr200,
                                                       dRangePriority: .auto, highlightTone: 0.5),
                              rawProperties: [:], unsupportedFields: [:])
        let rows = GuidedTestFlow.comparison(for: slot, model: model).rows
        XCTAssertEqual(rows.first { $0.field == RecipeField.dynamicRange.rawValue }?.appShowed, "DR200 · \(note)")
        XCTAssertEqual(rows.first { $0.field == RecipeField.highlightTone.rawValue }?.appShowed, "+0.5 · \(note)")
        XCTAssertEqual(rows.first { $0.field == RecipeField.dRangePriority.rawValue }?.appShowed, "Auto")
    }

    /// The headline chips on a card lead with the range and tones. Under a priority they are the
    /// camera's, so the chip that replaces them is the priority itself.
    func testTheHeadlineChipsNameThePriorityInsteadOfTheRangeItOverrides() {
        let on = RecipeSettingsFormatter.chips(for: RecipeSettings(
            dynamicRange: .dr400, dRangePriority: .strong, highlightTone: 2, shadowTone: -1, color: 3))
        XCTAssertEqual(on.first, "DRP Strong")
        XCTAssertFalse(on.contains("DR400"))
        XCTAssertFalse(on.contains { $0.hasPrefix("HL ") || $0.hasPrefix("SH ") })
        XCTAssertTrue(on.contains("Color +3"), "the rest of the row is untouched")

        let off = RecipeSettingsFormatter.chips(for: RecipeSettings(
            dynamicRange: .dr400, dRangePriority: .off, highlightTone: 2, shadowTone: -1))
        XCTAssertEqual(Array(off.prefix(3)), ["DR400", "HL +2", "SH −1"])
        XCTAssertFalse(off.contains { $0.hasPrefix("DRP") }, "an Off priority is not a headline")
    }

    // MARK: The summary line

    /// Slot rows, import review and the library all show this line, so it is pinned once: the film
    /// simulation, then the dynamic range, and nothing invented for what the recipe leaves unset.
    func testSummaryIsFilmSimulationThenDynamicRangeAsFarAsTheyAreSet() {
        XCTAssertEqual(RecipeSettingsFormatter.summary(for: RecipeSettings(filmSimulation: .classicChrome, dynamicRange: .dr400)),
                       "Classic Chrome · DR400")
        XCTAssertEqual(RecipeSettingsFormatter.summary(for: RecipeSettings(filmSimulation: .acrosR)), "ACROS + R Filter")
        XCTAssertEqual(RecipeSettingsFormatter.summary(for: RecipeSettings(dynamicRange: .dr200)), "DR200")
        XCTAssertEqual(RecipeSettingsFormatter.summary(for: RecipeSettings()), "")
    }
}
