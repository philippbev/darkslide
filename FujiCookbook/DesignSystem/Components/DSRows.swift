import SwiftUI

/// One recipe in a grouped list: test strip, name, a mono meta line and, when the recipe is in the
/// camera, its slot. Sits in a `dsCard()` with a `DSSeparator` between rows.
struct DSRecipeRow: View {
    let simulation: FilmSimulation?
    let name: String
    /// For example "CLASSIC CHROME   GRAIN WEAK": parts separated by space alone.
    let meta: String
    var slot: String?

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            DSTestStrip(simulation: simulation).listSize()
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(name)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(meta)
                    .dsLabelMono()
                    .lineLimit(1)
            }
            Spacer(minLength: DSSpacing.s)
            if let slot { DSSlotBadge(slot: slot) }
        }
        .padding(DSSpacing.m)
        .accessibilityElement(children: .combine)
    }
}

/// A group of settings: a mono heading above a card of label and value rows.
struct DSSettingsGroup: View {
    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let title: String
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(title)
                .dsLabelMono()
                .padding(.horizontal, DSSpacing.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { DSSeparator().padding(.leading, DSSpacing.l) }
                    HStack {
                        Text(row.label)
                            .font(DSFont.subhead)
                            .foregroundStyle(DSColor.textSecondary)
                        Spacer(minLength: DSSpacing.m)
                        Text(row.value)
                            .font(DSFont.valueMono)
                            .foregroundStyle(DSColor.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, DSSpacing.l)
                    .frame(minHeight: DSSize.settingsRowHeight)
                    .accessibilityElement(children: .combine)
                }
            }
            .dsCard()
        }
    }
}

/// The state of one thing the screen depends on, such as the camera or location: an icon tile, a
/// title, a mono meta line, and a status dot or a toggle on the right.
struct DSStatusCard<Trailing: View>: View {
    enum IconTint { case neutral, accent }

    let systemImage: String
    let title: String
    let meta: String
    var iconTint: IconTint = .neutral
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(iconTint == .accent ? DSColor.accentText : DSColor.textPrimary)
                .frame(width: DSSize.touchTarget, height: DSSize.touchTarget)
                .background(iconTint == .accent ? DSColor.accentSoft : DSColor.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: DSRadius.image, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(title)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Text(meta).dsLabelMono()
            }
            Spacer(minLength: DSSpacing.s)
            trailing
        }
        .padding(DSSpacing.l)
        .dsCard()
    }
}

/// The dot that says a connection is up.
struct DSStatusDot: View {
    /// What VoiceOver reads; the color alone doesn't carry it.
    var label = "Connected"

    var body: some View {
        Circle()
            .fill(DSColor.success)
            .frame(width: 10, height: 10)
            .accessibilityLabel(label)
    }
}
