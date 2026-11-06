import XCTest
@testable import FujiCookbook

/// The Library's camera facet: a body that can't run the recipe's film simulation hides it;
/// anything less definite stays, and the Works With card says what the change is.
final class RecipeFilterCameraTests: XCTestCase {

    private let registry = CameraModelRegistry.shared

    private func body(_ id: String) throws -> CameraModel { try XCTUnwrap(registry.model(withID: id)) }

    private func choice(_ name: String, _ settings: RecipeSettings?, favorite: Bool = false) -> RecipeChoice {
        RecipeChoice(ref: .library(UUID()), name: name, filmSimulation: settings?.filmSimulation,
                     summary: "", isFavorite: favorite, badge: nil, notes: "", tags: [],
                     updatedAt: .distantPast, settings: settings)
    }

    private let classicNeg = RecipeSettings(filmSimulation: .classicNeg)
    private let provia = RecipeSettings(filmSimulation: .provia)
    private let clarity = RecipeSettings(filmSimulation: .provia, clarity: 3)

    func testACameraFacetHidesRecipesWhoseFilmSimulationTheBodyLacks() throws {
        let rows = [choice("Neg", classicNeg), choice("Std", provia)]
        var filter = RecipeFilter()
        filter.camera = try body("X-T3")
        XCTAssertEqual(filter.apply(to: rows).map(\.name), ["Std"])
        filter.camera = try body("X-T50")
        XCTAssertEqual(filter.apply(to: rows).map(\.name), ["Neg", "Std"])
    }

    func testACameraFacetKeepsRecipesThatWorkWithChanges() throws {
        var filter = RecipeFilter()
        filter.camera = try body("GFX50S")
        XCTAssertEqual(filter.apply(to: [choice("Clear", clarity)]).map(\.name), ["Clear"])
    }

    func testACameraFacetKeepsARecipeWithNoFilmSimulation() throws {
        var filter = RecipeFilter()
        filter.camera = try body("X-T3")
        XCTAssertEqual(filter.apply(to: [choice("Blank", RecipeSettings())]).map(\.name), ["Blank"])
    }

    /// A camera slot the reader couldn't decode has no settings to judge; hiding it would make a
    /// decode failure look like an incompatibility.
    func testARowWithoutSettingsIsNotHidden() throws {
        var filter = RecipeFilter()
        filter.camera = try body("X-T3")
        XCTAssertEqual(filter.apply(to: [choice("Slot", nil)]).map(\.name), ["Slot"])
    }

    func testTheCameraFacetCountsAsActiveAndClearsWithTheOthers() throws {
        var filter = RecipeFilter()
        XCTAssertFalse(filter.isActive)
        filter.camera = try body("X-T3")
        XCTAssertTrue(filter.isActive)
        filter.clearFacets()
        XCTAssertNil(filter.camera)
        XCTAssertFalse(filter.isActive)
    }

    func testTheCameraFacetComposesWithFavoritesAndSearch() throws {
        let rows = [choice("Neg fav", classicNeg, favorite: true),
                    choice("Std fav", provia, favorite: true),
                    choice("Std", provia)]
        var filter = RecipeFilter()
        filter.camera = try body("X-T3")
        filter.favoritesOnly = true
        XCTAssertEqual(filter.apply(to: rows).map(\.name), ["Std fav"])
        filter.favoritesOnly = false
        XCTAssertEqual(filter.apply(to: rows, matching: "Std").map(\.name), ["Std", "Std fav"])
    }

    // MARK: - The controls' camera lists

    /// A body picked from the menu, or dropped from My Cameras while selected, keeps a chip; an
    /// owned active body is not listed twice.
    func testTheChipRowAddsTheActiveCameraOnlyWhenItIsNotOwned() throws {
        let xT3 = try body("X-T3")
        let xT50 = try body("X-T50")
        let cameras = RecipeFilterCameras(owned: [xT50], all: [xT3, xT50])
        XCTAssertEqual(cameras.chips(active: nil).map(\.id), ["X-T50"])
        XCTAssertEqual(cameras.chips(active: xT3).map(\.id), ["X-T50", "X-T3"])
        XCTAssertEqual(cameras.chips(active: xT50).map(\.id), ["X-T50"])
        XCTAssertEqual(cameras.others.map(\.id), ["X-T3"])
    }
}
