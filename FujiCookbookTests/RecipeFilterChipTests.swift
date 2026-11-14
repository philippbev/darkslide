import XCTest
@testable import FujiCookbook

/// The chips every filter row shows and what a tap on each does. The rows only draw them, so a row
/// in a new design reads the same chips as the old one.
final class RecipeFilterChipTests: XCTestCase {

    private let registry = CameraModelRegistry.shared

    private func body(_ id: String) throws -> CameraModel { try XCTUnwrap(registry.model(withID: id)) }

    func testChipsRunAllFavoritesCamerasThenFilmSimulations() throws {
        let x100vi = try body("X100VI")
        let cameras = RecipeFilterCameras(owned: [x100vi], all: [x100vi])
        let chips = RecipeFilter().chips(availableFilmSimulations: [.classicChrome, .acros], cameras: cameras)
        XCTAssertEqual(chips.map(\.kind), [.all, .favorites, .camera(x100vi),
                                           .filmSimulation(.classicChrome), .filmSimulation(.acros)])
        XCTAssertEqual(chips.map(\.label), ["All", "Favorites", "X100VI",
                                            FilmSimulation.classicChrome.displayName, FilmSimulation.acros.displayName])
        XCTAssertEqual(chips.filter(\.isSelected).map(\.kind), [.all])
    }

    func testAChipTurnsItsFacetOnAndASecondTapTurnsItOff() throws {
        let x100vi = try body("X100VI")
        var filter = RecipeFilter()

        filter.toggle(.filmSimulation(.classicChrome))
        XCTAssertEqual(filter.filmSimulation, .classicChrome)
        filter.toggle(.filmSimulation(.classicChrome))
        XCTAssertNil(filter.filmSimulation)

        filter.toggle(.camera(x100vi))
        XCTAssertEqual(filter.camera, x100vi)
        filter.toggle(.camera(x100vi))
        XCTAssertNil(filter.camera)

        filter.toggle(.favorites)
        XCTAssertTrue(filter.favoritesOnly)
        filter.toggle(.favorites)
        XCTAssertFalse(filter.favoritesOnly)
    }

    func testAllClearsEveryFacetButKeepsTheSort() throws {
        var filter = RecipeFilter()
        filter.sort = .updated
        filter.favoritesOnly = true
        filter.filmSimulation = .acros
        filter.camera = try body("X100VI")

        filter.toggle(.all)

        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.sort, .updated)
    }

    func testOnlyTheChipsInUseAreSelected() {
        var filter = RecipeFilter()
        filter.favoritesOnly = true
        filter.filmSimulation = .acros
        let chips = filter.chips(availableFilmSimulations: [.classicChrome, .acros], cameras: .none)
        XCTAssertEqual(chips.filter(\.isSelected).map(\.kind), [.favorites, .filmSimulation(.acros)])
    }

    func testAPickedCameraThatIsNotOwnedStillGetsASelectedChip() throws {
        let x100vi = try body("X100VI"), xt5 = try body("X-T5")
        var filter = RecipeFilter()
        filter.camera = xt5
        let chips = filter.chips(availableFilmSimulations: [],
                                 cameras: RecipeFilterCameras(owned: [x100vi], all: [x100vi, xt5]))
        XCTAssertEqual(chips.map(\.kind), [.all, .favorites, .camera(x100vi), .camera(xt5)])
        XCTAssertEqual(chips.filter(\.isSelected).map(\.kind), [.camera(xt5)])
    }
}
