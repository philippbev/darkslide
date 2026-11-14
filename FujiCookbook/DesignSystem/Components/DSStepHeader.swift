import SwiftUI

/// A numbered step of a task ("1  RAW files"): the number on a signal-blue LED-sized disc, the
/// title beside it. The Kitchen's develop flow reads as three steps, not a settings screen.
struct DSStepHeader: View {
    let number: Int
    let title: String
    @ScaledMetric(relativeTo: .headline) private var disc: CGFloat = 24

    var body: some View {
        HStack(spacing: DSSpacing.s + 2) {
            Text("\(number)")
                .dsSmallMono(size: 12, weight: .bold)
                .foregroundStyle(DSColor.onSignal)
                .frame(width: disc, height: disc)
                .background(Circle().fill(DSColor.signal))
            Text(title)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title)")
    }
}

#Preview("Step header") {
    VStack(alignment: .leading, spacing: DSSpacing.m) {
        DSStepHeader(number: 1, title: "RAW Files")
        DSStepHeader(number: 2, title: "Recipe")
    }
    .padding()
    .background(DSColor.background)
}
