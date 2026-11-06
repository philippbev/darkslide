import XCTest
@testable import FujiCookbook

/// The identifiers come from build settings rather than literals, so these pin how they relate to
/// each other instead of their values — which is what lets a fork with its own base pass them too.
final class AppIdentifiersTests: XCTestCase {
    func testTheBaseIsTheAppsBundleIdentifier() {
        XCTAssertEqual(AppIdentifiers.base, Bundle.main.bundleIdentifier)
    }

    func testTheAppGroupIsDerivedFromTheBase() {
        XCTAssertEqual(AppIdentifiers.appGroup, "group." + AppIdentifiers.base)
    }

    func testTheLogSubsystemFollowsTheBundleIdentifier() {
        XCTAssertEqual(AppLog.subsystem, AppIdentifiers.base)
    }
}
