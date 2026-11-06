import Foundation

/// The App Group `UserDefaults` suite, shared by the app and the Share Extension.
enum SharedDefaults {
    static let suite = UserDefaults(suiteName: ScreenshotInbox.appGroupID)

    /// Set by the extension after a save so the app knows to refetch on next foreground.
    static let libraryChangedKey = "shared.library.changedByExtension"
}

/// What the Share Extension needs to know to scan a screenshot and save the result.
///
/// A *mirror*, not a migration. `AISettings` keeps `UserDefaults.standard` as its source of truth
/// and republishes the handful of values the extension reads. One-directional by design: the
/// extension never writes here, so the two stores can't disagree about who wins.
///
/// The API key deliberately isn't in here. It stays in the Keychain, reached through
/// ``KeychainStore``'s shared access group; a secret mirrored into an App Group plist would be
/// plain text in a container any of this app's processes can read.
struct ScanConfiguration {
    let provider: AIProvider
    let modelID: String
    let isEnabled: Bool
    /// How the app actually opened the store this launch, so the extension can open it the *same*
    /// way. Both processes carry the iCloud container entitlement; what they must not do is
    /// disagree, because a process writing a CloudKit-mirrored store without mirroring of its own
    /// can produce rows the mirror never learns about.
    let icloudSyncEnabled: Bool

    /// The active provider's key, read straight from the shared Keychain item.
    var apiKey: String {
        (KeychainStore.get(provider.keychainAccount) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Scanning is set up end to end. Mirrors `AISettings.isConfigured`, which is the app-side
    /// answer to the same question.
    var isConfigured: Bool { isEnabled && !apiKey.isEmpty && !modelID.isEmpty }

    // MARK: Reading

    /// The published snapshot, or nil before the app has ever run and written one — which the
    /// extension treats exactly like "not configured".
    static func current() -> ScanConfiguration? {
        guard let defaults = SharedDefaults.suite,
              defaults.object(forKey: Keys.isEnabled) != nil else { return nil }
        return ScanConfiguration(
            provider: AIProvider.named(defaults.string(forKey: Keys.provider)),
            modelID: defaults.string(forKey: Keys.modelID) ?? "",
            isEnabled: defaults.bool(forKey: Keys.isEnabled),
            icloudSyncEnabled: defaults.bool(forKey: Keys.icloudSync))
    }

    // MARK: Writing (app only)

    /// Republish the AI settings. Called from `AISettings` on init and whenever one of these changes.
    static func publish(provider: AIProvider, modelID: String, isEnabled: Bool) {
        guard let defaults = SharedDefaults.suite else { return }
        defaults.set(provider.rawValue, forKey: Keys.provider)
        defaults.set(modelID, forKey: Keys.modelID)
        defaults.set(isEnabled, forKey: Keys.isEnabled)
    }

    /// Record how the store was actually opened this launch.
    ///
    /// Published from the app *after* the container is created, with the configuration that was
    /// really used rather than the preference that was asked for — the two differ when the user has
    /// just toggled sync (the store keeps its old configuration until the next launch) and when a
    /// CloudKit store couldn't be opened and the app fell back to local. The extension has to match
    /// the store as it exists, not as it was intended.
    static func publishStoreMode(cloudKit: Bool) {
        SharedDefaults.suite?.set(cloudKit, forKey: Keys.icloudSync)
    }

    private enum Keys {
        static let provider = "shared.ai.provider"
        static let modelID = "shared.ai.scanning.modelID"
        static let isEnabled = "shared.ai.enabled"
        static let icloudSync = "shared.icloud.sync.enabled"
    }
}
