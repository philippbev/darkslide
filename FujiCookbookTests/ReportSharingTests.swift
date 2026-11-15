import XCTest
@testable import FujiCookbook

/// What the Share sheet is handed: one body line, one file, a subject that is the file's name.
@MainActor
final class ReportSharingTests: XCTestCase {

    private var report: ShareableReport {
        ShareableReport(kind: .problem, address: "fujicookbook@grovehouse.xyz",
                        body: ShareableReport.body(for: "fujicookbook@grovehouse.xyz"),
                        fileName: "fuji-cookbook-camera-report-X-T50-20260904-1524.json",
                        data: Data("{}".utf8), mimeType: "application/json")
    }

    func testTheBodyIsOneFixedLine() {
        XCTAssertEqual(report.body, "To: fujicookbook@grovehouse.xyz. Darkslide report attached; add what went wrong below.")
        XCTAssertFalse(report.body.contains("\n"), "Gmail flattens newlines; there are none to flatten")
    }

    func testTheSubjectIsTheFileStem() {
        XCTAssertEqual(report.subject, "fuji-cookbook-camera-report-X-T50-20260904-1524",
                       "Mail shows the subject, Gmail shows the file name — same text either way")
    }

    func testShareBundleIsTheLineThenTheFile() throws {
        let items = try ShareBundle.items(for: report)
        XCTAssertEqual(items.count, 2)
        let text = try XCTUnwrap(items.first as? MailTextItem)
        let controller = UIActivityViewController(activityItems: [], applicationActivities: nil)
        XCTAssertEqual(text.activityViewController(controller, itemForActivityType: nil) as? String, report.body)
        XCTAssertEqual(text.activityViewController(controller, subjectForActivityType: nil), report.subject)
        let file = try XCTUnwrap(items.last as? URL)
        XCTAssertEqual(file.lastPathComponent, report.fileName)
        XCTAssertEqual(try Data(contentsOf: file), Data("{}".utf8))
    }

    func testAnyInvalidAttachmentRejectsTheWholeReport() throws {
        var invalid = report
        invalid.extraFiles = [("camera.json", Data())]
        XCTAssertThrowsError(try ShareBundle.items(for: invalid))

        invalid.extraFiles = [(report.fileName, Data("duplicate".utf8))]
        XCTAssertThrowsError(try ShareBundle.items(for: invalid), "one file must not overwrite another attachment")

        invalid.extraFiles = [("../outside.json", Data("{}".utf8))]
        XCTAssertThrowsError(try ShareBundle.items(for: invalid), "staging must not escape the report folder")
    }

