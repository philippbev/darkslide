import XCTest
@testable import FujiCookbook

/// The Library on the design system: the values its archive row and header show. Mono lines
/// separate their parts by space alone, never by a "·".
final class LibraryRolloutTests: XCTestCase {

    func testTheRowShowsTheArchiveNumberWithThreeDigits() {
        XCTAssertEqual(RecipeRow.objectNumber(34), "034")
        XCTAssertEqual(RecipeRow.objectNumber(1), "001")
        XCTAssertEqual(RecipeRow.objectNumber(1234), "1234")
    }

    func testARecipeTheNumberingHasNotReachedShowsADash() {
        XCTAssertEqual(RecipeRow.objectNumber(0), "—")
    }

    func testTheMetaLineIsFilmSimulationThenBody() throws {
        let x100vi = try XCTUnwrap(CameraModelRegistry.shared.model(withID: "X100VI"))
        let meta = RecipeRow.meta(filmSimulation: .classicChrome, authoredFor: x100vi)
        XCTAssertEqual(meta, "\(FilmSimulation.classicChrome.displayName)   X100VI")
        XCTAssertFalse(meta.contains("·"))
        XCTAssertEqual(RecipeRow.meta(filmSimulation: nil, authoredFor: nil), "No film simulation")
    }

    func testTheHeaderCountsTheArchive() {
        XCTAssertEqual(LibraryHeaderFields.fields(recipeCount: 24, camera: .neverRead).first,
                       DSDataField(label: "Archive", value: "024"))
    }

    func testACameraNeverReadShowsADashAndNoLED() {
        let field = LibraryHeaderFields.fields(recipeCount: 0, camera: .neverRead)[1]
        XCTAssertEqual(field, DSDataField(label: "Camera", value: "—", led: nil, note: nil))
    }

    func testTheConnectedCameraShowsItsSlotsWithTheLEDLit() {
        let field = LibraryHeaderFields.fields(
            recipeCount: 0, camera: LibraryCameraField(snapshot: snapshot(occupied: 5, of: 7), connectedCameraName: "X100VI"))[1]
        XCTAssertEqual(field, DSDataField(label: "Camera", value: "5/7", led: true, note: nil))
    }

    func testAnUnpluggedCameraShowsItsLastReadWithTheDateAndTheLEDOff() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let read = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        let camera = LibraryCameraField(snapshot: snapshot(occupied: 5, of: 7, readAt: read),
                                        connectedCameraName: nil, calendar: calendar)
        XCTAssertEqual(LibraryHeaderFields.fields(recipeCount: 0, camera: camera)[1],
                       DSDataField(label: "Camera", value: "5/7", led: false, note: "As of 04.11."))
        // Another camera on the cable doesn't light this one's LED.
        XCTAssertFalse(LibraryCameraField(snapshot: snapshot(occupied: 5, of: 7), connectedCameraName: "X-T5").isLive)
    }

    private func snapshot(occupied: Int, of count: Int, readAt: Date = Date()) -> CameraSlotSnapshot {
        CameraSlotSnapshot(cameraName: "X100VI", slotCount: count, readAt: readAt,
                           slots: (1...count).map {
                               CameraSlotSnapshot.Slot(index: $0, label: "C\($0)", isOccupied: $0 <= occupied,
                                                       name: nil, settings: nil)
                           })
    }
}
