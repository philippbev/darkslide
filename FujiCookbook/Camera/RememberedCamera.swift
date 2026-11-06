import Foundation

/// The last camera the app could push to, and how many custom slots its connect walk found.
///
/// A Chapter holds up to seven recipes, and a body may have four or six banks (`documentedSlotCount`),
/// so a chapter can hold recipes a push leaves behind. The push screen knows the count from the
/// connected body; this is what lets the Chapter screen say it with no camera plugged in. It is the
/// latest walk's answer for one body, not a fact about a model, and every push-capable connect
/// replaces it.
///
/// Only a body the app writes to is remembered: a chapter's fit matters only where it can be pushed,
/// and the Demo Camera is nobody's camera.
struct RememberedCamera: Equatable {
    let displayName: String
    let slotCount: Int

    /// UserDefaults keys. Views read them with `@AppStorage`, so a connect updates an open Chapter.
    static let displayNameKey = "camera.remembered.displayName"
    static let slotCountKey = "camera.remembered.slotCount"

    /// Nil for a name or count there is nothing to say about — the `@AppStorage` defaults included.
    init?(displayName: String, slotCount: Int) {
        guard !displayName.isEmpty, slotCount > 0 else { return nil }
        self.displayName = displayName
        self.slotCount = slotCount
    }

    /// What `save(to:)` last wrote; nil before any push-capable connect.
    init?(defaults: UserDefaults) {
        self.init(displayName: defaults.string(forKey: Self.displayNameKey) ?? "",
                  slotCount: defaults.integer(forKey: Self.slotCountKey))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(displayName, forKey: Self.displayNameKey)
        defaults.set(slotCount, forKey: Self.slotCountKey)
    }
}
