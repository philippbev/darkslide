import SwiftUI

/// Where a chosen recipe came from: the Library, or a slot programmed on the connected camera.
///
/// Named without a `Kitchen` prefix because it is not Kitchen-only — it is the identity the shared
/// picker returns. Resolving one against the camera *is* Kitchen-specific and lives in
/// `KitchenShared.swift`.
enum RecipeRef: Hashable {
    case library(UUID)
    case slot(Int)
}

/// One row in the picker: display text plus the fields `RecipeFilter` searches. Deliberately a flat
/// value rather than a `Recipe` or a `CameraSlot`, so the picker needs to know about neither
/// SwiftData nor the camera session.
struct RecipeChoice: Identifiable, Hashable {
    let ref: RecipeRef
    let name: String
    let filmSimulation: FilmSimulation?
    let summary: String
    let isFavorite: Bool
    /// Trailing tag — the camera slot label ("C2") or the model a recipe was authored for.
    let badge: String?
    let notes: String
    let tags: [String]
    let updatedAt: Date
    /// What the camera facet judges; nil for a slot the reader couldn't decode, which the facet
    /// then leaves alone. Last, and defaulted, so the memberwise callers need not name it.
    var settings: RecipeSettings? = nil

    var id: RecipeRef { ref }

    /// The camera slot number (1 … slotCount), or nil for a Library recipe.
    var slotIndex: Int? {
        if case .slot(let index) = ref { return index }
        return nil
    }

    var isSlot: Bool { slotIndex != nil }
}

extension Array where Element == RecipeChoice {
    /// A filtered list split into the picker's "On Camera" and "Library" sections. Library rows keep
    /// the filter's sort; slots always run C1…Cx whatever the sort, because that order is the
    /// camera's own and matches the body's menu.
    var pickerSections: (slots: [RecipeChoice], library: [RecipeChoice]) {
        let slots = filter(\.isSlot).sorted { ($0.slotIndex ?? 0) < ($1.slotIndex ?? 0) }
        return (slots, filter { !$0.isSlot })
    }
}

extension RecipeChoice: RecipeFilterable {
    var filterName: String { name }
    var filterNotes: String { notes }
    var filterTags: [String] { tags }
    var filterSummary: String { summary }
    var filterIsFavorite: Bool { isFavorite }
    var filterFilmSimulation: FilmSimulation? { filmSimulation }
    var filterUpdatedAt: Date { updatedAt }
    var filterSettings: RecipeSettings? { settings }
    var filterRecipeUUID: UUID? {
        if case .library(let uuid) = ref { return uuid }
        return nil
    }
}

extension RecipeChoice {
    init(_ recipe: Recipe) {
        self.init(ref: .library(recipe.uuid),
                  name: recipe.name,
                  filmSimulation: recipe.settings.filmSimulation,
                  summary: recipe.summary,
                  isFavorite: recipe.isFavorite,
                  badge: recipe.authoredForModel?.id,
                  notes: recipe.notes,
                  tags: recipe.tags,
                  updatedAt: recipe.updatedAt,
                  settings: recipe.settings)
    }
}

// MARK: - The sheet

/// The app's one recipe-picking sheet.
///
/// Serves Develop, Test Kitchen, Compare With and the Chapters editor, in single- or capped-multi-select, over a mixed list of library recipes and programmed
/// camera slots. It filters: a flat menu of every name stops being usable once a library runs to
/// dozens.
struct RecipePickerSheet: View {
    enum Mode: Equatable {
        case single
        /// Multi-select capped at `limit`, preserving the order rows were ticked in.
        case multiple(limit: Int)
    }

