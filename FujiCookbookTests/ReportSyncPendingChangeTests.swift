import XCTest
@testable import FujiCookbook

/// A changed sync preference applies at the next launch, so when the preference and the running
/// store differ the report's Sync line says the change is pending, not that the store fell back.
@MainActor
final class ReportSyncPendingChangeTests: XCTestCase {
    func testTurnedOnBeforeARestartIsPendingNotAFallback() {
        let sync = DiagnosticsReportView.syncDescription(syncEnabled: true, cloudStoreState: .local)

        XCTAssertEqual(sync, "on from next launch — local this launch")
    }

    func testTurnedOffBeforeARestartIsPending() {
        let sync = DiagnosticsReportView.syncDescription(syncEnabled: false, cloudStoreState: .cloudKit)

        XCTAssertEqual(sync, "off from next launch — iCloud this launch")
    }

    func testAnUnchangedPreferenceReadsPlainly() {
        XCTAssertEqual(DiagnosticsReportView.syncDescription(syncEnabled: true, cloudStoreState: .cloudKit), "on")
        XCTAssertEqual(DiagnosticsReportView.syncDescription(syncEnabled: false, cloudStoreState: .local), "off")
    }
}
