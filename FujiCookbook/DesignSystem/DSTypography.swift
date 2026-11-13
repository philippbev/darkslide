import SwiftUI

/// The type scale: SF Pro through Dynamic Type styles, so every size follows the system setting,
/// and SF Mono for labels and setting values (the print on a film's edge).
enum DSFont {
    static let largeTitle = Font.largeTitle.bold()
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let subhead = Font.subheadline
    static let footnote = Font.footnote
    /// Use through `dsLabelMono()`, which adds the capitals and the tracking the label needs.
    static let labelMono = Font.system(.caption2, design: .monospaced).weight(.medium)
    /// Setting values: "+2", "R+2  B−5", "DR200".
    static let valueMono = Font.system(.subheadline, design: .monospaced)

    /// Tracking of a mono label, 0.1 em at the default 11 pt.
    static let labelTracking: CGFloat = 1.1
}

extension View {
    /// A mono label in capitals: context above a title, a section heading, a list's meta line.
    /// Parts of one label are separated by space alone, never by a "·".
    func dsLabelMono(_ color: Color = DSColor.textSecondary) -> some View {
        font(DSFont.labelMono)
            .textCase(.uppercase)
            .tracking(DSFont.labelTracking)
            .foregroundStyle(color)
    }
}

/// How setting values are written.
enum DSValueFormat {
    /// A signed step with a real minus sign: "+2", "−5", "0".
    static func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\u{2212}\(-value)" }
        return "0"
    }
}
