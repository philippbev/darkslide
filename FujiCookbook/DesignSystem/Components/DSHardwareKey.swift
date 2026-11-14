import SwiftUI

/// A key on the instrument: rounded 14, `key` face, a hard shadow straight down. Active or pressed,
/// it turns signal blue and the shadow moves inside, as if the key were held down.
struct DSHardwareKeyStyle: ButtonStyle {
    enum Variant {
        /// 44 × 44, an SF Symbol.
        case icon
        /// 40 high, a mono label.
        case text
        /// 52 high, full width, signal blue: one per screen.
        case primary
        /// 52 high, full width, on `key`.
        case secondary
    }

    var variant: Variant
    /// Latched on, such as the chapter that filters the list.
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        DSHardwareKeyBody(variant: variant,
                          isLit: isActive || variant == .primary,
                          isPressed: configuration.isPressed,
                          isDestructive: configuration.role == .destructive,
                          label: configuration.label)
    }
}

private struct DSHardwareKeyBody<Label: View>: View {
    let variant: DSHardwareKeyStyle.Variant
    let isLit: Bool
    let isPressed: Bool
    /// A `role: .destructive` button: its label in `danger` on an unlit key.
    let isDestructive: Bool
    let label: Label
    @Environment(\.isEnabled) private var isEnabled

    private var foreground: Color {
        if isLit { return DSColor.onSignal }
        return isDestructive ? DSColor.danger : DSColor.textPrimary
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DSRadius.key, style: .continuous) }
    /// A lit key sits down in its well; so does any key while a finger holds it.
    private var isDown: Bool { isPressed || (isLit && variant != .primary) }

    var body: some View {
        sized
            .foregroundStyle(foreground)
            .background(shape.fill(isLit ? DSColor.signal : DSColor.key))
            .overlay {
                if isDown {
                    // The inset shadow: a dark band along the top edge, inside the key.
                    shape.stroke(DSColor.keyInset, lineWidth: 4)
                        .offset(y: 2)
                        .clipShape(shape)
                }
            }
            .background(shape.fill(DSColor.keyShadow).offset(y: isDown ? 0 : DSSize.keyShadowOffset))
            .offset(y: isPressed ? DSSize.keyShadowOffset - 1 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    @ViewBuilder
    private var sized: some View {
        switch variant {
        case .icon:
            label
                .font(DSFont.headline)
                .frame(width: DSSize.iconKey, height: DSSize.iconKey)
        case .text:
            label
                .dsSmallMono(size: 13, weight: .semibold)
                .textCase(.uppercase)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.m)
                .frame(minHeight: DSSize.textKeyHeight)
        case .primary, .secondary:
            label
                .font(DSFont.headline)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.xl)
                .frame(maxWidth: .infinity, minHeight: DSSize.primaryKeyHeight)
        }
    }
}

extension ButtonStyle where Self == DSHardwareKeyStyle {
    /// The screen's one primary action.
    static var dsPrimary: DSHardwareKeyStyle { DSHardwareKeyStyle(variant: .primary) }
    /// The action beside or below the primary one.
    static var dsSecondary: DSHardwareKeyStyle { DSHardwareKeyStyle(variant: .secondary) }
    static func dsIconKey(isActive: Bool = false) -> DSHardwareKeyStyle {
        DSHardwareKeyStyle(variant: .icon, isActive: isActive)
    }
    static func dsTextKey(isActive: Bool = false) -> DSHardwareKeyStyle {
        DSHardwareKeyStyle(variant: .text, isActive: isActive)
    }
}

/// A 44 pt icon key, such as the filter key or "+" in a screen's header.
struct DSIconKey: View {
    let systemImage: String
    /// What VoiceOver reads; an icon alone says nothing.
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.dsIconKey(isActive: isActive))
        .accessibilityLabel(label)
    }
}

/// A text key with an LED: a chapter or a filter that is on or off. The LED repeats the state in a
/// second form besides the key's color.
struct DSTextKey: View {
    let label: String
    let isOn: Bool
    var showsLED = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.s) {
                if showsLED { DSLED(isOn: isOn, color: .onSignal, size: 6) }
                Text(label)
            }
        }
        .buttonStyle(.dsTextKey(isActive: isOn))
        // The key is 40 high; the touch target is still 44.
        .frame(minHeight: DSSize.touchTarget)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A row of keys that scrolls sideways and starts at the screen margin. Leaves room below the keys
/// for their shadow.
struct DSKeyRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.s) { content }
                .padding(.horizontal, DSSpacing.screenMargin)
                .padding(.bottom, DSSize.keyShadowOffset)
        }
    }
}

/// Pressed and disabled feedback for a tappable view that isn't a key.
struct DSPlainPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DSPlainPressBody(isPressed: configuration.isPressed, label: configuration.label)
    }
}

private struct DSPlainPressBody<Label: View>: View {
    let isPressed: Bool
    let label: Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .opacity(isEnabled ? (isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

#Preview("Keys") {
    VStack(spacing: DSSpacing.l) {
        HStack(spacing: DSSpacing.m) {
            DSIconKey(systemImage: "line.3.horizontal.decrease", label: "Filter") {}
            DSIconKey(systemImage: "plus", label: "New", isActive: true) {}
        }
        DSKeyRow {
            DSTextKey(label: "All", isOn: true) {}
            DSTextKey(label: "Street", isOn: false) {}
            DSTextKey(label: "Portrait", isOn: false) {}
        }
        Button("Load Recipe into C3") {}.buttonStyle(.dsPrimary)
        Button("Undo") {}.buttonStyle(.dsSecondary)
        Button("Delete", role: .destructive) {}.buttonStyle(.dsSecondary)
        Button("Disabled") {}.buttonStyle(.dsSecondary).disabled(true)
    }
    .padding()
    .background(DSColor.background)
}
