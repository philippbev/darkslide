import SwiftUI

/// The primary action: a full-width Safelight capsule. One per screen, in the floating action bar.
struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.headline)
            .foregroundStyle(DSColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: DSSize.primaryButtonHeight)
            .padding(.horizontal, DSSpacing.xl)
            .background(DSColor.accent, in: Capsule())
            .modifier(DSPressFeedback(isPressed: configuration.isPressed))
    }
}

/// The action beside or below the primary one: the same capsule on `surfaceSecondary`.
struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.headline)
            .foregroundStyle(DSColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: DSSize.primaryButtonHeight)
            .padding(.horizontal, DSSpacing.xl)
            .background(DSColor.surfaceSecondary, in: Capsule())
            .modifier(DSPressFeedback(isPressed: configuration.isPressed))
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { DSSecondaryButtonStyle() }
}

/// A round 44 pt icon button. `primary` is for a screen's main action in the header, such as "+".
struct DSIconButton: View {
    enum Prominence { case secondary, primary }

    let systemImage: String
    /// What VoiceOver reads; an icon alone says nothing.
    let label: String
    var prominence: Prominence = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(prominence == .primary ? DSColor.onAccent : DSColor.textPrimary)
                .frame(width: DSSize.touchTarget, height: DSSize.touchTarget)
                .background(prominence == .primary ? DSColor.accent : DSColor.surfaceSecondary, in: Circle())
        }
        .buttonStyle(DSPlainPressStyle())
        .accessibilityLabel(label)
    }
}

/// Pressed and disabled read the same on every button of the system.
struct DSPressFeedback: ViewModifier {
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .opacity(isEnabled ? (isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

struct DSPlainPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(DSPressFeedback(isPressed: configuration.isPressed))
    }
}
