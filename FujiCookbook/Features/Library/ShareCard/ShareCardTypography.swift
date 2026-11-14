import CoreText
import SwiftUI
import UIKit

// MARK: - Palette

/// The card palette, spelled out as fixed values rather than read from the design system.
///
/// A card is a poster, not a screen: it is exported in light appearance whatever the phone is set
/// to, so the paper stays warm paper instead of turning into dark-mode paper the moment the user
/// shares one after sunset. Every value here is a *light* value of the app's first palette,
/// plus the handful of literals that only exist over a photograph.
enum CardPalette {
    // The first design's paper and ink, pinned light: a shared card keeps its look.
    static let paper = Color(cardHex: 0xF4EFE4)
    /// The inset surface — what an empty photo window on the Quarter Grid card shows.
    static let paper2 = Color(cardHex: 0xEFE8DA)
    static let ink = Color(cardHex: 0x201D17)
    static let ink2 = Color(cardHex: 0x6E675A)
    static let ink3 = Color(cardHex: 0xA49C8A)
    static let line = Color(cardHex: 0xE7DFCF)

    /// The brand mark: green on paper and beside ink type, mint beside light type over a
    /// photograph. Both are the brand kit's values rather than design-system tokens: the kit fixes
    /// them, and a shared card keeps its look whatever the app's palette is.
    static let mark = Color(cardHex: 0x2E6B4A)
    static let markOnDark = Color(cardHex: 0x86D5AC)

    /// Light text on the Plain card.
    static let overlayLight = Color(cardHex: 0xF7F3EA)
    /// Light text on the Story card's gradients: the paper colour, a touch dimmer and warmer than
    /// `overlayLight`.
    static let storyLight = Color(cardHex: 0xF4EFE4)
    /// Ink text on the Plain card in its Dark Text tone.
    static let overlayInk = Color(cardHex: 0x1B1813)

    /// The wide drop shadow that separates the Plain card's block, and the Story card's top bar, from
    /// the photograph — the design's alternative to laying a gradient over it.
    static let overlayShadow = Color(red: 12 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.5)
    /// The tight companion pass: same ink, drawn close enough to give each stroke its own edge where
    /// the wide blur is too diffuse to register.
    static let overlayShadowTight = Color(red: 12 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.6)
    /// Their inverses for ink type on a bright photograph: a paper-coloured halo, not a dark one.
    static let overlayLightShadow = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255).opacity(0.55)
    static let overlayLightShadowTight = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255).opacity(0.65)

    /// The Story card's foot gradient.
    static func gradientInk(_ opacity: Double) -> Color {
        Color(red: 16 / 255, green: 14 / 255, blue: 10 / 255).opacity(opacity)
    }
    /// The Feed card's gradient where the photograph meets the paper.
    static func photoGradientInk(_ opacity: Double) -> Color {
        Color(red: 20 / 255, green: 18 / 255, blue: 14 / 255).opacity(opacity)
    }
}

extension Color {
    /// Card literals are written as hex to stay legible against the design document.
    init(cardHex: UInt32) {
        self.init(red: Double((cardHex >> 16) & 0xFF) / 255,
                  green: Double((cardHex >> 8) & 0xFF) / 255,
                  blue: Double(cardHex & 0xFF) / 255)
    }
}

// MARK: - Line breaking

/// Line breaking done by hand, so the cards can honour the design's tight line heights.
///
/// The design sets the recipe name at line-height 1.0 (0.98 on Story, 1.04 on Quarter Grid). SwiftUI has no way
/// to tighten a multi-line `Text` below the font's natural leading — roughly 1.2× — and the Specimen
/// card in particular is laid out with about ten points of slack, so the difference between 1.0 and
/// 1.2 on a two-line name is the difference between fitting and not. Breaking the string here lets
/// each line be drawn in a box of exactly the height the design asks for.
enum CardTextLayout {

