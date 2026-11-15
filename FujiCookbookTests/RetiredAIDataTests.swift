import XCTest
@testable import FujiCookbook

/// AI scanning, the Share Extension and Ideas are gone, and nothing reads what they stored. The
/// launch cleanup is the only thing that can still reach it, so these pin that it does — against
/// the real Keychain, since a stored API key is the reason the cleanup exists.
final class RetiredAIDataTests: XCTestCase {
    private var standard: UserDefaults!
    private var shared: UserDefaults!
    private var container: URL!
    private let standardSuite = "RetiredAIDataTests.standard"
    private let sharedSuite = "RetiredAIDataTests.shared"

    override func setUpWithError() throws {
        standard = UserDefaults(suiteName: standardSuite)
        shared = UserDefaults(suiteName: sharedSuite)
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetiredAIDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        standard.removePersistentDomain(forName: standardSuite)
        shared.removePersistentDomain(forName: sharedSuite)
        try? FileManager.default.removeItem(at: container)
        for account in RetiredAIData.keychainAccounts { KeychainStore.set("", for: account) }
    }

    private func purge() {
        RetiredAIData.purge(standard: standard, shared: shared, container: container)
    }

    func testStoredProviderKeysAreDeleted() throws {
        for account in RetiredAIData.keychainAccounts { KeychainStore.set("planted-\(account)", for: account) }
        try XCTSkipIf(KeychainStore.get("anthropic.apiKey") == nil,
                      "Keychain unavailable to the test host; nothing to verify")

        purge()

        for account in RetiredAIData.keychainAccounts {
            XCTAssertNil(KeychainStore.get(account), "\(account) must not outlive the feature")
        }
    }

    func testTheSerialHashSecretIsNotAnAccountTheCleanupTouches() {
        XCTAssertFalse(RetiredAIData.keychainAccounts.contains(SerialHash.keychainAccount),
                       "deleting it would make every camera the app has met a stranger")
    }

    func testAISettingsAndTheExtensionSnapshotAreDeleted() {
        let standardKeys = ["ai.scanning.enabled", "ai.provider", "ai.disclosureAcknowledgedDate",
                            "ai.scanning.modelID", "ai.recommender.modelID",
                            "ai.scanning.modelID.anthropic", "ai.recommender.modelID.openai",
                            "ai.models.openai", "ai.scanning.modelID.google"]
        for key in standardKeys { standard.set("stale", forKey: key) }
        for key in RetiredAIData.sharedDefaultsKeys { shared.set("stale", forKey: key) }

        purge()

        for key in standardKeys { XCTAssertNil(standard.object(forKey: key), "\(key) should be gone") }
        for key in RetiredAIData.sharedDefaultsKeys { XCTAssertNil(shared.object(forKey: key), "\(key) should be gone") }
    }

    /// The App Group suite still holds settings that are in use; only the extension's keys go.
    func testSettingsStillInUseAreKept() {
        shared.set("dark", forKey: AppearancePreference.key)
        standard.set(true, forKey: FujiCookbookApp.iCloudSyncKey)

        purge()

        XCTAssertEqual(shared.string(forKey: AppearancePreference.key), "dark")
        XCTAssertTrue(standard.bool(forKey: FujiCookbookApp.iCloudSyncKey))
    }

    func testQueuedScreenshotsAreDeletedAndTheRestOfTheContainerIsNot() throws {
        let inbox = container.appendingPathComponent(RetiredAIData.inboxFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: inbox.appendingPathComponent("screenshot-1700000000-abcd1234"))
        let logs = container.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        purge()

        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logs.path))
    }

    /// Runs on every launch, and on almost every one there is nothing left to delete.
    func testPurgingTwiceWithNothingStoredIsHarmless() {
        purge()
        purge()
        XCTAssertNil(standard.object(forKey: "ai.provider"))
    }
}
