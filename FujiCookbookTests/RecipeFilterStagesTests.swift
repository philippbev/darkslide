import XCTest
@testable import FujiCookbook

/// The Library orders its recipes once per change of recipes or filter and searches that ordered
/// list on each keystroke, while `apply` searches first and sorts what it kept. Both have to give the
/// same rows in the same order, ties included, or the Library would disagree with every other list.
final class RecipeFilterStagesTests: XCTestCase {

    private struct Row: RecipeFilterable {
        let id: Int
        let filterName: String
        let filterNotes: String
        let filterTags: [String]
        let filterSummary: String
        let filterIsFavorite: Bool
        let filterFilmSimulation: FilmSimulation?
        let filterUpdatedAt: Date
        var filterSettings: RecipeSettings? { nil }
    }

    /// Names, film simulations and dates that repeat, so every sort has ties, with mixed case,
    /// diacritics and numbers; notes, tags and summaries that only some queries reach. Few film
    /// simulations, so the film facet keeps enough rows to have an order.
    private func makeRows() -> [Row] {
        let names = ["bravo", "Alpha", "alpha", "Ålesund", "Bravo 10", "Bravo 2", "charlie", "Émile", "zulu", "Kodak"]
        let notes = ["Grey morning by the harbour.", "", "Golden hour, open shade.", "Night street, tungsten."]
        let tags = [["street"], [], ["portrait", "warm"], ["harbour"]]
        let films: [FilmSimulation?] = [.provia, .classicChrome, nil, .acros]
        return (0..<64).map { index in
            let film = films[(index / 3) % films.count]
            return Row(id: index,
                       filterName: names[(index * 7) % names.count],
                       filterNotes: notes[index % notes.count],
                       filterTags: tags[(index / 2) % tags.count],
                       filterSummary: film?.displayName ?? "",
                       filterIsFavorite: index % 3 == 0,
                       filterFilmSimulation: film,
                       filterUpdatedAt: Date(timeIntervalSince1970: TimeInterval((index * 11) % 9)))
        }
    }

    func testSearchingTheOrderedRowsMatchesApply() {
        let rows = makeRows()
        let film = FilmSimulation.classicChrome
        let queries = ["", "  ", "alpha", "ALPHA ", "e", "bravo 1", "harbour", "street", film.displayName, "zzz"]
        var nonEmptyResults = 0
        for sort in RecipeSortField.allCases {
            for favoritesOnly in [false, true] {
                for filmSimulation in [nil, film] as [FilmSimulation?] {
                    var filter = RecipeFilter()
                    filter.sort = sort
                    filter.favoritesOnly = favoritesOnly
                    filter.filmSimulation = filmSimulation
                    let ordered = filter.ordered(rows)
                    for query in queries {
                        let context = "\(sort.rawValue), favorites \(favoritesOnly), \(filmSimulation?.displayName ?? "any film"), \"\(query)\""
                        let expected = filter.apply(to: rows, matching: query).map(\.id)
                        XCTAssertEqual(RecipeFilter.rows(ordered, matching: query).map(\.id), expected, context)
                        if expected.count > 1 { nonEmptyResults += 1 }
                    }
                }
            }
        }
        // Most combinations have to keep several rows, or the comparison says nothing about order.
        XCTAssertGreaterThan(nonEmptyResults, 90)
    }
}
