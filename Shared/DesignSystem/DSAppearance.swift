import SwiftUI
import UIKit

/// The navigation bar in the design system's type, applied once at launch: large titles in the
/// heavy cut, inline titles semibold, both the system face and both following Dynamic Type.
/// Replaces the first design's serif titles.
enum DSAppearance {
    static func apply() {
        let large = UIFont.preferredFont(forTextStyle: .largeTitle)
        let inline = UIFont.preferredFont(forTextStyle: .headline)
        let largeTitle = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: .systemFont(ofSize: large.pointSize, weight: .heavy))
        let inlineTitle = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: .systemFont(ofSize: inline.pointSize, weight: .semibold))

        // Blurred bar once content scrolls under it, transparent at rest so the background runs
        // behind the large title.
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        for appearance in [standard, scrollEdge] {
            appearance.largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: DSColor.Tokens.textPrimary.uiColor]
            appearance.titleTextAttributes = [.font: inlineTitle, .foregroundColor: DSColor.Tokens.textPrimary.uiColor]
        }
        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge
    }
}

/// A section's mono caption over its content: "WHAT CHANGES".
struct DSSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .dsMetaMono(DSColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}
