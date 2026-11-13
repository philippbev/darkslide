import SwiftUI

/// Spacing on a 4 pt grid.
enum DSSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    /// Distance from the screen's edge to its content.
    static let screenMargin = l

    static let scale: [(name: String, value: CGFloat)] = [
        ("xs", xs), ("s", s), ("m", m), ("l", l), ("xl", xl), ("xxl", xxl), ("xxxl", xxxl)
    ]
}

/// Corner radii. Buttons, chips and round icon buttons are capsules and need none.
enum DSRadius {
    static let badge: CGFloat = 8
    static let image: CGFloat = 12
    static let card: CGFloat = 16
    static let sheet: CGFloat = 22

    static let scale: [(name: String, value: CGFloat)] = [
        ("badge", badge), ("image", image), ("card", card), ("sheet", sheet)
    ]
}

/// Fixed sizes the components share.
enum DSSize {
    /// The smallest touch target.
    static let touchTarget: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 50
    static let chipHeight: CGFloat = 36
    static let hintPillHeight: CGFloat = 32
    static let settingsRowHeight: CGFloat = 46
    static let listTestStrip: CGFloat = 56
    static let detailTestStripHeight: CGFloat = 120
}

extension View {
    /// The card every grouped surface uses: `surface` fill, card radius.
    func dsCard() -> some View {
        background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
    }
}

/// The hairline between rows of a card.
struct DSSeparator: View {
    var body: some View {
        Rectangle().fill(DSColor.separator).frame(height: 1)
    }
}
