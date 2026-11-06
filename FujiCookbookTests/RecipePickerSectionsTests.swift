import XCTest
@testable import FujiCookbook

/// The picker's two sections: Library rows follow the chosen sort, camera slots stay in C1…Cx order.
final class RecipePickerSectionsTests: XCTestCase {

    private func slot(_ index: Int, _ name: String, _ sim: FilmSimulation) -> RecipeChoice {
        RecipeChoice(ref: .slot(index), name: name, filmSimulation: sim, summary: sim.displayName,
                     isFavorite: false, badge: "C\(index)", notes: "", tags: [],
                     updatedAt: Date(timeIntervalSince1970: TimeInterval(index)))
    }

    private func library(_ name: String, updated: TimeInterval) -> RecipeChoice {
        RecipeChoice(ref: .library(UUID()), name: name, filmSimulation: .provia, summary: "",
                     isFavorite: false, badge: nil, notes: "", tags: [],
                     updatedAt: Date(timeIntervalSince1970: updated))
    }

    /// Slot names, film simulations and dates all run against slot order, so any sort would reverse
    /// the slots if they went through it.
    private lazy var choices: [RecipeChoice] = [
        slot(1, "Zebra", .velvia),
        slot(2, "Mango", .classicChrome),
        slot(3, "Apple", .acros),
        library("Alpha", updated: 1),
        library("Bravo", updated: 2),
    ]

    func testSlotsKeepCameraOrderUnderEverySort() {
        for sort in RecipeSortField.allCases {
            var filter = RecipeFilter()
            filter.sort = sort
            XCTAssertEqual(filter.apply(to: choices).pickerSections.slots.map(\.badge),
                           ["C1", "C2", "C3"], "sorted by \(sort.rawValue)")
        }
    }

    func testLibraryStillFollowsTheChosenSort() {
        var filter = RecipeFilter()
        filter.sort = .name
        XCTAssertEqual(filter.apply(to: choices).pickerSections.library.map(\.name), ["Alpha", "Bravo"])
        filter.sort = .updated
        XCTAssertEqual(filter.apply(to: choices).pickerSections.library.map(\.name), ["Bravo", "Alpha"])
    }

    func testSearchStillNarrowsTheSlots() {
        let filter = RecipeFilter()
        XCTAssertEqual(filter.apply(to: choices, matching: "mango").pickerSections.slots.map(\.badge), ["C2"])
    }

    /// Slots handed over in reverse camera order and library rows that tie with each other and with
    /// the slots on every sort key, with mixed case, diacritics and numbers. Two slots have no
    /// settings, which the camera facet leaves alone; Classic Neg is a film the X-T3 lacks.
    private func mixedChoices() -> [RecipeChoice] {
        let names = ["bravo", "Alpha", "alpha", "Ålesund", "Bravo 10", "Bravo 2", "charlie", "Émile"]
        let notes = ["Grey morning by the harbour.", "", "Golden hour, open shade."]
        let tags = [["street"], [], ["harbour"]]
        let films: [FilmSimulation?] = [.provia, .classicChrome, .classicNeg, nil]
        let slotCount = 6
        return (0..<36).map { index in
            let film = films[(index / 2) % films.count]
            let isSlot = index < slotCount
            let undecoded = isSlot && index % 3 == 1
            return RecipeChoice(ref: isSlot ? .slot(slotCount - index) : .library(UUID()),
                                name: names[(index * 5) % names.count],
                                filmSimulation: undecoded ? nil : film,
                                summary: film?.displayName ?? "",
                                isFavorite: index % 3 == 0,
                                badge: isSlot ? "C\(slotCount - index)" : nil,
                                notes: notes[index % notes.count],
                                tags: tags[(index / 3) % tags.count],
                                updatedAt: Date(timeIntervalSince1970: TimeInterval((index * 11) % 5)),
                                settings: undecoded ? nil : RecipeSettings(filmSimulation: film))
        }
    }

    /// The sheet applies the facets and the sort once and searches that ordered list on each
    /// keystroke. Its sections have to be the ones `apply` gives, slots in camera order and library
    /// rows in the sort, ties included.
    func testSearchingTheOrderedChoicesGivesTheSectionsApplyGives() throws {
        let choices = mixedChoices()
        let film = FilmSimulation.classicChrome
        let camera = try XCTUnwrap(CameraModelRegistry.shared.model(withID: "X-T3"))
        let queries = ["", "  ", "alpha", "ALPHA ", "e", "bravo 1", "harbour", "street", film.displayName, "zzz"]
        var bothSectionsCompared = 0
        for sort in RecipeSortField.allCases {
            for favoritesOnly in [false, true] {
                for filmSimulation in [nil, film] as [FilmSimulation?] {
                    for cameraFacet in [nil, camera] as [CameraModel?] {
                        var filter = RecipeFilter()
                        filter.sort = sort
                        filter.favoritesOnly = favoritesOnly
                        filter.filmSimulation = filmSimulation
                        filter.camera = cameraFacet
                        let ordered = filter.ordered(choices)
                        for query in queries {
                            let context = "\(sort.rawValue), favorites \(favoritesOnly), \(filmSimulation?.displayName ?? "any film"), \(cameraFacet?.id ?? "any camera"), \"\(query)\""
                            let expected = filter.apply(to: choices, matching: query).pickerSections
                            let sections = RecipeFilter.rows(ordered, matching: query).pickerSections
                            XCTAssertEqual(sections.slots.map(\.ref), expected.slots.map(\.ref), context)
                            XCTAssertEqual(sections.library.map(\.ref), expected.library.map(\.ref), context)
                            if expected.slots.count > 1 && expected.library.count > 1 { bothSectionsCompared += 1 }
                        }
                    }
                }
            }
        }
        // Enough combinations have to keep several rows in both sections, or the comparison says
        // nothing about order.
        XCTAssertGreaterThan(bothSectionsCompared, 80)
    }
}
