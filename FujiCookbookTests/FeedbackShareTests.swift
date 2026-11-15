import XCTest
@testable import FujiCookbook

/// **Send Feedback carries nothing it didn't say it would.**
///
/// `DiagnosticsReportView` and `SendFeedbackView` sit next to each other under Help & Feedback and
/// make opposite promises: one attaches both launches' logs and the camera compatibility report, the
/// other attaches neither. The second promise is the one a test can break silently — adding a
/// convenience to `SupportMail.feedback` would falsify the screen's disclosure without failing a
/// build. These pin it.
final class FeedbackShareTests: XCTestCase {

    func testFeedbackCarriesNoAttachmentsBeyondTheNote() {
        let share = SupportMail.feedback(text: "the Kitchen is slow on my phone")
        XCTAssertTrue(share.extraFiles.isEmpty, "no camera JSON, no log, no settings")
    }

    func testTheFileIsExactlyWhatWasPassedIn() {
        let note = "Darkslide — feedback\n\nApp          1.0 (12)\n\nlove the app"
        let share = SupportMail.feedback(text: note)
        XCTAssertEqual(String(decoding: share.data, as: UTF8.self), note,
                       "nothing is spliced in behind the view's back")
    }

    func testFeedbackIsNamedAndTypedAsItsOwnKind() {
        let share = SupportMail.feedback(text: "x")
        XCTAssertEqual(share.kind, .feedback)
        XCTAssertEqual(share.address, SupportContact.address)
        XCTAssertTrue(share.fileName.hasPrefix("fuji-cookbook-feedback-"), share.fileName)
        XCTAssertTrue(share.fileName.hasSuffix(".txt"))
        XCTAssertEqual(share.mimeType, "text/plain")
        XCTAssertEqual(share.subject, (share.fileName as NSString).deletingPathExtension)
    }

    /// Two items where a problem report has three — see
    /// `SupportMailTests.testShareBundleCarriesEveryAttachmentInOrder`.
    func testShareBundleIsTheBodyLineAndOneFile() throws {
        let items = try ShareBundle.items(for: SupportMail.feedback(text: "x"))
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0] is MailTextItem)
        XCTAssertEqual((items[1] as? URL)?.pathExtension, "txt")
    }

    /// The files handed to the share sheet are copies of whatever the report carried — for a problem
    /// report, the tester's slot recipes. They used to be written into `tmp` and left there with
    /// nothing to remove them, outliving Clear Diagnostics.
    func testStagedFilesAreReplacedNotAccumulated() throws {
        ShareBundle.clearStaging()
        let first = try ShareBundle.items(for: SupportMail.feedback(text: "one"))
        let firstURL = try XCTUnwrap(first.last as? URL)
        let dir = firstURL.deletingLastPathComponent()
        XCTAssertEqual(dir.lastPathComponent, "SharedReports", "staged in their own folder, not bare tmp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))

        // A second share clears the first one's files rather than piling up beside them.
        _ = try ShareBundle.items(for: SupportMail.feedback(text: "two"))
        let staged = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(staged.count, 1, "only the newest share's files are on disk: \(staged)")

        ShareBundle.clearStaging()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "what Clear Diagnostics calls actually removes them")
    }

    /// The same Gmail invariant `ReportSharingTests` pins for the problem report's body: a
    /// multi-line body is flattened into one paragraph, so the body must be one line and the
    /// tester's prose must live in the file.
    func testTheBodyIsOneLineAndDropsTheProblemReportsPrompt() {
        let body = ShareableReport.feedbackBody(for: SupportContact.address)
        XCTAssertFalse(body.contains("\n"))
        XCTAssertTrue(body.contains(SupportContact.address))
        XCTAssertFalse(body.contains("add what went wrong below"),
                       "for feedback the note is already written")
        XCTAssertNotEqual(body, ShareableReport.body(for: SupportContact.address))
    }
}
