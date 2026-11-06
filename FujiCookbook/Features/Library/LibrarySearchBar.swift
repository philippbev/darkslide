import SwiftUI

/// The phone Library's bottom search + filter bar: the search field and the sort /
/// filter menu together at the bottom of the screen, where a thumb reaches them. The filter chips
/// stay at the top of the list — the same chips-top, search-bottom arrangement iOS 26 gives the
/// recipe picker sheet on its own.
///
/// A custom bar rather than a system placement, because none of those reach the bottom of a tab:
/// inside an iOS 26 tab the `.searchable` field stays under the title, a `.bottomBar` toolbar is
/// drawn behind the floating tab bar, and the tab-view bottom accessory is global to every tab.
/// The bar is hosted by `.safeAreaInset(edge: .bottom)` on the recipe list — the slot that already
/// carries the edit-mode selection bar — which is also what makes it rise with the keyboard and
/// lets the list scroll under it, as it does under the tab bar.
///
/// On iOS 26 the field and button are Liquid Glass, so they read like the picker sheet's system
/// field on the glass tab bar; below that they are the theme's paper inset over a soft paper fade.
struct LibrarySearchBar<MenuExtra: View>: View {
    @Binding var searchText: String
    @Binding var filter: RecipeFilter
    let availableFilmSimulations: [FilmSimulation]
    let cameras: RecipeFilterCameras
    @ViewBuilder var menuExtra: () -> MenuExtra

    /// The host screen's focus, not the bar's own. A screen that navigates away has to be able to
    /// drop the keyboard before it does: this field sits in the bottom safe-area inset of a
    /// `NavigationStack` root, and focus that outlives a push is restored on the pop into a layout
    /// that no longer accounts for the keyboard, leaving the bar behind it.
    @FocusState.Binding var isFocused: Bool

    init(searchText: Binding<String>,
         filter: Binding<RecipeFilter>,
         availableFilmSimulations: [FilmSimulation],
         cameras: RecipeFilterCameras,
         isFocused: FocusState<Bool>.Binding,
         @ViewBuilder menuExtra: @escaping () -> MenuExtra = { EmptyView() }) {
        _searchText = searchText
        _filter = filter
        self.availableFilmSimulations = availableFilmSimulations
        self.cameras = cameras
        _isFocused = isFocused
        self.menuExtra = menuExtra
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            // One container so the field's and the button's glass blend as a group.
            GlassEffectContainer(spacing: 10) { row }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        } else {
            row
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background {
                    // Soft edge so cards fade out under the capsule instead of scrolling straight
                    // through it. iOS 26's own scroll-edge effect does this for the glass version.
                    LinearGradient(colors: [Theme.paper.opacity(0), Theme.paper],
                                   startPoint: .top, endPoint: .bottom)
                        .padding(.top, -24)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            LibrarySearchField(searchText: $searchText, isFocused: $isFocused)
            filterMenu
        }
    }

    private var filterMenu: some View {
        RecipeFilterMenu(filter: $filter,
                         availableFilmSimulations: availableFilmSimulations,
                         cameras: cameras,
                         extraContent: menuExtra)
            .buttonStyle(RoundIconButtonStyle())
            .accessibilityLabel("Sort and filter")
    }
}

/// The bar's search field. Its own view so that a keystroke redraws the field and not the menu
/// beside it: the bar hands the text down without reading it.
private struct LibrarySearchField: View {
    @Binding var searchText: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        if #available(iOS 26.0, *) {
            // Tinted, not plain, glass: the system search field is a frosted, near-opaque capsule,
            // and untinted glass lets the cards show straight through the field.
            fieldContent
                .glassEffect(.regular.tint(Theme.card.opacity(0.7)), in: .capsule)
        } else {
            fieldContent
                .background(Theme.paper2, in: Capsule())
                .overlay { Capsule().strokeBorder(isFocused ? Theme.accent : Theme.line) }
        }
    }

    private var fieldContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.ink3)
                .accessibilityHidden(true)
            TextField("Search recipes", text: $searchText)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { isFocused = false }
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isSearchField)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        // A minimum, not a fixed height, so accessibility type sizes grow the row instead of
        // clipping it.
        .frame(minHeight: 44)
    }
}

/// A 44pt round tap target for a bare-symbol `Menu`. A button style rather than a frame on the menu
/// itself, because a `Menu` hit-tests only its label; the style wraps the label, so the whole circle
/// opens the menu. Glass on iOS 26, the theme's paper inset below it.
private struct RoundIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.title3.weight(.medium))
            // A `Menu` label inside a button style doesn't pick up the tint the toolbar gives it.
            .foregroundStyle(Theme.accent)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.6 : 1)
        if #available(iOS 26.0, *) {
            label.glassEffect(.regular.interactive(), in: .circle)
        } else {
            label
                .background(Theme.paper2, in: Circle())
                .overlay { Circle().strokeBorder(Theme.line) }
        }
    }
}