    /// Break `text` into at most `limit` lines that fit `maxWidth`, tail-truncating the last one.
    static func lines(_ text: String,
                      font: UIFont,
                      tracking: CGFloat,
                      maxWidth: CGFloat,
                      limit: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, maxWidth > 0, limit > 0 else { return [] }

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking]
        let attributed = NSAttributedString(string: trimmed, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let source = trimmed as NSString

        var result: [String] = []
        var start = 0
        while start < source.length, result.count < limit {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(maxWidth))
            guard count > 0 else { break }
            let piece = source.substring(with: NSRange(location: start, length: count))
            result.append(piece.trimmingCharacters(in: .whitespacesAndNewlines))
            start += count
        }

        // Anything past the limit folds into an ellipsis on the last line. Shrinking that line by a
        // character at a time is cheap here — a recipe name is a handful of words, not a paragraph.
        if start < source.length, var last = result.popLast() {
            while !last.isEmpty, width(of: last + "…", attributes: attributes) > maxWidth {
                last = String(last.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            result.append(last + "…")
        }
        return result
    }

    private static func width(of text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }

    /// The width of one run, at the size and tracking a card would draw it.
    static func width(_ text: String, font: UIFont, tracking: CGFloat) -> CGFloat {
        width(of: text, attributes: [.font: font, .kern: tracking])
    }

    /// The widest label-plus-value pair in a ledger, which is what decides how many columns a canvas
    /// can carry. Measured rather than estimated: "Noise Reduction" is several times the width of
    /// "WB", and only the recipe actually on the card knows which labels it has.
    static func widestLedgerEntry(_ lines: [ShareCardContent.Line],
                                  labelSize: CGFloat,
                                  valueSize: CGFloat) -> CGFloat {
        let labelFont = CardLedgerRow.labelFont(size: labelSize).uiFont
        let valueFont = CardLedgerRow.valueFont(size: valueSize).uiFont
        return lines.reduce(0) { widest, line in
            let label = width(line.label.uppercased(), font: labelFont,
                              tracking: CardLedgerRow.labelTrackingEm * labelSize)
            let value = width(line.value, font: valueFont, tracking: 0)
            return max(widest, label + value)
        }
    }
}

/// A card run's font, stated once for both Core Text, which measures the run to fit it, and
/// SwiftUI, which draws it. A run drawn a weight heavier than it was measured comes out wider than
/// the room the layout gave it, and is clipped.
struct CardFont: Equatable {
    /// The weights the cards set. Only these, so every mapping below is exhaustive.
    enum Weight { case regular, medium, semibold }
    enum Design { case standard, serif }

    let size: CGFloat
    var weight: Weight = .regular
    var design: Design = .standard

    /// The recipe name's face on every card.
    static func recipeName(size: CGFloat) -> CardFont {
        CardFont(size: size, weight: .semibold, design: .serif)
    }

    var font: Font {
        let weight: Font.Weight = switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
        let design: Font.Design = switch design {
        case .standard: .default
        case .serif: .serif
        }
        return .system(size: size, weight: weight, design: design)
    }