    let title: String
    let choices: [RecipeChoice]
    var mode: Mode = .single
    var initialSelection: [RecipeRef] = []
    /// Shown under the empty state when there is nothing at all to pick from.
    var emptyMessage: String = "Add recipes to your library first."
    let onDone: ([RecipeRef]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(OwnedCameras.self) private var ownedCameras
    @State private var filter = RecipeFilter()
    @State private var searchText = ""

    /// The user's cameras for the chips, and every body for the menu — the Library's own set.
    private var filterCameras: RecipeFilterCameras {
        RecipeFilterCameras(owned: ownedCameras.models, all: ownedCameras.selectable)
    }
    @State private var selection: [RecipeRef] = []

    private var limit: Int? {
        if case .multiple(let limit) = mode { return limit }
        return nil
    }

    private var isFull: Bool {
        guard let limit else { return false }
        return selection.count >= limit
    }

    var body: some View {
        NavigationStack {
            // The facets, the sort and the chip row's inputs run here, once per change of the
            // choices or the filter. `MatchingChoices` alone reads the search text and hosts its
            // field, so a keystroke searches this ordered list and re-runs that view, not this one.
            let chips = RecipeFilterChipRow(filter: $filter,
                                            availableFilmSimulations: choices.availableFilmSimulations,
                                            cameras: filterCameras,
                                            totalCount: choices.count)
            MatchingChoices(ordered: filter.ordered(choices), searchText: $searchText) { visible, query in
                List {
                    chips
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))

                    let (slots, library) = visible.pickerSections
                    if slots.isEmpty {
                        ForEach(library) { row($0) }
                    } else {
                        Section("On Camera") { ForEach(slots) { row($0) } }
                        if !library.isEmpty {
                            Section("Library") { ForEach(library) { row($0) } }
                        }
                    }
                }
                .overlay {
                    if choices.isEmpty {
                        ContentUnavailableView("No Recipes", systemImage: "tray",
                                               description: Text(emptyMessage))
                    } else if visible.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .listStyle(.plain)
            .paperBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .onAppear { if selection.isEmpty { selection = initialSelection } }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
            RecipeFilterMenu(filter: $filter,
                             availableFilmSimulations: choices.availableFilmSimulations,
                             cameras: filterCameras)
        }
        if let limit {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(title).font(.headline)
                    Text("\(selection.count) of \(limit)")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onDone(selection)
                    dismiss()
                }
            }
        }
    }

    /// One compact row — short enough that a dozen fit a phone screen, which is the whole point of
    /// the sheet. The full `RecipeRow` card is right for browsing the Library and too tall here.
    private func row(_ choice: RecipeChoice) -> some View {
        let selected = selection.contains(choice.ref)
        // At the cap, unselected rows go dim rather than disappearing, so the list doesn't shuffle
        // under the user mid-choice.
        let blocked = !selected && isFull
        return Button {
            tap(choice)
        } label: {
            HStack(spacing: 10) {
                FilmSwatch(simulation: choice.filmSimulation, size: 12)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(choice.name)
                            .font(DSFont.headline)
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                        if choice.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(DSColor.textPrimary)
                        }
                    }
                    Text(choice.summary)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let badge = choice.badge { BadgeTag(text: badge) }
                Image(systemName: selectionSymbol(selected: selected))
                    .foregroundStyle(selected ? DSColor.signalText : DSColor.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .opacity(blocked ? 0.4 : 1)
    }

    private func selectionSymbol(selected: Bool) -> String {
        switch mode {
        case .single: return selected ? "checkmark" : "chevron.right"
        case .multiple: return selected ? "checkmark.circle.fill" : "circle"
        }
    }

    private func tap(_ choice: RecipeChoice) {
        switch mode {
        case .single:
            onDone([choice.ref])
            dismiss()
        case .multiple:
            if let index = selection.firstIndex(of: choice.ref) {
                selection.remove(at: index)
            } else if !isFull {
                selection.append(choice.ref)
            }
        }
    }
}

/// The search field, and the ordered choices that contain its text, handed with the query to
/// `content`, which lays them out.
///
/// Its own view so that a keystroke re-runs this body and not the sheet's: the sheet applies the
/// facets and the sort to every choice and builds the toolbar, and none of that depends on the
/// search text. The field is applied here as well: the view that applies `.searchable` re-runs
/// whenever its text changes (iOS 26.5), so applied by the sheet it would re-run the sheet on every
/// keystroke. Searching a list that is already in order gives the rows `apply(to:matching:)` gives,
/// in the same order, ties included.
private struct MatchingChoices<Content: View>: View {
    let ordered: [RecipeChoice]
    @Binding var searchText: String
    @ViewBuilder let content: (_ visible: [RecipeChoice], _ query: String) -> Content

    var body: some View {
        content(RecipeFilter.rows(ordered, matching: searchText), searchText)
            .searchable(text: $searchText, prompt: "Search recipes")
    }
}
