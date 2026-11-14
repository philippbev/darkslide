import SwiftUI

/// The Library list's rows: the recipes that pass the filter and match the search text, or the
/// no-results state when none do.
///
/// Its own view so that a keystroke redraws these rows and nothing else on the screen. `LibraryView`
/// hands the search text and the filter down as bindings without reading either, so a change to
/// them never re-runs its body, or the sheets, alerts and controls it hosts.
///
/// The facets and the sort run here and the search runs in `MatchingRows`, the only view in the list
/// that reads the search text, so a keystroke searches a list that is already in order instead of
/// sorting the library again. Nothing holds a stored copy of that order: this body reads every recipe's facet
/// and sort keys, so an edit that could reorder the list re-runs it, as a new query result does.
struct LibraryRecipeRows<Row: View>: View {
    let recipes: [Recipe]
    @Binding var searchText: String
    @Binding var filter: RecipeFilter
    /// A recipe and whether it is the last row shown, which closes the archive frame.
    @ViewBuilder let row: (Recipe, _ isLast: Bool) -> Row

    var body: some View {
        MatchingRows(ordered: filter.ordered(recipes), searchText: $searchText, row: row)
    }
}

/// The ordered recipes that contain the search text, or the no-results state when none do.
private struct MatchingRows<Row: View>: View {
    let ordered: [Recipe]
    @Binding var searchText: String
    @ViewBuilder let row: (Recipe, Bool) -> Row

    var body: some View {
        let visible = RecipeFilter.rows(ordered, matching: searchText)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !visible.isEmpty {
            let last = visible.last?.persistentModelID
            ForEach(visible) { recipe in row(recipe, recipe.persistentModelID == last) }
        } else if query.isEmpty {
            // Facets alone emptied the list; there is no query to quote.
            ContentUnavailableView.search
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}