    /// Matched to `font`: the system face at the same size and weight, in the serif design when
    /// `font` is serif.
    var uiFont: UIFont {
        let weight: UIFont.Weight = switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard design == .serif, let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - Type roles

/// The recipe name, in the cards' serif, at an exact line height, at most two lines.
///
/// Two lines is the design's cap on every style.
struct CardTitle: View {
    let text: String
    let size: CGFloat
    /// As a multiple of the size. Each style passes its own from its spec.
    var lineHeight: CGFloat = 1.0
    /// Letter spacing as a fraction of the size. Each style passes its own.
    var trackingEm: CGFloat = -0.01
    let color: Color
    let maxWidth: CGFloat
    var alignment: HorizontalAlignment = .leading
    var lineLimit: Int = 2

    private var tracking: CGFloat { trackingEm * size }
    private var font: CardFont { .recipeName(size: size) }

    var body: some View {
        let lines = CardTextLayout.lines(text,
                                         font: font.uiFont,
                                         tracking: tracking,
                                         maxWidth: maxWidth,
                                         limit: lineLimit)
        VStack(alignment: alignment, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(font.font)
                    .tracking(tracking)
                    .foregroundStyle(color)
                    .fixedSize()
                    .frame(height: size * lineHeight)
            }
        }
    }
}

/// A tracked, uppercased run — the cards' small-caps voice (film simulation, ledger labels, the
/// Specimen recipe number, Quarter Grid's footer tag). Drawn in a box exactly one em tall, matching
/// the design's line-height 1.
struct CardCaps: View {
    let text: String
    let size: CGFloat
    var weight: CardFont.Weight = .semibold
    /// Letter spacing as a fraction of the size, as the design writes it (0.1em … 0.18em).
    let trackingEm: CGFloat
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(CardFont(size: size, weight: weight).font)
            .tracking(trackingEm * size)
            .foregroundStyle(color)
            .fixedSize()
            .frame(height: size)
    }
}

/// The credit line — "RECIPE BY NORTHLIGHT" — in the cards' small-caps voice, on exactly one
/// line.
///
/// It can't be a plain `CardCaps`: that run is `fixedSize`, which is right for a film-simulation
/// name and wrong for a credit, where the string is whatever the photographer typed. A name long
/// enough to outrun the card would simply draw past the edge and be clipped mid-letter. Breaking it
/// here with the same typesetter `CardTitle` uses means it ends in an ellipsis instead, and the
/// height the layout reserved still holds.
struct CardCredit: View {
    let text: String
    let size: CGFloat
    let trackingEm: CGFloat
    let color: Color
    let maxWidth: CGFloat

    private var tracking: CGFloat { trackingEm * size }

    /// Semibold, and not adjustable. This is the smallest run on the card and it is set in tracked
    /// caps, which thins a line further — at medium it goes grey before it goes small.
    private var font: CardFont { CardFont(size: size, weight: .semibold) }

    var body: some View {
        let caps = text.uppercased()
        let fitted = CardTextLayout.lines(caps,
                                          font: font.uiFont,
                                          tracking: tracking,
                                          maxWidth: maxWidth,
                                          limit: 1).first ?? caps
        Text(fitted)
            .font(font.font)
            .tracking(tracking)
            .foregroundStyle(color)
            .fixedSize()
            .frame(height: size)
    }
}

/// The app mark — the rounded square from the icon, drawn rather than shipped as artwork so it is
/// exact at any size. Never the full icon tile: that is the mark on its tinted field, and a card
/// sets the mark on its own paper or photograph.
struct BrandMark: View {
    let size: CGFloat
    let color: Color

    /// The brand kit's corner: 4/13 of the side, continuous.
    static let cornerRatio: CGFloat = 4.0 / 13.0

    var body: some View {
        RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// The mark and the wordmark — the brand kit's lockup, and the sign-off every card carries in one
/// arrangement or another.
///
/// The kit outlines the wordmark in Source Serif 4, which the app doesn't bundle, so it is set here
/// in the serif the cards use for recipe names. The proportions are the kit's, in ems of the type
/// size, so the lockup keeps its shape at any size. The mark takes its own colour rather than the
/// type's: the brand fixes it, and fading it with the type would muddy it over a photograph.
struct CardWordmark: View {
    /// The wordmark's type size, and its height on the card; the mark and the gap follow from it.
    let textSize: CGFloat
    let color: Color
    let markColor: Color
    /// Plain puts the wordmark first in a trailing corner, where its block is right-aligned.
    var markTrails: Bool = false

    private static let markEm: CGFloat = 0.62
    private static let gapEm: CGFloat = 0.57
    /// Where the mark's centre sits above the baseline.
    private static let markCentreEm: CGFloat = 0.35
    private static let trackingEm: CGFloat = -0.01

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.gapEm * textSize) {
            if markTrails {
                wordmark
                mark
            } else {
                mark
                wordmark
            }
        }
    }

