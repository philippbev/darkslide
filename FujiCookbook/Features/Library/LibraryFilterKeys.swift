import SwiftUI
import SwiftData

/// The Library's filters and chapters as one row of text keys with an LED: All, Favorites, the
/// user's cameras and the film simulations, then after a divider the chapters. One key is lit at a
/// time (`RecipeFilter.toggle`). The recipe picker keeps `RecipeFilterChipRow`, without chapters,
/// until it moves to the design system.
struct LibraryFilterKeys: View {
    @Binding var filter: RecipeFilter
    let availableFilmSimulations: [FilmSimulation]
    let cameras: RecipeFilterCameras

    /// By name, so the keys stay put when a chapter is edited.
    @Query(sort: \Chapter.name) private var chapters: [Chapter]

    private var chapterFacets: [RecipeChapterFacet] { chapters.map(RecipeChapterFacet.init) }

    var body: some View {
        let facets = chapterFacets
        DSKeyRow {
            ForEach(filter.chips(availableFilmSimulations: availableFilmSimulations, cameras: cameras,
                                 chapters: facets)) { chip in
                if chip.startsGroup {
                    DSRule(vertical: true)
                        .frame(height: DSSize.textKeyHeight - DSSpacing.m)
                        .padding(.horizontal, DSSpacing.xs)
                        .accessibilityHidden(true)
                }
                DSTextKey(label: chip.label, isOn: chip.isSelected) {
                    filter.toggle(chip.kind)
                }
            }
        }
        // A chapter edited or deleted while it filters the list: follow it, or fall back to All.
        .onChange(of: facets) { _, now in filter.refreshChapter(from: now) }
    }
}

/// The two fields under the Library's title: how many recipes the archive holds, and the camera's
/// slots as last read (`LibraryCameraField`).
enum LibraryHeaderFields {
    static func fields(recipeCount: Int, camera: LibraryCameraField) -> [DSDataField] {
        [DSDataField(label: "Archive", value: DSValueFormat.objectNumber(recipeCount)),
         // No LED for a camera never read: there is nothing for it to report on.
         DSDataField(label: "Camera", value: camera.value,
                     led: camera == .neverRead ? nil : camera.isLive, note: camera.asOf)]
    }
}
