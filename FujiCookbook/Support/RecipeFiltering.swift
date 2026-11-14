import SwiftUI

// The app's one search / filter / sort pipeline for recipe lists, and the two controls that drive
// it. The Library and `RecipePickerSheet` share it: with a library in the dozens, a "just show
// them all" list is not usable. It works over `RecipeFilterable` rather than `Recipe` so the
// picker can run the same search over a mixed list of library recipes and programmed camera slots.

/// How a filtered list is ordered.
enum RecipeSortField: String, CaseIterable, Identifiable {
    case updated = "Last Modified"
    case name = "Name"
    case filmSimulation = "Film Simulation"

    var id: String { rawValue }
}

/// What `RecipeFilter` needs to know about a row. Deliberately not `Recipe`: a camera slot is
/// filterable too, and the picker shouldn't have to care which it's looking at.
protocol RecipeFilterable {
    var filterName: String { get }
    var filterNotes: String { get }
    var filterTags: [String] { get }
    var filterSummary: String { get }
    var filterIsFavorite: Bool { get }
    var filterFilmSimulation: FilmSimulation? { get }
    var filterUpdatedAt: Date { get }
    /// What the camera facet judges. Nil for a row with nothing to judge — a camera slot the
    /// reader couldn't decode — which the facet then leaves alone.
    var filterSettings: RecipeSettings? { get }
    /// The library recipe behind the row, for the chapter facet. Nil for a row that isn't one, such
    /// as a camera slot, which the chapter facet hides.
    var filterRecipeUUID: UUID? { get }
}

extension RecipeFilterable {
    var filterRecipeUUID: UUID? { nil }
}

extension Recipe: RecipeFilterable {
    var filterName: String { name }
    var filterNotes: String { notes }
    var filterTags: [String] { tags }
    var filterSummary: String { summary }
    var filterIsFavorite: Bool { isFavorite }
    var filterFilmSimulation: FilmSimulation? { settings.filmSimulation }
    var filterUpdatedAt: Date { updatedAt }
    var filterSettings: RecipeSettings? { settings }
    var filterRecipeUUID: UUID? { uuid }
}

/// A chapter as a filter: its recipes, held as a value so the filter needs no store. The Library
/// refreshes it when the chapter changes (`LibraryFilterKeys`).
struct RecipeChapterFacet: Hashable, Identifiable {
    let id: UUID
    let name: String
    let recipeUUIDs: Set<UUID>

    init(id: UUID, name: String, recipeUUIDs: Set<UUID>) {
        self.id = id
        self.name = name
        self.recipeUUIDs = recipeUUIDs
    }

    init(_ chapter: Chapter) {
        self.init(id: chapter.uuid, name: chapter.name, recipeUUIDs: Set(chapter.recipeUUIDs))
    }
}

/// Facets and sort order for one recipe list: what the chip row and the menu set.
///
/// The search text is not part of it: a screen keeps that in state of its own and hands it to
/// `apply(to:matching:)`, or to `rows(_:matching:)` over a list it ordered with `ordered(_:)`. A
/// keystroke then changes nothing the controls read, so it needn't redraw them.
struct RecipeFilter: Equatable {
    var favoritesOnly = false
    var filmSimulation: FilmSimulation?
    /// Only recipes this body can run. A `CameraModel` rather than its id: it is Hashable by id, so
    /// the filter stays a value with no registry lookup inside it.
    var camera: CameraModel?
    /// Only the recipes in this chapter.
    var chapter: RecipeChapterFacet?
    var sort: RecipeSortField = .name

    /// True when a facet is narrowing the list. Search text deliberately doesn't count — the search
    /// field shows its own state, so folding it in here would light up the filter icon twice.
    var isActive: Bool { favoritesOnly || filmSimulation != nil || camera != nil || chapter != nil }

    mutating func clearFacets() {
        favoritesOnly = false
        filmSimulation = nil
        camera = nil
        chapter = nil
    }