    /// The mark carries the wordmark's baseline at the kit's height, so it sits right whichever
    /// baseline a caller aligns the lockup on.
    private var mark: some View {
        let baseline = { (dimensions: ViewDimensions) in
            dimensions[VerticalAlignment.center] + Self.markCentreEm * textSize
        }
        return BrandMark(size: Self.markEm * textSize, color: markColor)
            .alignmentGuide(.firstTextBaseline, computeValue: baseline)
            .alignmentGuide(.lastTextBaseline, computeValue: baseline)
    }

    private var wordmark: some View {
        Text("Fuji Cookbook")
            .font(.system(size: textSize, weight: .semibold, design: .serif))
            .tracking(Self.trackingEm * textSize)
            .foregroundStyle(color)
            .fixedSize()
            .frame(height: textSize)
    }
}

/// One ledger row: label left, value right, a hairline underneath unless it ends its column.
///
/// Shared by the Story, Feed and Specimen cards — they differ only in size and colour, which is
/// exactly the kind of difference a preset should be.
struct CardLedgerRow: View {
    let line: ShareCardContent.Line
    let labelSize: CGFloat
    let valueSize: CGFloat
    let labelColor: Color
    let valueColor: Color
    let ruleColor: Color
    let verticalPadding: CGFloat
    let showsRule: Bool

    /// A hairline at the canvas's own scale.
    var ruleHeight: CGFloat = 1

    // The label's and value's faces, which `CardTextLayout.widestLedgerEntry` measures with to
    // decide how many columns a card can carry.
    private static let labelWeight: CardFont.Weight = .medium
    static let labelTrackingEm: CGFloat = 0.1
    static func labelFont(size: CGFloat) -> CardFont { CardFont(size: size, weight: labelWeight) }
    static func valueFont(size: CGFloat) -> CardFont { CardFont(size: size, weight: .semibold) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: labelSize * 0.5) {
                CardCaps(text: line.label, size: labelSize, weight: Self.labelWeight,
                         trackingEm: Self.labelTrackingEm, color: labelColor)
                Spacer(minLength: labelSize * 0.35)
                Text(line.value)
                    .font(Self.valueFont(size: valueSize).font)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .fixedSize()
                    .frame(height: valueSize)
            }
            // Pinned rather than natural, so resolving a card's height and drawing it agree.
            .frame(height: valueSize)
            .padding(.vertical, verticalPadding)
            if showsRule {
                Rectangle().fill(ruleColor).frame(height: ruleHeight)
            }
        }
    }
}

// MARK: - Controls

/// A miniature of the card with four tappable quadrants — the block goes where you tap.
///
/// A segmented control of four corner names would be wider than the preview it describes; a picture
/// of the decision is both smaller and more obvious.
struct PlainCornerPicker: View {
    @Binding var selection: PlainCorner

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) { cell(.topLeading); cell(.topTrailing) }
            HStack(spacing: 2) { cell(.bottomLeading); cell(.bottomTrailing) }
        }
        .padding(3)
        .background(DSColor.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Text position")
    }

    private func cell(_ corner: PlainCorner) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = corner }
        } label: {
            VStack(alignment: corner.horizontal, spacing: 2) {
                Capsule().frame(width: 13, height: 2)
                Capsule().frame(width: 8, height: 2)
            }
            .foregroundStyle(selection == corner ? DSColor.signalText : DSColor.textSecondary)
            .frame(width: 17, height: 12, alignment: corner.alignment)
            .padding(4)
            .background(selection == corner ? DSColor.panel : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(corner.title)
        .accessibilityAddTraits(selection == corner ? .isSelected : [])
    }
}
