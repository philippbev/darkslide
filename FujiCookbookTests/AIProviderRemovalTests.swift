import XCTest
@testable import FujiCookbook

/// Google/Gemini isn't offered as a provider because of its API terms.
///
/// Removing an enum case is the easy half. The hard half is that every deletion path in the app
/// walks `AIProvider.allCases`, so a credential belonging to a case that no longer exists is
/// unreachable by design — it cannot be listed, cannot be deleted by the user, and survives an
/// uninstall. These lock down both halves.
final class AIProviderRemovalTests: XCTestCase {
    func testGoogleIsNotAnOfferedProvider() {
        XCTAssertEqual(Set(AIProvider.allCases.map(\.rawValue)), ["anthropic", "openai"],
                       "reinstating a provider is a terms question first — read the doc above")
    }

    /// An install that had Gemini selected has `"google"` sitting in UserDefaults.
    func testAStoredGoogleSelectionFallsBackInsteadOfFailing() {
        XCTAssertEqual(AIProvider.named("google"), .anthropic,
                       "a retired raw value must degrade, not crash or resolve to nothing")
    }

    func testNoRemainingProviderClaimsTheRetiredKeychainAccount() {
        XCTAssertFalse(AIProvider.allCases.map(\.keychainAccount).contains("google.apiKey"),
                       "the retired account is purged, never re-used — reusing it would hand one "
                       + "provider a key the user pasted for another")
    }

    /// The purge is called at launch and must be safe to run repeatedly on a device that never had
    /// a Google key — that is the ordinary case, and it is the reason there is no "migrated" flag.
    func testPurgingRetiredProviderDataIsIdempotentAndSafeWhenAbsent() {
        AISettings.purgeRetiredProviderData()

        let keys = ["ai.scanning.modelID.google", "ai.recommender.modelID.google", "ai.models.google"]
        for key in keys { UserDefaults.standard.set("stale", forKey: key) }
        AISettings.purgeRetiredProviderData()
        AISettings.purgeRetiredProviderData()

        for key in keys {
            XCTAssertNil(UserDefaults.standard.object(forKey: key), "\(key) should be gone")
        }
    }

    /// The whole reason the purge exists, exercised end to end against the real Keychain.
    ///
    /// Step 2 is the interesting assertion: it demonstrates the stranded state is genuinely
    /// reachable *only* by the literal account string. Nothing that walks `AIProvider.allCases`
    /// can see this item, which is why deleting the enum case without this purge would have left
    /// a user's key on the device with no control able to remove it.
    func testAKeyLeftBehindByTheRetiredProviderIsActuallyDeleted() throws {
        KeychainStore.set("planted-google-key", for: "google.apiKey")
        try XCTSkipIf(KeychainStore.get("google.apiKey") == nil,
                      "Keychain unavailable to the test host; nothing to verify")

        XCTAssertFalse(AIProvider.allCases.contains { KeychainStore.get($0.keychainAccount) == "planted-google-key" },
                       "no offered provider can reach it — that is the trap being closed")

        AISettings.purgeRetiredProviderData()

        XCTAssertNil(KeychainStore.get("google.apiKey"),
                     "a credential for a provider the app no longer offers must not survive the removal")
    }

    func testThePurgeRemovesAStoredGoogleModelChoice() {
        UserDefaults.standard.set("gemini-1.5-pro", forKey: "ai.scanning.modelID.google")

        AISettings.purgeRetiredProviderData()

        XCTAssertNil(UserDefaults.standard.object(forKey: "ai.scanning.modelID.google"),
                     "a model choice for a retired provider has nothing left that could reach it")
    }
}
