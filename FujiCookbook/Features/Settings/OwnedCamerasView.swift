import SwiftUI

/// Settings ▸ My Cameras: the bodies the user owns, ticked on and off. The Settings row's footer
/// says what the list drives; this screen only edits it.
struct OwnedCamerasView: View {
    @Environment(OwnedCameras.self) private var ownedCameras

    var body: some View {
        List {
            ForEach(SensorGeneration.settingsOrder, id: \.self) { generation in
                let bodies = ownedCameras.selectable.filter { $0.sensorGeneration == generation }
                if !bodies.isEmpty {
                    Section(generation.settingsTitle) {
                        ForEach(bodies) { row($0) }
                    }
                }
            }
        }
        .navigationTitle("My Cameras")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ model: CameraModel) -> some View {
        let owned = ownedCameras.contains(model.id)
        return Button {
            if owned { ownedCameras.remove(model.id) } else { ownedCameras.add(model.id) }
        } label: {
            HStack {
                Text(model.id)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                if owned {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(DSColor.signalText)
                }
            }
        }
        .accessibilityAddTraits(owned ? .isSelected : [])
    }
}

private extension SensorGeneration {
    /// Newest sensor first, GFX after the X series.
    static let settingsOrder: [SensorGeneration] = [.xTransV, .xTransIV, .xTransIII, .xTransII, .xTransI, .gfx, .other]

    var settingsTitle: String {
        switch self {
        case .xTransV: return "X-Trans V"
        case .xTransIV: return "X-Trans IV"
        case .xTransIII: return "X-Trans III"
        case .xTransII: return "X-Trans II"
        case .xTransI: return "X-Trans I"
        case .gfx: return "GFX"
        case .other: return "Other"
        }
    }
}
