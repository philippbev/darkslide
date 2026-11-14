import SwiftUI

/// The panel of the instrument: a device or source and its state. The name in heavy type, a mono
/// line under it ("FW 1.31   USB   RAW CONV. MODE"), and on the right whatever reports the state,
/// usually LEDs with labels, or a switch.
struct DSDevicePanel<Trailing: View>: View {
    let title: String
    let meta: String
    @ViewBuilder var trailing: Trailing

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DSRadius.panel, style: .continuous) }

    var body: some View {
        HStack(alignment: .center, spacing: DSSpacing.m) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                DSPanelTitle(text: title)
                Text(meta).dsMetaMono()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(DSSpacing.l)
        .background(shape.fill(DSColor.panel))
        // The fine light edge along the top.
        .overlay(alignment: .top) {
            shape.stroke(DSColor.panelEdge, lineWidth: 1)
                .mask(alignment: .top) { Rectangle().frame(height: DSRadius.panel) }
        }
    }
}

/// The panel's name: 20 pt heavy, following Dynamic Type.
private struct DSPanelTitle: View {
    let text: String
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 20

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(DSColor.textPrimary)
            .lineLimit(2)
    }
}

/// The LEDs a panel shows on its right, stacked.
struct DSPanelLEDs: View {
    let indicators: [(label: String, isOn: Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            ForEach(Array(indicators.enumerated()), id: \.offset) { _, indicator in
                DSLEDIndicator(label: indicator.label, isOn: indicator.isOn)
            }
        }
    }
}

#Preview("Device panel") {
    VStack(spacing: DSSpacing.l) {
        DSDevicePanel(title: "X100VI", meta: "FW 1.31   USB   RAW Conv. Mode") {
            DSPanelLEDs(indicators: [("Link", true), ("R/W", false)])
        }
        DSDevicePanel(title: "Location from Track", meta: "12 of 40 located") {
            Toggle("Location", isOn: .constant(true)).toggleStyle(.dsHardwareSwitchOnly)
        }
    }
    .padding()
    .background(DSColor.background)
}
