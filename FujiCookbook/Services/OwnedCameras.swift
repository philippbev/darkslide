import Foundation
import Observation

/// The registry bodies the user owns: first on each recipe's Works With card, and chips in the
/// Library's filter. Stored as model ids in the standard `UserDefaults` suite, not the App Group
/// one: the Share Extension never reads them.
///
/// Two ways in: the user ticks bodies in Settings ▸ My Cameras, and a camera that connects with a
/// trusted identification adds itself (`noteConnected`). A removal holds until that body next
/// connects.
@MainActor @Observable
final class OwnedCameras {
    static let key = "camera.owned.modelIDs"

    /// In the order they were added. Only ids the registry knows, never the Demo Camera, no
    /// duplicates: the load sanitises a stored list the way `add` guards a new entry.
    private(set) var modelIDs: [CameraModel.ID]

    @ObservationIgnored private let registry: CameraModelRegistry
    @ObservationIgnored private let defaults: UserDefaults

    init(registry: CameraModelRegistry = .shared, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.defaults = defaults
        var seen = Set<CameraModel.ID>()
        modelIDs = (defaults.stringArray(forKey: Self.key) ?? []).filter { id in
            Self.isSelectable(id, in: registry) && seen.insert(id).inserted
        }
    }

    /// The owned bodies, resolved, in insertion order.
    var models: [CameraModel] { modelIDs.compactMap { registry.model(withID: $0) } }

    /// What the user may pick: every registry body but the Demo Camera, in registry order.
    var selectable: [CameraModel] {
        registry.models.filter { $0.id != CameraModelRegistry.demoModelID }
    }

    func contains(_ id: CameraModel.ID) -> Bool { modelIDs.contains(id) }

    /// Adds a body. A no-op for the Demo Camera, an id the registry doesn't know, or one already here.
    func add(_ id: CameraModel.ID) {
        guard Self.isSelectable(id, in: registry), !modelIDs.contains(id) else { return }
        modelIDs.append(id)
        save()
    }

    func remove(_ id: CameraModel.ID) {
        guard let index = modelIDs.firstIndex(of: id) else { return }
        modelIDs.remove(at: index)
        save()
    }

    /// A camera on the cable with a trusted identification — exact or alias — is one the user
    /// owns, read-only bodies included. A name-pattern guess is not, and neither is the Demo
    /// Camera, even when a faulted demo wears a real body's name (`ConnectedCamera.isDemo`).
    func noteConnected(_ camera: ConnectedCamera) {
        guard camera.identification.isTrusted, !camera.isDemo, let model = camera.model else { return }
        add(model.id)
    }

    private static func isSelectable(_ id: CameraModel.ID, in registry: CameraModelRegistry) -> Bool {
        id != CameraModelRegistry.demoModelID && registry.model(withID: id) != nil
    }

    private func save() { defaults.set(modelIDs, forKey: Self.key) }
}
