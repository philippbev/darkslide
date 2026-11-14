import SwiftUI

/// A status LED: a small circle, lit or dark.
struct DSLED: View {
    enum Light {
        /// Signal blue: something is on or selected.
        case signal
        /// Green: a connection is up.
        case ok
        /// White, for an LED that sits on a lit (blue) key.
        case onSignal
    }

    let isOn: Bool
    var color: Light = .signal
    /// 6 to 10 pt.
    var size: CGFloat = 8
    /// A soft halo around a lit LED.
    var glows = false

    private var lit: Color {
        switch color {
        case .signal: return DSColor.signal
        case .ok: return DSColor.ledOK
        case .onSignal: return DSColor.onSignal
        }
    }

    var body: some View {
        Circle()
            .fill(isOn ? lit : DSColor.ledOff)
            .frame(width: size, height: size)
            // The specification's glow: 8 pt at 70 %.
            .shadow(color: isOn && glows ? lit.opacity(0.7) : .clear, radius: 4)
            .accessibilityHidden(true)
    }
}

/// An LED with its mono label beside it, such as LINK or R/W on the device panel.
struct DSLEDIndicator: View {
    let label: String
    let isOn: Bool
    var color: DSLED.Light = .ok

    var body: some View {
        HStack(spacing: DSSpacing.xs + 2) {
            DSLED(isOn: isOn, color: color, size: 8, glows: true)
            Text(label).dsMetaMono()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(isOn ? "on" : "off")")
    }
}

#Preview("LEDs") {
    VStack(alignment: .leading, spacing: DSSpacing.m) {
        HStack(spacing: DSSpacing.m) {
            DSLED(isOn: true, size: 6)
            DSLED(isOn: true, glows: true)
            DSLED(isOn: true, color: .ok, size: 10, glows: true)
            DSLED(isOn: false, size: 10)
        }
        DSLEDIndicator(label: "Link", isOn: true)
        DSLEDIndicator(label: "R/W", isOn: false)
    }
    .padding()
    .background(DSColor.background)
}
