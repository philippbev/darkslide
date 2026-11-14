import XCTest
@testable import FujiCookbook

/// What the recipe's archive card says: its head, its data sheet and its foot. Values are
/// separated by space alone, never by a "·".
final class RecipeDetailArchiveTests: XCTestCase {

    private typealias Archive = RecipeDetailArchive

    private func settings() -> RecipeSettings {
        var settings = RecipeSettings.neutral
        settings.filmSimulation = .classicChrome
        return settings
    }

    func testTheDataSheetLeavesTheFilmSimulationToTheBand() {
        let fields = Archive.dataSheetFields(for: settings())
        XCTAssertFalse(fields.isEmpty)
        XCTAssertFalse(fields.contains { $0.label == RecipeField.filmSimulation.displayName })
        XCTAssertEqual(fields.map(\.label),
                       RecipeSettingsFormatter.rows(for: settings()).map(\.field.displayName).filter {
                           $0 != RecipeField.filmSimulation.displayName
                       })
    }

    func testNoValueInTheSheetUsesADot() {
        var withShift = settings()
        withShift.whiteBalance = WhiteBalance(mode: .auto, shiftRed: 3, shiftBlue: -5, kelvin: nil)
        for field in Archive.dataSheetFields(for: withShift) {
            XCTAssertFalse(field.value.contains("·"), "\(field.label): \(field.value)")
        }
        XCTAssertEqual(Archive.spaced("Auto · R+3 B\u{2212}5"), "Auto   R+3 B\u{2212}5")
    }

    func testAGeneratedSlotNameSaysWhereItComesFrom() {
        XCTAssertEqual(Archive.slotNameField(name: "CLASSIC CHROME", isCustom: false).note, "From name")
        XCTAssertNil(Archive.slotNameField(name: "KODA64", isCustom: true).note)
    }

    func testTheSideFieldsAreSlotChapterAndCreated() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let created = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9))!
        XCTAssertEqual(Archive.sideFields(slot: "C3", chapterNames: ["Street"], createdAt: created, calendar: calendar),
                       [DSDataField(label: "Slot", value: "C3"),
                        DSDataField(label: "Chapter", value: "Street"),
                        DSDataField(label: "Created", value: "2026-03-07")])
        XCTAssertEqual(Archive.sideFields(slot: nil, chapterNames: [], createdAt: created, calendar: calendar).prefix(2).map(\.value),
                       ["—", "—"])
    }

    func testMoreThanOneChapterShowsTheFirstAndTheCount() {
        XCTAssertEqual(Archive.chapterValue(["Street", "Travel", "Night"]), "Street +2")
    }

    func testTheFootNamesTheCameraAndItsVerdict() {
        XCTAssertEqual(Archive.footer(cameraID: "X100VI", verdict: .worksAsWritten), "X100VI   Works as written")
        XCTAssertEqual(Archive.footer(cameraID: nil, verdict: .worksAsWritten), "")
        XCTAssertFalse(Archive.footer(cameraID: "X-T5", verdict: .worksWithChanges).contains("·"))
    }
}
