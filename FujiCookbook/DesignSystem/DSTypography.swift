import SwiftUI

/// The type scale: SF Pro and SF Mono through Dynamic Type.
///
/// The text-style tokens are plain fonts. The tokens with a fixed size in the specification
/// (object number, field label, key label) are modifiers instead: they scale that size with
/// `@ScaledMetric`, so they grow with the reader's text size like everything else.
enum DSFont {
    static let largeTitle = Font.largeTitle.weight(.heavy)
    static let title = Font.title.weight(.heavy)
    static let headline = Font.headline.weight(.bold)
    static let body = Font.body
    static let subhead = Font.subheadline
    /// Use through `dsMetaMono()`, which adds the capitals and the tracking.
    static let metaMono = Font.system(.caption2, design: .monospaced)
    /// Setting values: "+2", "R+2  B−5", "DR200".
    static let valueMono = Font.system(.subheadline, design: .monospaced).weight(.medium)

    /// Tracking in em, multiplied by the size where it is applied.
    static let largeTitleTracking = -0.03
    static let objectNumberTracking = -0.04
    static let fieldLabelTracking = 0.1
    static let metaMonoTracking = 0.08
    /// The default point size of `metaMono` (caption 2), for its tracking.
    static let metaMonoSize: CGFloat = 11
}

/// A fixed point size that follows Dynamic Type, scaled against a text style.
private struct DSScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    /// In em.
    let tracking: Double
    let monospacedDigits: Bool

    init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, design: Font.Design,
         tracking: Double = 0, monospacedDigits: Bool = false) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.tracking = tracking
        self.monospacedDigits = monospacedDigits
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight, design: design)
        content
            .font(monospacedDigits ? font.monospacedDigit() : font)
            .tracking(tracking * size)
    }
}

extension View {
    /// A recipe's archive number in signal blue: 64 on the card, 52 in a header, 26 in a list.
    func dsObjectNumber(size: CGFloat = 64) -> some View {
        modifier(DSScaledFont(size: size, relativeTo: .largeTitle, weight: .heavy, design: .default,
                              tracking: DSFont.objectNumberTracking, monospacedDigits: true))
            .foregroundStyle(DSColor.signalText)
    }

    /// The screen title's heavy cut with its tighter tracking.
    func dsLargeTitle() -> some View {
        font(DSFont.largeTitle)
            .tracking(DSFont.largeTitleTracking * 34)
            .foregroundStyle(DSColor.textPrimary)
    }

    /// A field's caption in capitals above its value. Short labels only.
    func dsFieldLabel() -> some View {
        modifier(DSScaledFont(size: 10, relativeTo: .caption2, weight: .regular, design: .monospaced,
                              tracking: DSFont.fieldLabelTracking))
            .textCase(.uppercase)
            .foregroundStyle(DSColor.textSecondary)
    }

    /// A meta line or section heading in capitals. Parts are separated by space alone, never by "·".
    func dsMetaMono(_ color: Color = DSColor.textSecondary) -> some View {
        font(DSFont.metaMono)
            .textCase(.uppercase)
            .tracking(DSFont.metaMonoTracking * DSFont.metaMonoSize)
            .foregroundStyle(color)
    }

    /// The label of a slot key: "C1".
    func dsKeyLabel() -> some View {
        modifier(DSScaledFont(size: 18, relativeTo: .headline, weight: .bold, design: .monospaced))
    }

    /// A small mono label at a fixed base size, such as a frame number or the name under a slot key.
    func dsSmallMono(size: CGFloat = 10, weight: Font.Weight = .medium) -> some View {
        modifier(DSScaledFont(size: size, relativeTo: .caption2, weight: weight, design: .monospaced))
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

    /// An archive number with three digits: "034".
    static func objectNumber(_ value: Int) -> String {
        value < 0 ? "000" : String(format: "%03d", value)
    }
}
