import SwiftUI

/// A darkroom test strip in place of a sample photo: five equal patches, shadows to highlights,
/// with no gap between them.
struct DSTestStrip: View {
    let simulation: FilmSimulation?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(TestStripPalette.colors(for: simulation).enumerated()), id: \.offset) { _, color in
                color
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.image, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The square strip of a list row.
    func listSize() -> some View {
        frame(width: DSSize.listTestStrip, height: DSSize.listTestStrip)
    }
}

/// The strip of a recipe's detail page: full width, with the tonal range named beneath it.
struct DSTestStripDetail: View {
    let simulation: FilmSimulation?

    var body: some View {
        VStack(spacing: DSSpacing.s) {
            DSTestStrip(simulation: simulation)
                .frame(maxWidth: .infinity)
                .frame(height: DSSize.detailTestStripHeight)
            HStack {
                Text("Shadows")
                Spacer()
                Text("Midtones")
                Spacer()
                Text("Highlights")
            }
            .dsLabelMono()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Test strip, shadows to highlights")
    }
}
