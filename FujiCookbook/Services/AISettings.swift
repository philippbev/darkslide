import Foundation
import Observation

/// User-configurable settings for the app's optional AI features.
///
/// Two storage tiers, chosen by what the data is:
/// - **Keychain, device-local** — the API keys (``KeychainStore``). One per provider, all kept at
///   once so switching providers never costs the user a re-paste.
/// - **`UserDefaults`, device-local** — everything else: the on/off flag, the selected provider,
///   and the per-provider model choices.
///
/// **Nothing in here syncs, by design.** The on/off flag and the model choices all hang off the
/// one thing that is device-local and must stay that way — the API key. A synced provider would
/// point another device at a vendor it has no key for; a synced model id names a model that key
/// can't reach; a synced "AI is on" leaves a switch reading on over a provider that can't answer.
/// So the whole AI section is configured per device.
///
/// Injected app-wide so the Library import menu and the Settings screen share one source of truth.
@Observable
final class AISettings {
    /// The master switch for every AI feature. Off by default: this is the one feature that sends
    /// the user's content to a third party.
    ///
    /// Stored under `ai.scanning.enabled`, the key from when scanning was the only AI feature;
    /// keeping it carries existing installs' choice over without a migration.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            publishSharedSnapshot()
        }
    }

    /// When the user accepted the AI disclosure, the alert Settings presents before the Enable AI
    /// Features switch turns on. A record of that consent: nothing in the app reads it back, and
    /// Delete API Keys leaves it in place. Device-local like the rest of this type, and necessarily
    /// so: consent given on one device must not appear on another as consent nobody gave there.
    static let disclosureAcknowledgedDateKey = "ai.disclosureAcknowledgedDate"

    /// Which vendor both AI features talk to.
    var provider: AIProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: Keys.provider)
            publishSharedSnapshot()
        }
    }

    // MARK: API keys

    // One stored property per provider rather than a single value swapped on provider change.
    // That is a safety property, not a style preference: `KeychainStore.set("")` *deletes* the
    // item, so with one swapped property the didSet ordering decides whether the outgoing
    // provider's key is written or erased. Split like this, that failure is not expressible.

    var anthropicKey: String {
        didSet { KeychainStore.set(anthropicKey, for: AIProvider.anthropic.keychainAccount) }
    }

    var openAIKey: String {
        didSet { KeychainStore.set(openAIKey, for: AIProvider.openai.keychainAccount) }
    }

    /// The active provider's key. Computed, so it cannot drift out of step with `provider`.
    var apiKey: String {
        get { key(for: provider) }
        set { setKey(newValue, for: provider) }
    }

    func key(for provider: AIProvider) -> String {
        switch provider {
        case .anthropic: return anthropicKey
        case .openai: return openAIKey
        }
    }

    func setKey(_ value: String, for provider: AIProvider) {
        switch provider {
        case .anthropic: anthropicKey = value
        case .openai: openAIKey = value
        }
    }

    /// True when the active provider has a non-blank key.
    var hasAPIKey: Bool { !trimmedKey.isEmpty }

    /// True when scanning is set up end to end: switched on, a key present, and a model chosen.
    /// The model has to be part of this — model ids come from the provider's own list rather than
    /// a built-in default (see ``AIModelCatalog``), so "key but no model yet" is a real state a
    /// new user passes through, not a should-never-happen.
    var isConfigured: Bool { isEnabled && hasAPIKey && hasScanningModel }

    /// True when the recommender has everything it needs. Ideas has no switch of its own — it
    /// only ever runs when the user opens the tab and asks, so the master toggle is the only
    /// gate it needs.
    var canRecommend: Bool { isEnabled && hasAPIKey && hasRecommenderModel }

    var hasScanningModel: Bool { !modelID.isEmpty }
    var hasRecommenderModel: Bool { !recommenderModelID.isEmpty }

    /// The key as it goes on the wire. Trims newlines too: a pasted key often ends in one, and a
    /// newline is invalid in an HTTP header value.
    var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Providers with a key stored on this device, whichever one is currently selected.
    ///
    /// Deliberately not scoped to `provider`: keys are kept per provider so switching back and
    /// forth doesn't lose one, which means a user can have a key stored for a provider the picker
    /// isn't showing. A deletion control has to reach every stored key, not just the selected
    /// provider's, or it leaves one behind and reports success.
    var storedKeyProviders: [AIProvider] {
        AIProvider.allCases.filter { !key(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var hasAnyStoredKey: Bool { !storedKeyProviders.isEmpty }

    /// Delete the Keychain item and defaults left by Google/Gemini, a provider this app no longer
    /// offers.
    ///
    /// Every other deletion path, ``deleteAllCredentials()`` included, walks `AIProvider.allCases`,
    /// so without this a stored Google key would sit in the Keychain where no control can reach
    /// it, and Keychain items survive an uninstall.
    ///
    /// Idempotent, like the pre-provider model seed in `init`: deleting an absent Keychain item or
    /// default is a no-op, so this runs on every launch with no "migrated" flag to keep true.
    /// Called from `FujiCookbookApp.init`.
    static func purgeRetiredProviderData() {
        // Literals, not `AIProvider` members — the whole point is that these no longer exist as
        // cases. They are the exact strings the removed `.google` case returned.
        KeychainStore.set("", for: "google.apiKey")
        for key in ["ai.scanning.modelID.google", "ai.recommender.modelID.google", "ai.models.google"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Erase every stored API key, model choice, and cached model list.
    ///
    /// Turning AI off is not deletion: the switch stops future requests and deliberately keeps the
    /// setup. This is how a user who wants the secret *gone* says so. Leaves `isEnabled` and the
    /// disclosure-acknowledgment date alone — the first is the user's own switch to hold, and the
    /// second is the record that consent was given, not a credential.
    func deleteAllCredentials() {
        for provider in AIProvider.allCases {
            // An empty key deletes the Keychain item.
            setKey("", for: provider)
            defaults.removeObject(forKey: Keys.scanningModel(provider))
            defaults.removeObject(forKey: Keys.recommenderModel(provider))
        }
        // The pre-provider keys too: `init` seeds the Anthropic slot from them whenever it is
        // empty, so leaving them would hand the deleted model choice back on the next launch.
        defaults.removeObject(forKey: Keys.legacyScanningModel)
        defaults.removeObject(forKey: Keys.legacyRecommenderModel)
        // `persist` skips absent entries, so emptying the dictionaries alone would leave the
        // defaults keys behind. They are removed above; these keep memory in step.
        scanningModels = [:]
        recommenderModels = [:]

        AIModelCatalog.forgetAll()
        publishSharedSnapshot()
        AppLog.info(.ai, "AI credentials deleted at the user's request")
    }

    // MARK: Model selection

    /// Selected model for screenshot scanning with the current provider.
    ///
    /// Empty until one is chosen. There is no hardcoded fallback on purpose: a built-in id that the
    /// provider has since retired would look like a working setting and fail only on first use, so
    /// Settings fills this in from the provider's own list instead (see ``AIModelCatalog``).
    var modelID: String {
        get { scanningModels[provider.rawValue] ?? "" }
        set { scanningModels[provider.rawValue] = newValue }
    }

    /// Selected model for the recipe recommender. Independent of the scanning model — scanning
    /// leans on vision, recommendations on reasoning, so the cost/quality sweet spots differ.
    var recommenderModelID: String {
        get { recommenderModels[provider.rawValue] ?? "" }
        set { recommenderModels[provider.rawValue] = newValue }
    }

    private var scanningModels: [String: String] {
        didSet {
            persist(scanningModels, under: Keys.scanningModel)
            publishSharedSnapshot()
        }
    }

    private var recommenderModels: [String: String] {
        didSet {
            persist(recommenderModels, under: Keys.recommenderModel)
        }
    }

    // MARK: Storage keys

    private enum Keys {
        static let enabled = "ai.scanning.enabled"
        static let provider = "ai.provider"

        static func scanningModel(_ provider: AIProvider) -> String {
            "ai.scanning.modelID.\(provider.rawValue)"
        }

        static func recommenderModel(_ provider: AIProvider) -> String {
            "ai.recommender.modelID.\(provider.rawValue)"
        }

        // Pre-provider keys, from when the app only ever spoke to Anthropic. Read once to seed
        // the Anthropic slot on an upgrading install (see `init`); never written. A build that
        // wrote them too would hand a pre-provider build a model id for whichever vendor was
        // picked last — an OpenAI id arriving at api.anthropic.com, 404ing on every scan with
        // nothing on screen to explain it.
        static let legacyScanningModel = "ai.scanning.modelID"
        static let legacyRecommenderModel = "ai.recommender.modelID"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard

        isEnabled = defaults.bool(forKey: Keys.enabled)
        provider = AIProvider.named(defaults.string(forKey: Keys.provider))

        anthropicKey = KeychainStore.get(AIProvider.anthropic.keychainAccount) ?? ""
        openAIKey = KeychainStore.get(AIProvider.openai.keychainAccount) ?? ""

        var scanning: [String: String] = [:]
        var recommender: [String: String] = [:]
        for provider in AIProvider.allCases {
            scanning[provider.rawValue] = defaults.string(forKey: Keys.scanningModel(provider))
            recommender[provider.rawValue] = defaults.string(forKey: Keys.recommenderModel(provider))
        }

        // One-way seed from the pre-provider keys, triggered by absence rather than a "migrated"
        // flag: absence is idempotent, so the seed is safe to re-evaluate on every launch and
        // there is no second piece of state to keep true.
        let anthropic = AIProvider.anthropic.rawValue
        if scanning[anthropic] == nil, let legacy = defaults.string(forKey: Keys.legacyScanningModel) {
            scanning[anthropic] = legacy
            defaults.set(legacy, forKey: Keys.scanningModel(.anthropic))
        }
        if recommender[anthropic] == nil,
           let legacy = defaults.string(forKey: Keys.legacyRecommenderModel) {
            recommender[anthropic] = legacy
            defaults.set(legacy, forKey: Keys.recommenderModel(.anthropic))
        }

        // Observers don't run during init, so these assignments neither persist nor publish. The
        // publish below writes the Share Extension's snapshot, which an install may not have yet.
        scanningModels = scanning
        recommenderModels = recommender

        publishSharedSnapshot()
    }

    /// Mirror the settings the Share Extension reads into the App Group suite. See
    /// ``ScanConfiguration`` for why this is a mirror rather than a move.
    private func publishSharedSnapshot() {
        ScanConfiguration.publish(provider: provider, modelID: modelID, isEnabled: isEnabled)
    }

    private func persist(_ models: [String: String], under key: (AIProvider) -> String) {
        for provider in AIProvider.allCases {
            guard let value = models[provider.rawValue] else { continue }
            defaults.set(value, forKey: key(provider))
        }
    }
}
