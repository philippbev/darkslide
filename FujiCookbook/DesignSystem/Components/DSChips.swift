import SwiftUI

/// A chapter filter chip. Selected inverts: ink as the ground, paper as the text, so the accent
/// stays reserved for actions.
struct DSChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DSFont.subhead.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(isSelected ? DSColor.background : DSColor.textPrimary)
                .padding(.horizontal, DSSpacing.l)
                .frame(minHeight: DSSize.chipHeight)
                .background(isSelected ? DSColor.textPrimary : DSColor.surfaceSecondary, in: Capsule())
                // The chip is 36 pt high; the touch target is still 44.
                .frame(minHeight: DSSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPlainPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row of chips that scrolls sideways and starts at the screen margin.
struct DSChipRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.s) { content }
                .padding(.horizontal, DSSpacing.screenMargin)
        }
    }
}

/// The camera slot a recipe sits in: "C1" to "C7".
struct DSSlotBadge: View {
    let slot: String

    var body: some View {
        Text(slot)
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .foregroundStyle(DSColor.accentText)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xs)
            .overlay(RoundedRectangle(cornerRadius: DSRadius.badge, style: .continuous)
                .strokeBorder(DSColor.accent, lineWidth: 1.5))
            .accessibilityLabel("Slot \(slot)")
    }
}

/// A short hint on a soft accent ground, such as which camera a recipe runs on.
struct DSHintPill: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: DSSpacing.xs + 2) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(1)
        }
        .font(DSFont.footnote.weight(.semibold))
        .foregroundStyle(DSColor.accentText)
        .padding(.horizontal, DSSpacing.m)
        .frame(minHeight: DSSize.hintPillHeight)
        .background(DSColor.accentSoft, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