    func testFailureWritingSecondAttachmentDoesNotReturnOrLeavePartialReport() throws {
        var complete = report
        complete.extraFiles = [("second.json", Data("{}".utf8))]
        var attempts = 0
        var stagedDirectory: URL?
        XCTAssertThrowsError(try ShareBundle.items(for: complete) { data, url in
            attempts += 1
            stagedDirectory = url.deletingLastPathComponent()
            if attempts == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertEqual(attempts, 2, "the failure occurs after a valid first attachment")
        let directory = try XCTUnwrap(stagedDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "no partial evidence is left staged")
        let retried = try ShareBundle.items(for: complete)
        XCTAssertEqual(retried.count, 3, "the same report can be retried intact")
        ShareBundle.clearStaging()
    }

    func testFrozenSnapshotRoundTripsAndDoesNotAccumulateEditedNotes() throws {
        let original = DiagnosticsReportSnapshot(capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                 reportText: "Original diagnostics", cameraReport: nil,
                                                 summary: ["Reading: passed", "Develop: not checked"])
        let restored = try JSONDecoder().decode(DiagnosticsReportSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        let first = restored.testResults(note: "First note").text
        let second = restored.testResults(note: "Revised note").text
        XCTAssertTrue(first.contains("First note"))
        XCTAssertFalse(second.contains("First note"))
        XCTAssertTrue(second.contains("Revised note"))
        XCTAssertEqual(second.components(separatedBy: "— Tester note —").count - 1, 1)
        XCTAssertEqual(second.components(separatedBy: "Reading: passed").count - 1, 1)
        XCTAssertTrue(second.contains("Develop: not checked"), "missing coverage survives reporting")
        XCTAssertEqual(restored.reportText, "Original diagnostics", "rendering never mutates captured evidence")
    }

    func testGuidedLogContextExcludesOtherTimesAndUsesDatesAcrossMidnight() {
        let start = Date(timeIntervalSince1970: 1_700_006_399)
        func event(_ offset: TimeInterval, _ category: AppLog.Category, _ message: String) -> AppLog.Entry {
            .init(timestamp: start.addingTimeInterval(offset), category: category, isError: false, message: message)
        }
        let entries = [event(-1, .camera, "Earlier GFX demo"), event(0, .camera, "This test connected"),
                       event(2, .kitchen, "JPEG produced"), event(2, .ai, "Unrelated activity"),
                       event(4, .camera, "After snapshot")]
        let text = DiagnosticsReportSnapshot.scopedActivityText(entries: entries, startedAt: start,
                                                                capturedAt: start.addingTimeInterval(3))
        XCTAssertFalse(text.contains("Earlier GFX demo"))
        XCTAssertFalse(text.contains("After snapshot"))
        XCTAssertFalse(text.contains("Unrelated activity"))
        XCTAssertTrue(text.contains("This test connected"))
        XCTAssertTrue(text.contains("JPEG produced"))
        XCTAssertTrue(text.contains("2023-11-14T23:59:59Z"))
        XCTAssertTrue(text.contains("2023-11-15T00:00:01Z"))
        XCTAssertTrue(text.contains("associated by time, not individually identified to a camera"))
    }

    func testShareOutcomesPersistWithoutClaimingReceipt() throws {
        for outcome: ReportShareOutcome in [.ready, .canceled, .saved, .shared, .mailSent, .failed] {
            XCTAssertEqual(try JSONDecoder().decode(ReportShareOutcome.self, from: JSONEncoder().encode(outcome)), outcome)
        }
        XCTAssertTrue(ReportShareOutcome.shared.message.contains("not confirmed"))
        XCTAssertTrue(ReportShareOutcome.mailSent.message.contains("not a delivery receipt"))
    }


    private func sessionAndReport(model: String = "X-M5", hash: String = "body-one")
        -> (GuidedTestSession, CameraCompatibilityReport) {
        var session = GuidedTestSession.beginContinuous(step: .review)
        session.cameraProductName = "FUJIFILM \(model)"
        session.identifiedModelID = model
        session.transport = "usb"
        session.serialHash = hash
        session.identity = .init(confirmed: true)
        var report = CameraCompatibilityReport.begin(productName: session.cameraProductName!, transport: "usb",
                                                      usb: nil, modelID: model, identification: "exact",
                                                      firmwareVersion: "1.00", verification: "inferred",
                                                      assumedSlotCount: 7)
        report.camera.serialHash = hash
        report.camera.serialHashScheme = SerialHash.keyedScheme
        report.note("Original camera trace")
        report.record(guidedTest: .init(session: session))
        return (session, report)
    }

    func testWrongBodyReportCannotReplaceSessionIdentityOrSupplyItsEvidence() {
        let (session, _) = sessionAndReport()
        var (_, wrong) = sessionAndReport(model: "X-T30 III", hash: "body-two")
        wrong.note("Other camera private evidence")
        let snapshot = DiagnosticsReportSnapshot.forSession(session, report: wrong)
        XCTAssertEqual(snapshot.cameraReport?.camera.productName, "FUJIFILM X-M5")
        XCTAssertEqual(snapshot.cameraReport?.camera.serialHash, "body-one")
        XCTAssertEqual(snapshot.cameraReport?.guidedTests?.first?.sessionID, session.id)
        XCTAssertFalse(snapshot.reportText.contains("Other camera private evidence"))
        XCTAssertFalse(snapshot.reportText.contains("— App activity at capture —"))
        XCTAssertTrue(snapshot.cameraReport?.slots.reads.isEmpty == true)
    }

    func testSameModelDifferentSerialAndLaterArchivedVisitAreNotSessionEvidence() {
        var (session, report) = sessionAndReport()
        var otherBody = report
        otherBody.camera.serialHash = "body-two"
        XCTAssertFalse(DiagnosticsReportSnapshot.belongsToSessionBody(otherBody, session: session))
        otherBody.camera.serialHash = nil
        XCTAssertFalse(DiagnosticsReportSnapshot.belongsToSessionBody(otherBody, session: session),
                       "missing serial on one side cannot verify the same body")

        session.outcome = .completed
        report.record(guidedTest: .init(session: session))
        report.updatedAt = session.updatedAt.addingTimeInterval(3600)
        report.note("Later same-body evidence")
        report.updatedAt = session.updatedAt.addingTimeInterval(3600)
        let archived = DiagnosticsReportSnapshot.forSession(session, report: report)
        XCTAssertFalse(archived.reportText.contains("Later same-body evidence"))
        XCTAssertTrue(archived.reportText.contains("original camera diagnostics were unavailable"))
    }

    func testRetainedSnapshotAndExplicitRefreshNeverAdoptLatestOtherBody() throws {
        var (session, report) = sessionAndReport()
        let original = DiagnosticsReportSnapshot.forSession(session, report: report)
        session.reportSnapshot = original
        let (_, otherBody) = sessionAndReport(model: "X-T30 III", hash: "body-two")
        XCTAssertEqual(DiagnosticsReportSnapshot.forSession(session, report: otherBody), original)

        session.freeText = "The original slot was restored later"
        let refreshed = DiagnosticsReportSnapshot.refreshing(session: session, reportSnapshot: original)
        XCTAssertEqual(refreshed.cameraReport?.camera, original.cameraReport?.camera)
        XCTAssertTrue(refreshed.reportText.contains("Original camera trace"))
        XCTAssertEqual(refreshed.cameraReport?.guidedTests?.first?.freeText, session.freeText)
        XCTAssertEqual(refreshed.cameraReport?.guidedTests?.count, 1, "refresh replaces its session projection")
        report.note("An operation after the saved snapshot")
        XCTAssertFalse(refreshed.reportText.contains("An operation after the saved snapshot"))
    }

    func testProjectingAnotherBodyDoesNotModifyTheManagersLiveOrSavedReport() async throws {
        CameraReportStore.deleteLatest()
        var faults = MockCameraFaults.xM5
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        let before = try XCTUnwrap(manager.reports.report)
        let savedBefore = CameraReportStore.loadLatest()
        var session = GuidedTestSession.beginContinuous()
        session.adopt(camera: GuidedTestRunner.facts(manager))
        session.cameraProductName = "FUJIFILM X-T30 III"
        GuidedTestRunner.project(session, into: manager)
        XCTAssertEqual(manager.reports.report, before)
        XCTAssertEqual(CameraReportStore.loadLatest(), savedBefore)
        await manager.connector.disconnect()
        CameraReportStore.deleteLatest()
    }


    func testEditedNoteAppearsOnceAndMatchesJSONWithoutChangingOtherSessions() throws {
        var (session, report) = sessionAndReport()
        var earlier = session
        earlier.id = "earlier-session"
        earlier.freeText = "Earlier test note remains"
        report.record(guidedTest: .init(session: earlier))
        session.freeText = "Stale current test note"
        report.record(guidedTest: .init(session: session))
        let snapshot = DiagnosticsReportSnapshot.forSession(session, report: report)
        let edited = snapshot.testResults(note: "Revised current test note")
        let share = SupportMail.testResults(text: edited.text, cameraReport: edited.cameraReport)
        let exportedJSON = try CameraCompatibilityReport.decode(XCTUnwrap(share.extraFiles.first?.data))

        XCTAssertEqual(edited.text.components(separatedBy: "Revised current test note").count - 1, 1)
        XCTAssertFalse(edited.text.contains("Stale current test note"))
        XCTAssertFalse(edited.technicalText.contains("Revised current test note"))
        XCTAssertTrue(edited.text.contains("Earlier test note remains"))
        XCTAssertEqual(exportedJSON.guidedTests?.first { $0.sessionID == session.id }?.freeText,
                       "Revised current test note")
        XCTAssertEqual(exportedJSON.guidedTests?.first { $0.sessionID == earlier.id }?.freeText,
                       "Earlier test note remains")
        XCTAssertEqual(snapshot.cameraReport?.guidedTests?.first { $0.sessionID == session.id }?.freeText,
                       "Stale current test note", "editing the export does not rewrite captured evidence")

        let cleared = snapshot.testResults(note: "   ")
        XCTAssertFalse(cleared.text.contains("— Tester note —"))
        XCTAssertFalse(cleared.text.contains("Stale current test note"))
        XCTAssertNil(cleared.cameraReport?.guidedTests?.first { $0.sessionID == session.id }?.freeText)
        XCTAssertTrue(cleared.text.contains("Earlier test note remains"))

        var legacy = snapshot
        legacy.sessionID = nil
        XCTAssertEqual(legacy.testResults(note: "Revised current test note", sessionID: session.id).text,
                       edited.text, "the owning session disambiguates a legacy multi-session snapshot")
    }

    func testCameraDataShowsTheAttachedJSONBytesForBothPresentations() throws {
        var (session, report) = sessionAndReport()
        session.freeText = "Saved note"
        report.record(guidedTest: .init(session: session))
        let snapshot = DiagnosticsReportSnapshot.forSession(session, report: report)

        let presentations: [(DiagnosticsReportView.Presentation, kind: ShareableReport.Kind)] = [
            (.standalone, .problem), (.cameraTest, .test)]
        for (presentation, kind) in presentations {
            let export = snapshot.export(for: presentation, note: "Edited note")
            let shared = export.shareable(for: presentation)
            let shown = try XCTUnwrap(export.cameraJSON)
            XCTAssertEqual(shared.kind, kind)
            XCTAssertEqual(shared.extraFiles.count, 1)
            XCTAssertEqual(Data(shown.utf8), shared.extraFiles.first?.data,
                           "\(presentation): Camera Data shows the attachment byte for byte")
            XCTAssertEqual(Data(export.text.utf8), shared.data, "\(presentation): Copy Report Text copies the .txt")
        }

        let standalone = try XCTUnwrap(snapshot.export(for: .standalone, note: "Edited note").cameraJSON)
        XCTAssertEqual(Data(standalone.utf8), snapshot.cameraReport?.json, "a problem report shows its capture as it is")
        let guided = try XCTUnwrap(snapshot.export(for: .cameraTest, note: "Edited note").cameraJSON)
        XCTAssertEqual(try CameraCompatibilityReport.decode(Data(guided.utf8))
                           .guidedTests?.first { $0.sessionID == session.id }?.freeText,
                       "Edited note", "a Camera Test shows the note-projected export, not the captured report")

        var noCamera = snapshot
        noCamera.cameraReport = nil
        let bare = noCamera.export(for: .standalone, note: nil)
        XCTAssertNil(bare.cameraJSON, "no camera report, no Camera Data section")
        XCTAssertTrue(bare.shareable(for: .standalone).extraFiles.isEmpty)
    }

}
