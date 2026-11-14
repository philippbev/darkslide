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

    // MARK: One key at a time

    func testAKeySetsItsFacetAlone() throws {
        let x100vi = try body("X100VI")
        var filter = RecipeFilter()
        filter.toggle(.favorites)
        filter.toggle(.filmSimulation(.acros))
        XCTAssertFalse(filter.favoritesOnly, "the simulation key replaced favorites")
        XCTAssertEqual(filter.filmSimulation, .acros)

        filter.toggle(.camera(x100vi))
        XCTAssertNil(filter.filmSimulation)
        XCTAssertEqual(filter.camera, x100vi)
        let lit = filter.chips(availableFilmSimulations: [.acros], cameras: RecipeFilterCameras(owned: [x100vi], all: [x100vi]))
            .filter(\.isSelected)
        XCTAssertEqual(lit.map(\.kind), [.camera(x100vi)])
    }

    func testTappingTheLitKeyOfACombinationFromTheMenuLeavesOnlyIt() {
        // The menu can combine favorites with a simulation; a key tap then narrows to that key.
        var filter = RecipeFilter()
        filter.favoritesOnly = true
        filter.filmSimulation = .acros
        filter.toggle(.filmSimulation(.acros))
        XCTAssertFalse(filter.favoritesOnly)
        XCTAssertEqual(filter.filmSimulation, .acros)
    }

    // MARK: Chapters

    private struct Row: RecipeFilterable {
        let filterName: String
        var filterRecipeUUID: UUID?
        var filterNotes: String { "" }
        var filterTags: [String] { [] }
        var filterSummary: String { "" }
        var filterIsFavorite: Bool { false }
        var filterFilmSimulation: FilmSimulation? { nil }
        var filterUpdatedAt: Date { .distantPast }
        var filterSettings: RecipeSettings? { nil }
    }

    func testAChapterKeyShowsOnlyThatChaptersRecipes() {
        let a = UUID(), b = UUID(), c = UUID()
        let rows = [Row(filterName: "A", filterRecipeUUID: a), Row(filterName: "B", filterRecipeUUID: b),
                    Row(filterName: "C", filterRecipeUUID: c), Row(filterName: "Slot C4", filterRecipeUUID: nil)]
        var filter = RecipeFilter()
        filter.toggle(.chapter(RecipeChapterFacet(id: UUID(), name: "Street", recipeUUIDs: [a, c])))
        XCTAssertEqual(filter.apply(to: rows).map(\.filterName), ["A", "C"], "a camera slot is in no chapter")
        XCTAssertTrue(filter.isActive)
    }

    func testChaptersFollowTheFiltersAfterADivider() {
        let street = RecipeChapterFacet(id: UUID(), name: "Street", recipeUUIDs: [])
        let travel = RecipeChapterFacet(id: UUID(), name: "Travel", recipeUUIDs: [])
        var filter = RecipeFilter()
        filter.toggle(.chapter(travel))
        let chips = filter.chips(availableFilmSimulations: [.acros], cameras: .none, chapters: [street, travel])
        XCTAssertEqual(chips.map(\.kind), [.all, .favorites, .filmSimulation(.acros), .chapter(street), .chapter(travel)])
        XCTAssertEqual(chips.map(\.startsGroup), [false, false, false, true, false])
        XCTAssertEqual(chips.filter(\.isSelected).map(\.label), ["Travel"])
    }

    func testTheChapterKeyGoesOffAgainAndAllClearsIt() {
        let street = RecipeChapterFacet(id: UUID(), name: "Street", recipeUUIDs: [])
        var filter = RecipeFilter()
        filter.toggle(.chapter(street))
        filter.toggle(.chapter(street))
        XCTAssertNil(filter.chapter)
        filter.toggle(.chapter(street))
        filter.toggle(.all)
        XCTAssertNil(filter.chapter)
    }

    func testAnEditedChapterFiltersByItsNewRecipesAndADeletedOneFallsBackToAll() {
        let id = UUID(), added = UUID()
        var filter = RecipeFilter()
        filter.toggle(.chapter(RecipeChapterFacet(id: id, name: "Street", recipeUUIDs: [])))

        filter.refreshChapter(from: [RecipeChapterFacet(id: id, name: "Street Night", recipeUUIDs: [added])])
        XCTAssertEqual(filter.chapter?.recipeUUIDs, [added])
        XCTAssertEqual(filter.chapter?.name, "Street Night")

        filter.refreshChapter(from: [])
        XCTAssertNil(filter.chapter)
        XCTAssertFalse(filter.isActive)
    }

    func testAChapterKeyKeepsItsIdentityWhenItsRecipesChange() {
        let id = UUID()
        let before = RecipeFilterChip(kind: .chapter(RecipeChapterFacet(id: id, name: "Street", recipeUUIDs: [])),
                                      label: "Street", isSelected: false)
        let after = RecipeFilterChip(kind: .chapter(RecipeChapterFacet(id: id, name: "Street", recipeUUIDs: [UUID()])),
                                     label: "Street", isSelected: false)
        XCTAssertEqual(before.id, after.id)
    }
}
