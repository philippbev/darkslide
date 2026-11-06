import SwiftUI

/// Covers the screen while long work runs off the main actor: a dimmed backdrop that takes every
/// touch, what is being done, how far it has got, and Cancel. Import and export share it, so the
/// wait looks the same either way.
struct CancellableProgressOverlay: View {
    let title: String
    let detail: String?
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture {}
            VStack(spacing: 14) {
                ProgressView(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Button("Cancel", action: onCancel)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
