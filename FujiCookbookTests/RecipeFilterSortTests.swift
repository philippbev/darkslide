import XCTest
@testable import FujiCookbook

/// How `RecipeFilter` orders a list: the chosen field's comparator order, reading each row's sort key
/// once. For a SwiftData `Recipe` every key read is a model getter.
final class RecipeFilterSortTests: XCTestCase {

    private final class KeyReads {
        var count = 0
    }

    /// A row that counts reads of its three sort keys. The other fields are constants the sort never
    /// touches.
    private struct Row: RecipeFilterable {
        let id: Int
        let name: String
        let filmSimulation: FilmSimulation?
        let updatedAt: Date
        let reads: KeyReads

        var filterName: String {
            reads.count += 1
            return name
        }

        var filterFilmSimulation: FilmSimulation? {
            reads.count += 1
            return filmSimulation
        }

        var filterUpdatedAt: Date {
            reads.count += 1
            return updatedAt
        }

        var filterNotes: String { "" }
        var filterTags: [String] { [] }
        var filterSummary: String { "" }
        var filterIsFavorite: Bool { false }
        var filterSettings: RecipeSettings? { nil }
    }

    /// Names, film simulations and dates that repeat, so every sort has ties, with mixed case,
    /// diacritics and numbers for the name comparator.
    private func makeRows(counting reads: KeyReads) -> [Row] {
        let names = ["bravo", "Alpha", "alpha", "Ålesund", "Bravo 10", "Bravo 2", "charlie", "Émile", "zulu", "Kodak"]
        let films: [FilmSimulation?] = FilmSimulation.allCases + [nil]
        return (0..<64).map { index in
            Row(id: index,
                name: names[(index * 7) % names.count],
                filmSimulation: films[(index * 5) % films.count],
                updatedAt: Date(timeIntervalSince1970: TimeInterval((index * 11) % 9)),
                reads: reads)
        }
    }

    /// The order each field promises, written with the key read inside the comparator.
    private func referenceOrder(_ rows: [Row], by sort: RecipeSortField) -> [Int] {
        let sorted: [Row]
        switch sort {
        case .updated:
            sorted = rows.sorted { $0.updatedAt > $1.updatedAt }
        case .name:
            sorted = rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .filmSimulation:
            sorted = rows.sorted { ($0.filmSimulation?.displayName ?? "") < ($1.filmSimulation?.displayName ?? "") }
        }
        return sorted.map(\.id)
    }

    func testEachRowsSortKeyIsReadOnce() {
        let reads = KeyReads()
        let rows = makeRows(counting: reads)
        for sort in RecipeSortField.allCases {
            var filter = RecipeFilter()
            filter.sort = sort
            reads.count = 0
            _ = filter.apply(to: rows)
            XCTAssertEqual(reads.count, rows.count, "sorted by \(sort.rawValue)")
        }
    }

    func testOrderIsTheComparatorsOrderTiesIncluded() {
        let rows = makeRows(counting: KeyReads())
        for sort in RecipeSortField.allCases {
            var filter = RecipeFilter()
            filter.sort = sort
            XCTAssertEqual(filter.apply(to: rows).map(\.id), referenceOrder(rows, by: sort),
                           "sorted by \(sort.rawValue)")
        }
    }
}
