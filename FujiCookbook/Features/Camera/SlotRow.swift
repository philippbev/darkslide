import SwiftUI

/// One custom slot in a slot list — C-badge, on-camera name, film simulation: it shows what's
/// loaded.
struct SlotRow: View {
    let slot: CameraSlot

    var body: some View {
        HStack(spacing: 12) {
            Text(slot.label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(slot.isOccupied ? Theme.accent : Theme.ink3)
                .frame(width: 38, height: 38)
                .background(slot.isOccupied ? Theme.accentSoft : Theme.paper2,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                if slot.isOccupied {
                    Text(slot.resolvedName ?? "Unnamed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    // The film simulation alone: it is what tells slots apart at a glance, and the
                    // recipe summary's dynamic range only crowds the line.
                    if let sim = slot.settings?.filmSimulation {
                        Text(sim.displayName)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                    }
                    // The one place a divergent body announces itself. `SlotRow` is used by the
                    // Camera screen *and* by the import picker, so this flag reaches the tester at
                    // the moment they choose to import a recipe the app only partly read.
                    if !slot.unsupportedFields.isEmpty {
                        Label("\(slot.unsupportedFields.count) setting\(slot.unsupportedFields.count == 1 ? "" : "s") this app couldn't read",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                    }
                    // A setting the slot holds that no recipe carries — a Custom white balance is a
                    // measurement on this camera. Said as information, so an import of this slot
                    // doesn't look like it lost a white balance: nothing was misread.
                    ForEach(slot.cameraOnlyFields.sorted(by: { $0.key < $1.key }), id: \.key) { field, label in
                        Label("\(field): \(label) — set on the camera, not part of a recipe",
                              systemImage: "camera")
                            .font(.caption2)
                            .foregroundStyle(Theme.ink2)
                    }
                } else {
                    Text("Empty")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