    /// The rows that pass every facet and contain `searchText`, in the sort order. Blank search text
    /// matches every row.
    ///
    /// Searches before it sorts, so a query that narrows the list leaves less to sort. A screen that
    /// redraws on every keystroke can instead keep `ordered(_:)` and search that with
    /// `rows(_:matching:)`. Both give the same rows in the same order, ties included: the sort is
    /// stable, and filtering a sorted list keeps its order.
    func apply<T: RecipeFilterable>(to items: [T], matching searchText: String = "") -> [T] {
        inSortOrder(Self.rows(passingFacets(items), matching: searchText))
    }

    /// The rows that pass every facet, in the sort order, whatever the search text.
    func ordered<T: RecipeFilterable>(_ items: [T]) -> [T] {
        inSortOrder(passingFacets(items))
    }

    /// The rows that contain `searchText`, in the order given. Blank search text matches every row.
    static func rows<T: RecipeFilterable>(_ items: [T], matching searchText: String) -> [T] {
        // `localizedStandardContains` rather than `lowercased().contains`: the latter allocates a
        // case-folded copy of every recipe's full note text on each keystroke, which is enough to
        // stutter the search field on a large library. This also matches diacritics the way the
        // rest of the system's search fields do.
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.filterName.localizedStandardContains(query)
            || $0.filterNotes.localizedStandardContains(query)
            || $0.filterSummary.localizedStandardContains(query)
            || $0.filterTags.contains { $0.localizedStandardContains(query) }
        }
    }

    private func passingFacets<T: RecipeFilterable>(_ items: [T]) -> [T] {
        var result = items
        if favoritesOnly { result = result.filter(\.filterIsFavorite) }
        if let filmSimulation { result = result.filter { $0.filterFilmSimulation == filmSimulation } }
        if let chapter {
            result = result.filter { item in item.filterRecipeUUID.map(chapter.recipeUUIDs.contains) ?? false }
        }
        // A body that can't run the recipe's film simulation hides it. One that needs a change
        // keeps it — the Works With card says what the change is — and so does a row the filter
        // can't judge.
        if let camera {
            result = result.filter { item in
                guard let settings = item.filterSettings else { return true }
                return RecipeCameraFit(settings, on: camera).verdict != .notAvailable
            }
        }
        return result
    }

    private func inSortOrder<T: RecipeFilterable>(_ items: [T]) -> [T] {
        switch sort {
        case .updated:
            return items.sorted(on: \.filterUpdatedAt, by: >)
        case .name:
            return items.sorted(on: \.filterName) { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .filmSimulation:
            return items.sorted(on: { $0.filterFilmSimulation?.displayName ?? "" }, by: <)
        }
    }
}

private extension Array {
    /// Sorted by `key`, read once per element rather than twice per comparison. Same comparisons, so
    /// the same order as sorting with the key read inside the comparator, ties included.
    ///
    /// For a SwiftData `Recipe` every read is a model getter, and a key read inside the comparator
    /// costs two per comparison: 250 recipes by name take about 8.7 ms with the key read in the
    /// comparator and 3.5 ms read here (iPhone 16 Pro Simulator, 2026-10-19).
    func sorted<Key>(on key: (Element) -> Key, by areInIncreasingOrder: (Key, Key) -> Bool) -> [Element] {
        map { (element: $0, key: key($0)) }
            .sorted { areInIncreasingOrder($0.key, $1.key) }
            .map(\.element)
    }
}

extension Collection where Element: RecipeFilterable {
    /// The film simulations actually present, for building the chip row and the filter menu. A facet
    /// for a simulation nothing uses is just a dead end.
    var availableFilmSimulations: [FilmSimulation] {
        Set(compactMap(\.filterFilmSimulation)).sorted { $0.displayName < $1.displayName }
    }
}

/// The bodies a filter control can offer: the user's own (Settings ▸ My Cameras), and every
/// registry body for the menu. Parameters that always travel together, so one value.
struct RecipeFilterCameras: Equatable {
    let owned: [CameraModel]
    let all: [CameraModel]

