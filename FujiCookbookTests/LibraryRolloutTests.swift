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

    func testTheHeaderCountsTheArchiveAndNamesTheFirstCamera() {
        XCTAssertEqual(LibraryHeaderFields.fields(recipeCount: 24, cameraIDs: ["X100VI", "X-T5"]),
                       [DSDataField(label: "Archive", value: "024"), DSDataField(label: "Camera", value: "X100VI")])
        XCTAssertEqual(LibraryHeaderFields.fields(recipeCount: 0, cameraIDs: []).map(\.value), ["000", "—"])
    }
}
