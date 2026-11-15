import XCTest
@testable import FujiCookbook

/// The on-disk log ships inside user-emailed problem reports, and the privacy policy (§3) promises
/// it carries no recipe or photo content and no picked file names. Seven call sites used to interpolate a full
/// `String(describing: error)` into it — and a `.fujirecipe` is usually named after the recipe
/// inside it, so a failed import wrote the user's recipe name into a file they then mailed us.
///
/// `AppLog.bounded` is what keeps that promise. These assert the property the promise rests on.
final class LogRedactionTests: XCTestCase {
    /// The shape Foundation actually throws at a failed read — `NSFilePath` populated, and the
    /// description quoting it back.
    private func fileError(path: String) -> Error {
        CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: path])
    }

    func testBoundedDropsTheFilePath() {
        let secret = "/private/var/mobile/Containers/Shared/Inbox/Kodachrome Summer.fujirecipe"
        let bounded = AppLog.bounded(fileError(path: secret))

        XCTAssertFalse(bounded.contains("Kodachrome"), "the recipe name is the user's content")
        XCTAssertFalse(bounded.contains(".fujirecipe"), "the file name identifies the content")
        XCTAssertFalse(bounded.contains("/"), "no path component survives")
    }

    func testBoundedKeepsWhatMakesItDiagnosable() {
        let bounded = AppLog.bounded(fileError(path: "/tmp/DSCF0001.RAF"))

        XCTAssertTrue(bounded.contains(NSCocoaErrorDomain), "the domain says which subsystem failed")
        XCTAssertTrue(bounded.contains("\(CocoaError.fileReadNoSuchFile.rawValue)"),
                      "the code says how — that is the half worth keeping")
    }

    /// A URL error quotes the whole URL, host and path included.
    func testBoundedDropsTheURL() {
        let error = URLError(.timedOut,
                             userInfo: [NSURLErrorFailingURLStringErrorKey: "https://api.example.com/v1/messages"])
        let bounded = AppLog.bounded(error)

        XCTAssertFalse(bounded.contains("example.com"), "the endpoint does not belong in the log")
        XCTAssertTrue(bounded.contains("\(URLError.Code.timedOut.rawValue)"), "the code survives")
    }

    /// `Error.cameraLogDescription` is what the camera layer's log lines and report notes
    /// go through. Its final fallback used to be `localizedDescription`, which for a Foundation
    /// error quotes the path it failed on. It has callers across the camera layer, many of them
    /// reachable only on hardware, so the helper is where the property gets pinned.
    @MainActor
    func testShortErrorDropsTheFilePath() {
        let secret = "/private/var/mobile/Containers/Shared/Inbox/Kodachrome Summer.fujirecipe"
        let short = fileError(path: secret).cameraLogDescription

        XCTAssertFalse(short.contains("Kodachrome"))
        XCTAssertFalse(short.contains("/"))
        XCTAssertTrue(short.contains(NSCocoaErrorDomain), "the domain and code still survive")
    }

    /// And the branch that matters more: a PTP refusal keeps its code and name, which is the whole
    /// diagnostic value of these lines.
    @MainActor
    func testShortErrorKeepsThePTPResponseCode() {
        let short = CameraError.ptpError(code: FujiPTP.responseDevicePropNotSupported).cameraLogDescription

        XCTAssertTrue(short.contains("0x200A"), short)
    }
}