    static let none = RecipeFilterCameras(owned: [], all: [])

    /// The chip row's bodies: the owned ones, plus the active facet when it isn't one of them, so a
    /// body picked from the menu — or dropped from My Cameras while selected — keeps a visible,
    /// selected chip. Choosing a chip never makes a body owned.
    func chips(active: CameraModel?) -> [CameraModel] {
        guard let active, !owned.contains(active) else { return owned }
        return owned + [active]
    }

    /// The registry bodies that are not owned, for the menu's second group.
    var others: [CameraModel] { all.filter { !owned.contains($0) } }
}

// MARK: - Controls

/// Horizontal filter chips — All · N, Favorites, the user's cameras, then one chip per film
/// simulation present.
struct RecipeFilterChipRow: View {
    @Binding var filter: RecipeFilter
    let availableFilmSimulations: [FilmSimulation]
    let cameras: RecipeFilterCameras
    let totalCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filter.chips(availableFilmSimulations: availableFilmSimulations, cameras: cameras)) { chip in
                    FilterChip(label: label(for: chip), selected: chip.isSelected) {
                        filter.toggle(chip.kind)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// This row's own wording; the design-system row in the Library says the plain label.
    private func label(for chip: RecipeFilterChip) -> String {
        switch chip.kind {
        case .all: return "All · \(totalCount)"
        case .favorites: return "★ Favorites"
        case .camera, .filmSimulation, .chapter: return chip.label
        }
    }
}

/// One chip of a filter row: what it narrows to, what it says, and whether it is on.
struct RecipeFilterChip: Identifiable {
    enum Kind: Hashable {
        case all, favorites
        case camera(CameraModel)
        case filmSimulation(FilmSimulation)
        case chapter(RecipeChapterFacet)
    }

    let kind: Kind
    let label: String
    let isSelected: Bool
    /// The first chip of a new group (the chapters), which a row sets apart with a divider.
    var startsGroup = false

    /// A chapter's chip keeps its identity when the chapter's recipes change.
    var id: String {
        switch kind {
        case .all: return "all"
        case .favorites: return "favorites"
        case .camera(let model): return "camera:\(model.id)"
        case .filmSimulation(let sim): return "sim:\(sim.rawValue)"
        case .chapter(let chapter): return "chapter:\(chapter.id)"
        }
    }
}

extension RecipeFilter {
    /// The chips a filter row shows, in order: All, Favorites, the user's cameras, one per film
    /// simulation present, then the chapters, the first of which starts a group.
    func chips(availableFilmSimulations: [FilmSimulation], cameras: RecipeFilterCameras,
               chapters: [RecipeChapterFacet] = []) -> [RecipeFilterChip] {
        [RecipeFilterChip(kind: .all, label: "All", isSelected: !isActive),
         RecipeFilterChip(kind: .favorites, label: "Favorites", isSelected: favoritesOnly)]
            + cameras.chips(active: camera).map {
                RecipeFilterChip(kind: .camera($0), label: $0.id, isSelected: camera == $0)
            }
            + availableFilmSimulations.map {
                RecipeFilterChip(kind: .filmSimulation($0), label: $0.displayName, isSelected: filmSimulation == $0)
            }
            + chapters.enumerated().map { index, facet in
                RecipeFilterChip(kind: .chapter(facet), label: facet.name, isSelected: chapter?.id == facet.id,
                                 startsGroup: index == 0)
            }
    }

    /// A tap on a chip. The row works like a set of radio keys, one lit at a time: a chip sets its
    /// facet alone, clearing the others; a tap on the lit chip, or on All, clears them all.
    ///
    /// The filter menu can still combine facets (favorites of one simulation, say); the row then
    /// lights each of them.
    mutating func toggle(_ kind: RecipeFilterChip.Kind) {
        let wasOnlyThis: Bool
        switch kind {
        case .all: wasOnlyThis = false
        case .favorites: wasOnlyThis = favoritesOnly && filmSimulation == nil && camera == nil && chapter == nil
        case .camera(let model): wasOnlyThis = camera == model && !favoritesOnly && filmSimulation == nil && chapter == nil
        case .filmSimulation(let sim): wasOnlyThis = filmSimulation == sim && !favoritesOnly && camera == nil && chapter == nil
        case .chapter(let facet): wasOnlyThis = chapter?.id == facet.id && !favoritesOnly && camera == nil && filmSimulation == nil
        }
        clearFacets()
        guard !wasOnlyThis else { return }
        switch kind {
        case .all: break
        case .favorites: favoritesOnly = true
        case .camera(let model): camera = model
        case .filmSimulation(let sim): filmSimulation = sim
        case .chapter(let facet): chapter = facet
        }
    }

    /// Keeps the chapter facet in step with the chapters as they are now: a chapter whose recipes
    /// or name changed is refreshed, a deleted one is dropped, which leaves the list on All.
    mutating func refreshChapter(from chapters: [RecipeChapterFacet]) {
        guard let current = chapter else { return }
        chapter = chapters.first { $0.id == current.id }
    }
}

/// The sort + filter menu — in the toolbar, or beside the search field in the phone Library's bottom
/// bar. `extraContent` lets a screen append its own sections (the Library hangs "Export All" off
/// the same button) without a second menu beside it.
struct RecipeFilterMenu<Extra: View>: View {
    @Binding var filter: RecipeFilter
    let availableFilmSimulations: [FilmSimulation]
    let cameras: RecipeFilterCameras
    @ViewBuilder var extraContent: () -> Extra

    init(filter: Binding<RecipeFilter>,
         availableFilmSimulations: [FilmSimulation],
         cameras: RecipeFilterCameras,
         @ViewBuilder extraContent: @escaping () -> Extra = { EmptyView() }) {
        _filter = filter
        self.availableFilmSimulations = availableFilmSimulations
        self.cameras = cameras
        self.extraContent = extraContent
    }

    var body: some View {
        Menu {
            Section("Sort By") {
                Picker("Sort", selection: $filter.sort) {
                    ForEach(RecipeSortField.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Filter") {
                Toggle("Favorites Only", isOn: $filter.favoritesOnly)
                // Submenus rather than pickers beside the toggle: a picker in this menu renders its
                // rows inline, and a library's simulations or the registry's bodies would run the
                // menu past the screen. Each label shows the current choice instead.
                if availableFilmSimulations.count > 1 {
                    Menu {
                        Picker("Film Simulation", selection: $filter.filmSimulation) {
                            Text("All Film Simulations").tag(FilmSimulation?.none)
                            ForEach(availableFilmSimulations) { sim in
                                Text(sim.displayName).tag(FilmSimulation?.some(sim))
                            }
                        }
                    } label: {
                        Text("Film Simulation")
                        Text(filter.filmSimulation?.displayName ?? "All Film Simulations")
                    }
                }
                Menu {
                    Picker("Works On", selection: $filter.camera) {
                        Text("Any Camera").tag(CameraModel?.none)
                        if !cameras.owned.isEmpty {
                            Section("My Cameras") {
                                ForEach(cameras.owned) { model in
                                    Text(model.id).tag(CameraModel?.some(model))
                                }
                            }
                        }
                        Section(cameras.owned.isEmpty ? "" : "Other Cameras") {
                            ForEach(cameras.others) { model in
                                Text(model.id).tag(CameraModel?.some(model))
                            }
                        }
                    }
                    // What the facet keeps: a body that needs a change still runs the recipe, and
                    // the Works With card says what the change is.
                    Text("Includes recipes that need changes")
                } label: {
                    Text("Works On")
                    Text(filter.camera?.id ?? "Any Camera")
                }
            }
            extraContent()
        } label: {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill"
                                              : "line.3.horizontal.decrease.circle")
        }
    }
}
