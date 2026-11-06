import XCTest
@testable import FujiCookbook

/// A problem report leaves the device when the user shares it, so its Sync line names a CloudKit
/// fallback by domain and code only; Settings, on the device, keeps the full description.
@MainActor
final class CloudStoreFailureReportTests: XCTestCase {
    /// Made up: a description that quotes a container and an account, the kind of text the report
    /// must not carry. What a real store-creation failure's description holds is unverified.
    private let error = NSError(domain: "TestCloudStoreDomain", code: 7, userInfo: [
        NSLocalizedDescriptionKey: "Couldn't mirror iCloud.com.example.container for someone@example.com",
    ])

    func testReportNamesOnlyTheDomainAndCode() {
        let sync = DiagnosticsReportView.syncDescription(syncEnabled: true,
                                                         cloudStoreState: .fellBack(CloudStoreFailure(error)))

        XCTAssertEqual(sync, "on, but fell back to local — TestCloudStoreDomain 7")
        XCTAssertFalse(sync.contains("someone@example.com"))
    }

    func testSettingsKeepsTheFullDescription() {
        XCTAssertTrue(CloudStoreFailure(error).deviceOnlyDescription.contains("someone@example.com"))
    }
}
