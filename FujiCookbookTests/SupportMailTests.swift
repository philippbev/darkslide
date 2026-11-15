import XCTest
@testable import FujiCookbook

/// Each report leaves as one attachment with a name that says what it is,
/// under a body line that says where it goes — and the log it quotes comes from the file.
@MainActor
final class SupportMailTests: XCTestCase {

    private func cameraReport() async -> CameraCompatibilityReport {
        var faults = MockCameraFaults.fiveSlots
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager.reports.report!
    }

    func testSupportAddressIsConfigured() {
        XCTAssertEqual(SupportContact.address, "hello@bevier.cloud")
    }

    func testProblemReportSharesTheTextNamedForTheCamera() async {
        let r = await cameraReport()
        let share = SupportMail.problemReport(text: "Darkslide — problem report\nApp 1.0\n" + r.textRendering, cameraReport: r)
        XCTAssertEqual(share.kind, .problem)
        XCTAssertTrue(share.fileName.hasPrefix("darkslide-problem-report-DEMO-"), share.fileName)
        XCTAssertTrue(share.fileName.hasSuffix(".txt"))
        XCTAssertEqual(share.mimeType, "text/plain")
        let text = String(decoding: share.data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("Darkslide — problem report"))
        XCTAssertTrue(text.contains("camera compatibility report v\(CameraCompatibilityReport.currentVersion)"), "the camera report rides inside the text")
        XCTAssertEqual(share.body, ShareableReport.body(for: SupportContact.address))

        let bare = SupportMail.problemReport(text: "x", cameraReport: nil)
        XCTAssertTrue(bare.fileName.hasPrefix("darkslide-problem-report-app-"), bare.fileName)
    }

    func testCurrentLaunchTextComesFromTheFileWhenThereIsOne() {
        let marker = "SupportMailTests marker \(UUID().uuidString)"
        AppLog.info(.camera, marker)
        let text = AppLog.currentLaunchText()
        XCTAssertTrue(text.contains(marker), "flushed and read back, or fallen back to the ring")
        // Clearing the screen must not clear the record a report reads.
        AppLog.clear(.camera)
        if CameraReportStore.latestURL != nil {
            XCTAssertTrue(AppLog.currentLaunchText().contains(marker), "Clear is screen-only")
        }
    }

    /// The `.txt` is what the tester reads; the JSON is what `MockCameraFaults` can be driven from
    /// and what two testers' reports diff against — including, since v2, the pre-push bytes of any
    /// slot a push changed.
    func testProblemReportAttachesTheCameraJSONToo() async throws {
        let r = await cameraReport()
        let share = SupportMail.problemReport(text: "x", cameraReport: r)

        XCTAssertEqual(share.extraFiles.count, 1)
        XCTAssertEqual(share.extraFiles.first?.fileName, r.suggestedFilename)
        XCTAssertTrue(r.suggestedFilename.hasPrefix("darkslide-camera-report-DEMO-"), r.suggestedFilename)
        XCTAssertTrue(r.suggestedFilename.hasSuffix(".json"))
        XCTAssertEqual(try CameraCompatibilityReport.decode(share.extraFiles[0].data).camera.productName,
                       r.camera.productName, "the attachment is the report itself, not a summary")
    }

    func testAProblemReportWithNoCameraAttachesNothing() {
        XCTAssertTrue(SupportMail.problemReport(text: "x", cameraReport: nil).extraFiles.isEmpty)
    }

    /// The body line first (Gmail flattens it), then the text report — Gmail names the mail after
    /// the first *file* — then the machine-readable copies.
    func testShareBundleCarriesEveryAttachmentInOrder() async throws {
        let r = await cameraReport()
        let items = try ShareBundle.items(for: SupportMail.problemReport(text: "x", cameraReport: r))

        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0] is MailTextItem)
        XCTAssertEqual((items[1] as? URL)?.pathExtension, "txt")
        XCTAssertEqual((items[2] as? URL)?.pathExtension, "json")
    }

    func testCameraTestResultsUseSuccessfulTestLanguageAndKeepCameraEvidence() async throws {
        let camera = await cameraReport()
        let report = SupportMail.testResults(text: "Reading: passed\nDevelop: not checked", cameraReport: camera)
        XCTAssertEqual(report.kind, .test)
        XCTAssertTrue(report.fileName.hasPrefix("darkslide-test-results-"))
        XCTAssertFalse(report.subject.contains("problem"))
        XCTAssertFalse(report.body.contains("what went wrong"))
        XCTAssertEqual(report.address, SupportContact.address)
        XCTAssertEqual(String(decoding: report.data, as: UTF8.self), "Reading: passed\nDevelop: not checked")
        XCTAssertEqual(try CameraCompatibilityReport.decode(report.extraFiles[0].data), camera)
    }

}
