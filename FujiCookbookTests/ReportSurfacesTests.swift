import XCTest
@testable import FujiCookbook

/// Darkslide doesn't collect reports yet (`FeatureFlags.reportsEnabled`). These pin what the app
/// shows with reports off and on, and that the shipping configuration is off.
final class ReportSurfacesTests: XCTestCase {
    func testReportsStayHiddenUntilDarkslideCollectsThem() {
        XCTAssertFalse(
            FeatureFlags.reportsEnabled,
            """
            Reports are enabled. docs/privacy-policy.md says Darkslide doesn't collect reports or \
            feedback; update it in the same change, then delete this assertion.
            """)
        XCTAssertEqual(ReportSurfaces.current, ReportSurfaces(reportsEnabled: false))
    }

    func testWithReportsOffNothingOffersToSend() {
        let off = ReportSurfaces(reportsEnabled: false)
        XCTAssertFalse(off.showsSendFeedback)
        XCTAssertFalse(off.showsShareOnReport)
        XCTAssertFalse(off.showsReportPrompts)
        XCTAssertFalse(off.showsCameraTest)
    }

    func testWithReportsOffTheDiagnosticsReportStaysReadable() {
        let off = ReportSurfaces(reportsEnabled: false)
        XCTAssertEqual(off.diagnosticsTitle, "Diagnostics Report")
        XCTAssertEqual(off.unexpectedExitAction, "View Diagnostics")
        XCTAssertEqual(off.helpSectionTitle, "Help")
    }

    func testWithReportsOnEverySurfaceComesBack() {
        let on = ReportSurfaces(reportsEnabled: true)
        XCTAssertTrue(on.showsSendFeedback)
        XCTAssertTrue(on.showsShareOnReport)
        XCTAssertTrue(on.showsReportPrompts)
        XCTAssertTrue(on.showsCameraTest)
        XCTAssertEqual(on.diagnosticsTitle, "Report a Problem")
        XCTAssertEqual(on.unexpectedExitAction, "Report a Problem")
        XCTAssertEqual(on.helpSectionTitle, "Help & Feedback")
    }

    func testPrivacyPolicyLinkPointsAtThisRepository() {
        XCTAssertEqual(SettingsView.privacyPolicyURL.absoluteString,
                       "https://github.com/philippbev/darkslide/blob/main/docs/privacy-policy.md")
    }

    func testCameraErrorPointsAtTheDiagnosticsTheAppShows() {
        let off = CameraError.diagnosticsRoute(ReportSurfaces(reportsEnabled: false))
        XCTAssertEqual(off, "Copy the report from Settings → Help → Diagnostics Report")
        XCTAssertFalse(off.contains("Report a Problem"), "with reports off there is nothing to send")
        XCTAssertEqual(CameraError.diagnosticsRoute(ReportSurfaces(reportsEnabled: true)),
                       "Send a report from Settings → Help & Feedback → Report a Problem")
        XCTAssertTrue(CameraError.contentsAccessUnavailable.message
            .contains(CameraError.diagnosticsRoute(.current)))
    }
}
