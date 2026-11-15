import SwiftUI

/// Onboarding / help for physically connecting a camera: cable & adapter per
/// device generation, the required camera USB mode, and common failure modes.
struct ConnectionGuideView: View {
    var modelID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(CameraServices.self) private var camera
    @State private var selectedModelID: String?

    /// A manual choice only changes these help instructions. Live detection always takes priority.
    private var setupModelID: String? {
        camera.session.isConnected ? camera.session.connected?.registryModel?.id : selectedModelID ?? modelID
    }

    private var modelSelection: Binding<String> {
        Binding(get: {
            guard let id = setupModelID, !id.isEmpty else { return "" }
            return ["X-T30 III", "X-M5"].contains(id) ? id : "other"
        }, set: { selectedModelID = $0 })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("1. Cable & Adapter") {
                    guideRow("USB-C iPhone / iPad (iPhone 15 and later, recent iPads)",
                             "Use a USB-C–to–USB-C data cable. The cable that shipped with your camera is a safe choice.",
                             "cable.connector")
                    guideRow("Lightning iPhone (older)",
                             "Use an Apple Lightning to USB Camera Adapter (or a reputable Lightning-to-USB-C adapter) plus a data cable.",
                             "bolt.horizontal")
                }

                Section("2. Camera USB Mode") {
                    if !camera.session.isConnected {
                        Picker("Setup instructions for", selection: modelSelection) {
                            Text("Choose a camera (optional)").tag("")
                            Text("X-T30 III").tag("X-T30 III")
                            Text("X-M5").tag("X-M5")
                            Text("Another Fujifilm").tag("other")
                        }
                        Text("This only changes the instructions below. The app detects your camera when it connects.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    guideRow("Set the right mode",
                             CameraTestSetup.usbInstructions(modelID: setupModelID),
                             "camera")
                    if setupModelID == "X-M5" {
                        guideRow("Use a still-photo bank",
                                 "Set the Film Simulation dial to C. The mode dial's C1–C4 positions are separate; use a bank assigned to STILL in IQ → CUSTOM MODE SETTING.",
                                 "dial.medium")
                    }
                    guideRow("During a check",
                             "Use a charged battery and leave the USB cable connected until the operation finishes.",
                             "battery.75percent")
                }

                Section("3. If It Doesn't Connect") {
                    troubleshootRow("Nothing detected", "The cable may be charge-only, or an adapter may be unpowered/non-Apple. Swap to a known data cable.")
                    troubleshootRow("Detected but errors", "The camera is probably in the wrong USB mode. Re-check step 2 and reconnect.")
                    troubleshootRow("Permission prompt", "Allow both Camera and Files and Folders access when iOS asks. Both permissions are needed to communicate with the camera.")
                }

                if ReportSurfaces.current.showsCameraTest {
                    Section {
                        Label("Camera Test backs up your settings before checking grain or writing a recipe. You choose the slot for the test recipe.",
                              systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Connection Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func guideRow(_ title: String, _ detail: String, _ icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
    }

    private func troubleshootRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
