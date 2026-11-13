import SwiftUI

/// One frame of the import's contact sheet: the picture, its frame number, its file formats, and
/// whether it is selected. A frame that isn't selected is dimmed.
struct DSContactSheetTile: View {
    /// Nil while the thumbnail loads.
    var image: Image?
    /// Stands in for the picture until it loads.
    var placeholder: Color = DSColor.surfaceSecondary
    let frameNumber: String
    /// For example "RAF+JPG".
    var format: String?
    let isSelected: Bool

    var body: some View {
        placeholder
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { image.resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.badge, style: .continuous))
            .opacity(isSelected ? 1 : 0.45)
            .overlay(alignment: .bottomLeading) {
                Text(frameNumber)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1, y: 0.5)
                    .padding(DSSpacing.xs + 2)
            }
            .overlay(alignment: .topLeading) {
                if let format {
                    Text(format)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(DSSpacing.xs + 2)
                }
            }
            .overlay(alignment: .topTrailing) { selectionMark.padding(DSSpacing.xs + 2) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Frame \(frameNumber)\(format.map { ", \($0)" } ?? "")")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionMark: some View {
        ZStack {
            Circle().fill(isSelected ? DSColor.accent : Color.black.opacity(0.2))
            Circle().strokeBorder(.white, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DSColor.onAccent)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// The contact sheet's grid: three columns, 4 pt apart.
enum DSContactSheet {
    static let spacing = DSSpacing.xs
    static let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
}

/// The bar floating at the bottom of a screen that holds its primary button and, where needed, a
/// line above it such as the import's destination. Put it in `safeAreaInset(edge: .bottom)`.
///
/// Liquid Glass from iOS 26; before that a material under the `chromeGlass` tint.
struct DSActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: DSSpacing.m) { content }
            .padding(DSSpacing.l)
            .frame(maxWidth: .infinity)
            .background { chrome.ignoresSafeArea(edges: .bottom) }
            .overlay(alignment: .top) { DSSeparator() }
    }

    @ViewBuilder
    private var chrome: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: .rect)
        } else {
            Rectangle().fill(.regularMaterial).overlay(DSColor.chromeGlass)
        }
    }
}

/// A line of the action bar that names a choice and its value, such as "Destination" and
/// "Photo Library".
struct DSActionBarDetail: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).dsLabelMono()
            Spacer()
            Text(value)
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
