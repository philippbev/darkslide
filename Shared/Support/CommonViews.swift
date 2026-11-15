import SwiftUI
import UIKit

/// Small shared views that predate the design system's own
/// components. They draw with its tokens (`DSColor`, `DSFont`); new UI uses the `DS` components.

// MARK: - Components

/// A small square of the film simulation's color.
struct FilmSwatch: View {
    let simulation: FilmSimulation?
    var size: CGFloat = 10

    var body: some View {
        Rectangle()
            .fill(simulation?.dsFill ?? DSNoSimulation.fill)
            .frame(width: size, height: size)
    }
}

/// One preset colour beside a colour picker: a filled circle, ringed in accent while it is the
/// colour in use. Selection compares resolved colours, so white chosen by the picker still lights
/// the white swatch.
struct SwatchButton: View {
    let color: Color
    let name: String
    let current: Color
    let action: () -> Void

    private var isSelected: Bool { UIColor(current).cgColor == UIColor(color).cgColor }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(DSColor.separator))
                .overlay { if isSelected { Circle().strokeBorder(DSColor.signal, lineWidth: 2).padding(-3) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A dense parameter chip ("DR400", "HL −1") — the design system's at-a-glance recipe summary unit.
struct ParamChip: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(prominent ? DSColor.panel : DSColor.panel,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// A pill-shaped filter chip — filled accent when selected, bordered card when not.
struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? DSColor.onSignal : DSColor.textPrimary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(selected ? AnyShapeStyle(DSColor.signal) : AnyShapeStyle(DSColor.surface),
                            in: Capsule())
                .overlay { if !selected { Capsule().strokeBorder(DSColor.separator) } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small bordered badge, e.g. the "X-T5" camera tag on a recipe card.
struct BadgeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(DSColor.separator))
    }
}

/// The secondary action beside or below a filled one: card fill, hairline border, accent label,
/// full width. Its height matches the filled buttons it sits with, so a pair reads as one row.
///
/// A primitive style so the button inside can stay `.plain` and keep the system's press highlight.
/// Disabled reads at the same 0.45 the filled buttons use.
struct OutlineButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.signalText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DSColor.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DSColor.separator))
                }
        }
        .buttonStyle(.plain)
        .modifier(DimmedWhenDisabled())
    }
}

extension PrimitiveButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}

private struct DimmedWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : 0.45)
    }
}

/// One setting as a label and its value: the label quiet, the value in ink with aligned digits, so a
/// column of signed numbers lines up. Read as one element by VoiceOver.
struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(DSColor.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A recipe's settings as one card of rows, in the order `RecipeSettingsFormatter.rows(for:model:)`
/// gives them. The rule between rows runs the card's full width, like the recipe page's own table.
struct SettingsTable: View {
    let rows: [(field: RecipeField, value: String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.field) { index, row in
                if index > 0 { Rectangle().fill(DSColor.separator).frame(height: 1) }
                SettingsRow(label: row.field.displayName, value: row.value)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .themedCard(cornerRadius: 16)
    }
}

/// Covers the screen while work that mustn't be interrupted runs: a dimmed backdrop that takes every
/// touch, and one card saying what is happening. The card is the app's own, so a wait reads as
/// part of the app rather than a system HUD.
struct BlockingProgressOverlay<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) { content }
                .padding(24)
                .themedCard(cornerRadius: 16)
                .accessibilityElement(children: .combine)
        }
    }
}

extension View {
    /// A blocking overlay with a spinner and one line saying what is happening.
    func blockingProgress(_ label: String, isPresented: Bool) -> some View {
        overlay {
            if isPresented {
                BlockingProgressOverlay {
                    ProgressView()
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(DSColor.textPrimary)
                }
            }
        }
    }
}

/// Card chrome shared by the screens the design system's rollout didn't redraw one by one: the
/// archive's square frame, `surface` inside a 1.5 pt rule. `cornerRadius` is kept for the call
/// sites; the archive has none.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content.dsArchiveFrame()
    }
}

extension View {
    /// Apply the design system's card chrome.
    func themedCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

    /// Style a `List`/`Form` screen with the warm paper background.
    func paperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(DSColor.background)
    }
}

/// Left-aligned wrapping layout for parameter chips.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
