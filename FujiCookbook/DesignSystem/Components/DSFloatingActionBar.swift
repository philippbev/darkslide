import SwiftUI

/// The bar floating at the bottom of a screen: a mono status line ("TARGET C3   WRITE  READ BACK
/// VERIFY") over the screen's keys. Put it in `safeAreaInset(edge: .bottom)`.
///
/// Liquid Glass from iOS 26, a material under `chromeGlass` before: the one place besides the tab
/// bar where the design system allows a material.
struct DSFloatingActionBar<Content: View>: View {
    var status: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if let status { Text(status).dsMetaMono() }
            content
        }
        .padding(DSSpacing.l)
        .padding(.bottom, DSSize.keyShadowOffset)
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

/// A line of the bar that names a choice and its value, such as "Destination" and "Photo Library".
struct DSActionBarDetail<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack {
            Text(label).dsMetaMono()
            Spacer()
            value
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension DSActionBarDetail where Value == Text {
    init(label: String, value: String) {
        self.init(label: label) { Text(value) }
    }
}

#Preview("Floating action bar") {
    Color.clear
        .background(DSColor.background)
        .safeAreaInset(edge: .bottom) {
            DSFloatingActionBar(status: "Target C3   Write  Read back  Verify") {
                HStack(spacing: DSSpacing.m) {
                    Button("Undo") {}.buttonStyle(.dsSecondary)
                    Button("Load into C3") {}.buttonStyle(.dsPrimary)
                }
            }
        }
}
