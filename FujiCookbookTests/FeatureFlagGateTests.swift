import XCTest
@testable import FujiCookbook

/// Release gates for the build-time feature flags.
///
/// `FeatureFlags.ideasEnabled` carries a four-item privacy checklist in its own doc comment — the
/// privacy policy's AI section, the Settings ▸ AI Features copy, the App Store Connect privacy
/// answers, and `PrivacyInfo.xcprivacy` — because Ideas sends the user's shooting brief *and their
/// entire recipe library* to their AI provider, and no shipped privacy surface describes that
/// payload. Nothing enforced that checklist: the flag is one word, and flipping it is a
/// one-character diff that changes what leaves the device.
///
/// This is the enforcement. It is deliberately a failing test rather than a lint rule, so the
/// checklist arrives in front of whoever flips the flag, at the moment they flip it.
final class FeatureFlagGateTests: XCTestCase {
    func testIdeasStaysDisabledUntilItsPrivacySurfacesShip() {
        XCTAssertFalse(
            FeatureFlags.ideasEnabled,
            """
            Ideas is enabled. Before shipping this, update all four privacy surfaces named in \
            FeatureFlags.ideasEnabled's doc comment — Ideas sends the whole recipe library, and \
            the consent alert currently offers screenshot import as its only example. Then delete \
            this assertion in the same commit, so the gate never becomes a formality to silence.
            """)
    }
}
