import SwiftUI

/// A toggle drawn as a square hardware switch: 56 × 32, a signal-blue knob on the right when on, a
/// white knob on the left when off. Keeps the `Toggle`'s label, role and accessibility.
///
/// `.labelsHidden()` doesn't reach a custom toggle style, so a switch that sits beside its own
/// title (in a device panel, say) uses `.dsHardwareSwitchOnly`, which shows the track alone and
/// still gives VoiceOver the label.
struct DSHardwareSwitchStyle: ToggleStyle {
    var showsLabel = true

    func makeBody(configuration: Configuration) -> some View {
        DSHardwareSwitchBody(configuration: configuration, showsLabel: showsLabel)
    }
}

private struct DSHardwareSwitchBody: View {
    let configuration: ToggleStyleConfiguration
    let showsLabel: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var isOn: Bool { configuration.isOn }

    var body: some View {
        HStack {
            if showsLabel {
                configuration.label
                Spacer(minLength: DSSpacing.s)
            }
            track
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        .opacity(isEnabled ? 1 : 0.45)
        // VoiceOver gets a system switch with the label, shown or not, its value and its action.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private var track: some View {
        RoundedRectangle(cornerRadius: DSRadius.switchTrack, style: .continuous)
            // On, the track is the text color, so it reads against the ground in both modes.
            .fill(isOn ? DSColor.textPrimary : DSColor.ledOff)
            .frame(width: DSSize.switchSize.width, height: DSSize.switchSize.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: DSRadius.switchKnob, style: .continuous)
                    .fill(isOn ? DSColor.signal : DSColor.onSignal)
                    .frame(width: DSSize.switchKnob, height: DSSize.switchKnob)
                    .padding((DSSize.switchSize.height - DSSize.switchKnob) / 2)
            }
            .animation(.easeOut(duration: 0.12), value: isOn)
            .frame(minHeight: DSSize.touchTarget)
    }
}

extension ToggleStyle where Self == DSHardwareSwitchStyle {
    static var dsHardware: DSHardwareSwitchStyle { DSHardwareSwitchStyle() }
    /// The track alone, for a switch whose title stands beside it.
    static var dsHardwareSwitchOnly: DSHardwareSwitchStyle { DSHardwareSwitchStyle(showsLabel: false) }
}

#Preview("Switch") {
    struct Demo: View {
        @State private var on = true
        @State private var off = false
        var body: some View {
            VStack(spacing: DSSpacing.m) {
                Toggle("Location from Track", isOn: $on).toggleStyle(.dsHardware)
                Toggle("Only New", isOn: $off).toggleStyle(.dsHardware)
                Toggle("Disabled", isOn: .constant(true)).toggleStyle(.dsHardware).disabled(true)
            }
            .foregroundStyle(DSColor.textPrimary)
            .padding()
            .background(DSColor.background)
        }
    }
    return Demo()
}
