import SwiftUI

/// The Library's filters as text keys with an LED: the same chips and taps as
/// `RecipeFilterChipRow`, which the recipe picker keeps until it moves to the design system.
struct LibraryFilterKeys: View {
    @Binding var filter: RecipeFilter
    let availableFilmSimulations: [FilmSimulation]
    let cameras: RecipeFilterCameras

    var body: some View {
        DSKeyRow {
            ForEach(filter.chips(availableFilmSimulations: availableFilmSimulations, cameras: cameras)) { chip in
                DSTextKey(label: chip.label, isOn: chip.isSelected) {
                    filter.toggle(chip.kind)
                }
            }
        }
    }
}

/// The two fields under the Library's title: how many recipes the archive holds, and the user's
/// camera.
enum LibraryHeaderFields {
    static func fields(recipeCount: Int, cameraIDs: [String]) -> [DSDataField] {
        [DSDataField(label: "Archive", value: DSValueFormat.objectNumber(recipeCount)),
         DSDataField(label: "Camera", value: cameraIDs.first ?? "—")]
    }
}
