import Foundation

/// Deletes what the removed AI features (screenshot scanning, the Share Extension, Ideas) left on
/// the device: the provider API keys in the Keychain, their settings in `UserDefaults`, the
/// snapshot mirrored into the App Group suite, and screenshots still waiting in the inbox folder.
///
/// Nothing in the app reads any of it any more, so without this a user's API key would sit in the
/// Keychain where no control can reach it, and Keychain items survive an uninstall.
///
/// Idempotent: deleting an absent item, default or folder is a no-op, so this runs on every launch
/// with no "done" flag to keep true. The names are literals because the types that owned them are
/// gone; they are the exact strings earlier builds wrote.
enum RetiredAIData {
    /// The Keychain accounts the provider keys were stored under, Google's included (a provider an
    /// earlier build offered and then dropped). Never `SerialHash.keychainAccount`.
    static let keychainAccounts = ["anthropic.apiKey", "openai.apiKey", "google.apiKey"]

    /// `UserDefaults.standard` keys: the switch, the provider, the consent date, the model choices
    /// per provider and from before providers existed, and the cached model lists.
    static let standardDefaultsKeys: [String] = {
        var keys = ["ai.scanning.enabled", "ai.provider", "ai.disclosureAcknowledgedDate",
                    "ai.scanning.modelID", "ai.recommender.modelID"]
        for provider in ["anthropic", "openai", "google"] {
            keys += ["ai.scanning.modelID.\(provider)", "ai.recommender.modelID.\(provider)",
                     "ai.models.\(provider)"]
        }
        return keys
    }()

    /// Keys in the App Group suite that only the Share Extension read or wrote.
    static let sharedDefaultsKeys = ["shared.ai.provider", "shared.ai.scanning.modelID", "shared.ai.enabled",
                                     "shared.icloud.sync.enabled", "shared.library.changedByExtension"]

    /// The folder in the App Group the Share Extension queued screenshots in.
    static let inboxFolderName = "ScreenshotInbox"

    /// Called from `FujiCookbookApp.init`. The parameters exist for tests.
    static func purge(standard: UserDefaults = .standard,
                      shared: UserDefaults? = SharedDefaults.suite,
                      container: URL? = SharedContainer.url) {
        for account in keychainAccounts where KeychainStore.get(account) != nil {
            // An empty value deletes the item, in every group the app can reach.
            KeychainStore.set("", for: account)
            AppLog.info(.app, "Deleted a stored AI provider key")
        }
        for key in standardDefaultsKeys { standard.removeObject(forKey: key) }
        for key in sharedDefaultsKeys { shared?.removeObject(forKey: key) }

        if let inbox = container?.appendingPathComponent(inboxFolderName, isDirectory: true),
           FileManager.default.fileExists(atPath: inbox.path) {
            do {
                try FileManager.default.removeItem(at: inbox)
                AppLog.info(.app, "Deleted the shared-screenshot inbox")
            } catch {
                AppLog.error(.app, "Deleting the shared-screenshot inbox failed — \(AppLog.bounded(error))")
            }
        }
    }
}
