import SwiftUI

/// One recipe card in the inventory — the design system's "recipe card" unit: thumbnail, serif
/// name, favorite star, film-sim family swatch, and camera badge.
struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(recipe.name)
                        .font(Theme.serif(19))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if recipe.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.star)
                    }
                    if recipe.hasPreservedUnsupportedFields {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                            .accessibilityLabel("Contains fields not modeled by this app")
                    }
                }
                HStack(spacing: 7) {
                    FilmSwatch(simulation: recipe.settings.filmSimulation, size: 9)
                    Text(recipe.settings.filmSimulation?.displayName ?? "No film simulation")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                    if let model = recipe.authoredForModel {
                        // Model ids are the short marketing names ("X-T5") — right size for a badge.
                        BadgeTag(text: model.id)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        // Cached by uuid so the JPEG decode doesn't repeat on every body evaluation while scrolling.
        if let photo = recipe.sortedPhotos.first,
           let image = ThumbnailCache.thumbnail(uuid: photo.uuid, data: photo.thumbnailData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((recipe.settings.filmSimulation?.swatchColor ?? Theme.ink3).opacity(0.22))
                .frame(width: 56, height: 56)
                .overlay {
                    FilmSwatch(simulation: recipe.settings.filmSimulation, size: 18)
                }
        }
    }
}
