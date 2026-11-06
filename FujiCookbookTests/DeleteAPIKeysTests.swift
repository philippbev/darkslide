import XCTest
@testable import FujiCookbook

/// Delete API Keys promises the stored keys and model choices are gone, and `AISettings.init`
/// seeds the Anthropic model slot from the pre-provider keys whenever that slot is empty. Leaving
/// those keys behind handed the deleted model choice back on the next launch.
@MainActor
final class DeleteAPIKeysTests: XCTestCase {
    private let legacyScanning = "ai.scanning.modelID"
    private let legacyRecommender = "ai.recommender.modelID"
    private let anthropicScanning = "ai.scanning.modelID.anthropic"
    private let anthropicRecommender = "ai.recommender.modelID.anthropic"

    override func tearDown() {
        for key in [legacyScanning, legacyRecommender, anthropicScanning, anthropicRecommender] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testAPreProviderModelChoiceDoesNotComeBackAfterDeletion() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: anthropicScanning)
        defaults.removeObject(forKey: anthropicRecommender)
        defaults.set("legacy-scan-model", forKey: legacyScanning)
        defaults.set("legacy-ideas-model", forKey: legacyRecommender)

        let settings = AISettings()
        XCTAssertEqual(defaults.string(forKey: anthropicScanning), "legacy-scan-model",
                       "precondition: an upgrading install is seeded from the pre-provider key")

        settings.deleteAllCredentials()
        XCTAssertNil(defaults.string(forKey: legacyScanning))
        XCTAssertNil(defaults.string(forKey: legacyRecommender))

        // The next launch.
        _ = AISettings()
        XCTAssertNil(defaults.string(forKey: anthropicScanning), "the deleted scanning model stays deleted")
        XCTAssertNil(defaults.string(forKey: anthropicRecommender), "and so does the Ideas model")
    }
}
