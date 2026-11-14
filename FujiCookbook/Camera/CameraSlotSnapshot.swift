import Foundation

/// The custom slots of a camera as the app last read them, kept so the Library can say what is in
/// the camera with no camera plugged in: the CAMERA field ("5/7") and the slot badge on a recipe.
///
/// Saved beside `RememberedCamera`, by the same rule: at the end of a slot walk on a body the app
/// writes to, never the Demo Camera. Kept per camera by display name, so a second body's read
/// doesn't erase the first's. Only reads; nothing here goes back to the camera.
struct CameraSlotSnapshot: Codable, Equatable {
    struct Slot: Codable, Equatable {
        let index: Int
        /// "C1".
        let label: String
        let isOccupied: Bool
        /// The on-camera name, when the slot has one.
        let name: String?
        let settings: RecipeSettings?
    }

    let cameraName: String
    let slotCount: Int
    let readAt: Date
    let slots: [Slot]

    var occupiedCount: Int { slots.filter(\.isOccupied).count }

    init(cameraName: String, slotCount: Int, readAt: Date, slots: [Slot]) {
        self.cameraName = cameraName
        self.slotCount = slotCount
        self.readAt = readAt
        self.slots = slots
    }

    init(cameraName: String, slotCount: Int, readAt: Date = Date(), reading slots: [CameraSlot]) {
        self.init(cameraName: cameraName, slotCount: slotCount, readAt: readAt,
                  slots: slots.map { Slot(index: $0.index, label: $0.label, isOccupied: $0.isOccupied,
                                          name: $0.resolvedName, settings: $0.settings) })
    }

    // MARK: Storage

    /// UserDefaults key of the JSON map from camera name to snapshot. The Library reads it with
    /// `@AppStorage`, so a slot read shows up there without a relaunch.
    static let storageKey = "camera.slotSnapshots"

    /// Every camera's snapshot, from the JSON the key holds. Empty for no or unreadable JSON.
    static func all(from json: String) -> [String: CameraSlotSnapshot] {
        guard let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: CameraSlotSnapshot].self, from: data) else { return [:] }
        return map
    }

    static func load(cameraName: String, from defaults: UserDefaults) -> CameraSlotSnapshot? {
        all(from: defaults.string(forKey: storageKey) ?? "")[cameraName]
    }

    /// Replaces this camera's snapshot and keeps the others.
    func save(to defaults: UserDefaults) {
        var map = Self.all(from: defaults.string(forKey: Self.storageKey) ?? "")
        map[cameraName] = self
        guard let data = try? JSONEncoder().encode(map), let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Self.storageKey)
    }

    // MARK: Recipes in the slots

    /// Which library recipe sits in which slot: an occupied slot belongs to the recipe whose
    /// settings match it exactly (`RecipeMatcher`). When several recipes match equally, the one
    /// whose camera name is the slot's name wins; with no such tie-breaker the slot gets no badge,
    /// rather than one on a guess.
    func slotLabels(for recipes: [Recipe]) -> [UUID: String] {
        var labels: [UUID: String] = [:]
        for slot in slots where slot.isOccupied {
            guard let settings = slot.settings else { continue }
            let result = RecipeMatcher.match(photo: settings, against: recipes)
            guard result.tier == .exact, let best = result.best else { continue }
            let tied = [best] + result.tiedWithBest
            let chosen: Recipe?
            if tied.count == 1 {
                chosen = best.recipe
            } else {
                let named = tied.filter { $0.recipe.effectiveCameraName == slot.name }
                chosen = named.count == 1 ? named[0].recipe : nil
            }
            // A recipe held in two slots shows the first.
            if let chosen, labels[chosen.uuid] == nil { labels[chosen.uuid] = slot.label }
        }
        return labels
    }
}

/// What the Library's CAMERA field says about the camera's slots.
struct LibraryCameraField: Equatable {
    /// "5/7", or "—" when no camera was ever read.
    let value: String
    /// Lit while the camera that was read is connected.
    let isLive: Bool
    /// "As of 14.11." while it isn't; nil when live or never read.
    let asOf: String?

    static let neverRead = LibraryCameraField(value: "—", isLive: false, asOf: nil)

    init(value: String, isLive: Bool, asOf: String?) {
        self.value = value
        self.isLive = isLive
        self.asOf = asOf
    }

    init(snapshot: CameraSlotSnapshot?, connectedCameraName: String?, calendar: Calendar = .current) {
        guard let snapshot else { self = .neverRead; return }
        let live = connectedCameraName == snapshot.cameraName
        let day = calendar.component(.day, from: snapshot.readAt)
        let month = calendar.component(.month, from: snapshot.readAt)
        self.init(value: "\(snapshot.occupiedCount)/\(snapshot.slotCount)",
                  isLive: live,
                  asOf: live ? nil : String(format: "As of %02d.%02d.", day, month))
    }
}
