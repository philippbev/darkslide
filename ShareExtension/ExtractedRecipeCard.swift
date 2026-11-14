import SwiftUI

/// What the scan read, laid out the way the app lays out a recipe: serif name, film-simulation
/// swatch, a chip row of the headline parameters, then every extracted value in a table.
///
/// Rows come from `RecipeSettingsFormatter.rows(for:)`, the same primitive the app's detail screen
/// and the Kitchen's Read Recipe use — so what the user confirms here is rendered by exactly the
/// code that will render it afterwards. No `model:` filter: this is what the *screenshot* said, and
/// narrowing it to one camera's fields would quietly hide a value the user could see with their own
/// eyes.
struct ExtractedRecipeCard: View {
    let recipe: PortableRecipe
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            // `rows` omits nil fields by design — it shows what the screenshot *said*. A missing
            // film simulation is the one omission shown anyway: saved as-is, this recipe pushes
            // PROVIA / Standard, and the user is choosing whether to save it now.
            if recipe.settings.filmSimulation == nil {
                Label("No film simulation was read, so pushing this recipe writes PROVIA / Standard. Set one before saving if that isn't the look you want.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
            if !rows.isEmpty {
                Divider().background(DSColor.separator)
                settingsTable
            } else {
                Text("No settings could be read from this screenshot.")
                    .font(.footnote)
                    .foregroundStyle(DSColor.textSecondary)
            }
            if let notes = recipe.notes, !notes.isEmpty {
                Divider().background(DSColor.separator)
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(14)
        .themedCard(cornerRadius: 16)
    }

    private var rows: [(field: RecipeField, value: String)] {
        RecipeSettingsFormatter.rows(for: recipe.settings)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    FilmSwatch(simulation: recipe.settings.filmSimulation)
                    Text(recipe.name)
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2)
                }
                if let credit = recipe.credit, !credit.isEmpty {
                    Text("Recipe by \(credit)")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                let chips = RecipeSettingsFormatter.chips(for: recipe.settings)
                if !chips.isEmpty {
                    ChipFlow(spacing: 6) {
                        ForEach(chips, id: \.self) { ParamChip(text: $0) }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var settingsTable: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.field) { index, row in
                if index > 0 {
                    Rectangle().fill(DSColor.separator).frame(height: 0.5)
                }
                HStack {
                    Text(row.field.displayName)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                    Spacer(minLength: 12)
                    Text(row.value)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(DSColor.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 7)
            }
        }
    }
}
