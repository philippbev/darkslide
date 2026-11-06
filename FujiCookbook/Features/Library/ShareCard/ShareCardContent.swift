import Foundation

/// Everything a share card draws, resolved from a `Recipe` once and handed to whichever style is
/// selected.
///
/// The point of the indirection is that the five styles are presets of one renderer: they differ in
/// layout, never in what they say. Anything a recipe may lack (the film simulation, the credit, the
/// recipe number) is optional here, and a style drops the element rather than printing a
/// placeholder.
struct ShareCardContent: Equatable {

    /// One line of the settings block. `label` is the card's own short name for the field; `value`
    /// is whatever `RecipeSettingsFormatter` renders, so a card says exactly what every other
    /// read-only screen says about the same recipe.
    struct Line: Identifiable, Equatable {
        /// The label doubles as the id — the fixed order below never repeats one.
        var id: String { label }
        let label: String
        let value: String
    }

    let name: String
    /// Drives the family swatch on the paper and story cards.
    let filmSimulation: FilmSimulation?
    let filmSimulationName: String?
    /// Who the recipe is by, already trimmed — nil when it's unattributed, in which case every style
    /// drops the line and gets its height back. A card that travels off the phone is exactly where
    /// attribution matters most, so every style carries it.
    let credit: String?
    /// The parameters the recipe actually sets, in the fixed card order.
    let lines: [Line]
    /// 1-based position in the recipe's chapter, for the Specimen card's "RECIPE № 04". Nil when the
    /// recipe belongs to no chapter.
    let recipeNumber: Int?

    /// The credit as the cards print it, or nil when there is none.
    var creditLine: String? { credit.map { "Recipe by \($0)" } }

    /// `lines`, with the film simulation prepended as its own row. Plain is the one style with no
    /// film line of its own (no swatch, no separate run above the settings), so it draws the base
    /// the same way it draws everything that adjusts it.
    var linesWithFilmSimulation: [Line] {
        guard let simulation = filmSimulationName else { return lines }
        return [Line(label: "Film Simulation", value: simulation)] + lines
    }

    init(recipe: Recipe, recipeNumber: Int? = nil) {
        self.name = recipe.name
        self.filmSimulation = recipe.settings.filmSimulation
        self.filmSimulationName = RecipeSettingsFormatter.valueString(for: .filmSimulation,
                                                                      in: recipe.settings)
        self.credit = recipe.displayCredit
        self.lines = Self.lines(for: recipe.settings)
        self.recipeNumber = recipeNumber
    }

    /// The fields a card prints, in the order the design fixes — which is the order of the app's
    /// parameter section, so a card reads the same way as the detail screen.
    private static let fieldOrder: [RecipeField] = [
        .grain, .colorChromeEffect, .colorChromeFXBlue, .whiteBalance,
        .dynamicRange, .highlightTone, .shadowTone,
        .color, .sharpness, .highISONR, .clarity
    ]

    /// The card's own name for each field. `RecipeField.displayName` is the app's name and is the
    /// right one on a detail row, where there is a whole screen width to spend; a ledger column on
    /// a card is a couple of inches wide and needs "WB".
    private static let cardLabel: [RecipeField: String] = [
        .grain: "Grain",
        .colorChromeEffect: "Color Chrome",
        .colorChromeFXBlue: "FX Blue",
        .whiteBalance: "WB",
        .dynamicRange: "Dynamic Range",
        .dRangePriority: "D-Range Priority",
        .highlightTone: "Highlight",
        .shadowTone: "Shadow",
        .color: "Color",
        .sharpness: "Sharpness",
        .highISONR: "Noise Reduction",
        .clarity: "Clarity"
    ]

    /// The settings block. Every value comes from `RecipeSettingsFormatter`, the primitive the
    /// detail screen, the share extension's card, the Kitchen read and the Camera Test all render
    /// rows from, so a card cannot quietly disagree with any of them about the same recipe. A
    /// parameter the recipe doesn't set has no line at all; the block simply gets shorter.
    ///
    /// The one place a card parts company with those screens is how it says that D-Range Priority
    /// has taken a field over. The formatter appends a sentence — "DR400 · overridden by D-Range
    /// Priority" — which reads well on a row beside the recipe it belongs to. A card is a poster:
    /// the ledger column is too narrow to hold that, and it is looked at with no app around it to
    /// explain. So the card takes the same decision to its conclusion instead. While the priority
    /// is on, the fields it drives are not printed and the priority that drives them is, and a
    /// photographer copying the card into their camera dials in what the camera will honour and
    /// nothing it refuses.
    ///
    /// No model is passed, which is what `RecipeDetailView` does. Neither has a camera in front of
    /// it, and two screens showing one recipe differently is the thing this primitive exists to
    /// prevent.
    private static func lines(for s: RecipeSettings) -> [Line] {
        let overridden = RecipeApplicability.priorityOverrides(s, on: nil)

        var fields: [RecipeField] = []
        for field in fieldOrder {
            guard overridden, RecipeApplicability.fieldsUnderPriority.contains(field) else {
                fields.append(field)
                continue
            }
            // The priority stands in the first slot of the run it overrides, so the block keeps its
            // reading order. Which fields those are is `RecipeApplicability.fieldsUnderPriority`, the
            // set the formatter notes, so a field brought under the priority is handled here too.
            if !fields.contains(.dRangePriority) { fields.append(.dRangePriority) }
        }

        return fields.compactMap { field -> Line? in
            guard let label = Self.cardLabel[field] else { return nil }
            guard let value = RecipeSettingsFormatter.valueString(for: field, in: s) else { return nil }
            return Line(label: label, value: value)
        }
    }

    /// Split into `count` columns, filling the first column before the next — the reading order the
    /// ledger cards want.
    func columns(_ count: Int) -> [[Line]] {
        guard count > 1 else { return [lines] }
        guard !lines.isEmpty else { return Array(repeating: [], count: count) }
        let perColumn = Int((Double(lines.count) / Double(count)).rounded(.up))
        return (0..<count).map { column in
            let start = min(column * perColumn, lines.count)
            let end = min(start + perColumn, lines.count)
            return Array(lines[start..<end])
        }
    }
}
