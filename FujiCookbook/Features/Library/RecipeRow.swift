import SwiftUI

/// One recipe in the Library list: the design system's recipe row, with the simulation's color
/// column, the archive number, a star for a favorite and a mark for fields the app keeps but
/// doesn't model.
///
/// The camera slot badge stays off: a recipe doesn't know which slot it sits in until a camera is
/// connected and read.
struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        DSRecipeRow(simulation: recipe.settings.filmSimulation,
                    objectNumber: Self.objectNumber(recipe.archiveNumber),
                    name: recipe.name,
                    meta: Self.meta(filmSimulation: recipe.settings.filmSimulation,
                                    authoredFor: recipe.authoredForModel),
                    isFavorite: recipe.isFavorite,
                    warning: recipe.hasPreservedUnsupportedFields ? "Contains fields not modeled by this app" : nil)
    }

    /// "034"; a dash for a recipe the numbering hasn't reached yet (an open editor's new recipe).
    static func objectNumber(_ number: Int) -> String {
        number > 0 ? DSValueFormat.objectNumber(number) : "—"
    }

    /// The mono line under the name: the film simulation, then the body the recipe was written
    /// for, separated by space alone ("CLASSIC CHROME   X100VI"). `dsMetaMono` sets the capitals.
    static func meta(filmSimulation: FilmSimulation?, authoredFor model: CameraModel?) -> String {
        [filmSimulation?.displayName ?? "No film simulation", model?.id]
            .compactMap { $0 }
            .joined(separator: "   ")
    }
}

extension View {
    /// One row of an archive frame inside a system `List`, where rows can't share one frame: the
    /// top rule and the sides on every row, the bottom rule on the last, so neighbouring rows draw
    /// one 1.5 pt line between them.
    func dsArchiveListRow(isLast: Bool) -> some View {
        background(DSColor.surface)
            .overlay(alignment: .top) { DSRule() }
            .overlay(alignment: .leading) { DSRule(vertical: true) }
            .overlay(alignment: .trailing) { DSRule(vertical: true) }
            .overlay(alignment: .bottom) { if isLast { DSRule() } }
    }
}
