import XCTest
@testable import FujiCookbook

/// Foreground-death detection.
///
/// The assertion that carries this feature is the **negative** one. Making "we noticed a crash"
/// fire is trivial; the whole value depends on it staying silent when iOS reclaims a suspended app,
/// which happens constantly and is not a fault. A detector that cries wolf on every background kill
/// trains people to dismiss the banner, at which point it is worse than not having one.
@MainActor
final class SessionTerminationTests: XCTestCase {

    private var markerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ScreenshotInbox.appGroupID)?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("session-foreground.marker")
    }

    private let originalRun = SessionTermination.currentRun

    /// A run from the home screen: no debugger, one install. Pinned, because the test host may be
    /// running under a debugger, and every run it records would then read as one Xcode ended.
    private static let homeScreenRun = SessionTermination.Run(bundlePath: "/Bundle/Application/A/FujiCookbook.app",
                                                              debuggerAttached: false)

    override func setUp() {
        super.setUp()
        SessionTermination.currentRun = { Self.homeScreenRun }
        SessionTermination.markForegroundEnded()
        AppLog.eraseFiles()
    }

    override func tearDown() {
        SessionTermination.markForegroundEnded()
        AppLog.eraseFiles()
        SessionTermination.currentRun = originalRun
        super.tearDown()
    }

    /// The app was backgrounded, then terminated. Routine, and must read as routine.
    func testACleanBackgroundLeavesNothingToDetect() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        SessionTermination.markForegroundActive()   // launched, on screen
        SessionTermination.markForegroundEnded()    // user swiped away; iOS may now kill us freely

        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertFalse(SessionTermination.previousLaunchEndedUnexpectedly,
                       "iOS reclaiming a suspended app is not a fault and must never be reported as one")
        XCTAssertTrue(AppLog.unexpectedExitText().isEmpty, "and nothing is preserved")
    }

    /// The app died while the user was looking at it. The marker is still there.
    func testAForegroundDeathIsDetected() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        SessionTermination.markForegroundActive()   // on screen …
        // … and then the process is gone, with no chance to clean up. Nothing runs here on purpose.

        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly)
    }

    /// Stop or Run in Xcode kills the app where it stands, usually on screen. That is the developer
    /// ending the run, and a banner about it on every rebuild is the crying wolf this type exists
    /// to avoid.
    func testARunXcodesDebuggerEndedIsNotReported() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        SessionTermination.currentRun = { .init(bundlePath: Self.homeScreenRun.bundlePath, debuggerAttached: true) }
        SessionTermination.markForegroundActive()   // on screen, under Xcode, and then Stop

        SessionTermination.currentRun = { Self.homeScreenRun }   // relaunched from the home screen
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertFalse(SessionTermination.previousLaunchEndedUnexpectedly)
        XCTAssertTrue(AppLog.unexpectedExitText().isEmpty, "and nothing is preserved as if it were a fault")
    }

    /// Installing over a running copy kills it — Xcode's Run does, even when the copy it kills was
    /// opened from the home screen with no debugger in sight.
    func testARunEndedByAReinstallIsNotReported() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        SessionTermination.markForegroundActive()   // on screen, and then a new build lands
        SessionTermination.currentRun = { .init(bundlePath: "/Bundle/Application/B/FujiCookbook.app",
                                                debuggerAttached: false) }
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertFalse(SessionTermination.previousLaunchEndedUnexpectedly)
        XCTAssertTrue(AppLog.unexpectedExitText().isEmpty)

        // The launch that stayed quiet is still armed: if the new install dies on screen, that is
        // reported.
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly)
    }

    /// Builds before the run record wrote a bare timestamp. The first launch of a build that reads
    /// one is, by definition, a launch after a reinstall.
    func testAMarkerFromAnOlderBuildIsNotReported() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")
        let url = try XCTUnwrap(markerURL)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("2026-10-17T18:44:29Z".utf8).write(to: url, options: .atomic)

        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertFalse(SessionTermination.previousLaunchEndedUnexpectedly)
    }

    /// Presence is the signal. A marker whose contents can't be read still says the run died on
    /// screen; only contents that explain the death keep it quiet.
    func testAMarkerThatCantBeReadIsReported() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")
        let url = try XCTUnwrap(markerURL)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0x00, 0x7B]).write(to: url, options: .atomic)

        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly,
                      "unreadable contents explain nothing, so they must not read as a reinstall")
    }

    /// Detection re-arms for the run that just started, so a second consecutive foreground death is
    /// also caught. Without this the marker would be consumed and only the first would ever report.
    func testDetectionRearmsForTheNewRun() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        SessionTermination.markForegroundActive()
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly)

        // Die again without a clean background.
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly,
                      "two crashes in a row are two reports, not one")
    }

    /// A silent CloudKit push launches the app with no scene. Nobody is looking, so that run's death
    /// is iOS's business, and the detector must not be armed as if a person had opened the app.
    func testABackgroundLaunchDoesNotArmTheDetector() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        SessionTermination.detectAtLaunch(.background, after: AppLog.rollLogFiles())   // woken by a push …
        // … and reclaimed by iOS without a scene ever appearing. Nothing runs here on purpose.

        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertFalse(SessionTermination.previousLaunchEndedUnexpectedly,
                       "a background run iOS reclaimed is not a death anyone saw")
    }

    /// A death found by a background launch is reported by the launch that has a screen, with the
    /// dead run's log as the evidence, not the background run's.
    func testADeathFoundAtABackgroundLaunchIsReportedByTheNextForegroundLaunch() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        AppLog.error(.app, "the dead run's last words")
        _ = AppLog.currentLaunchText()   // drains the log's IO queue; see testAcknowledgingKeepsThePreservedLog
        SessionTermination.markForegroundActive()   // on screen, and then gone

        // A push wakes the app with no scene.
        SessionTermination.detectAtLaunch(.background, after: AppLog.rollLogFiles())
        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly)
        XCTAssertTrue(AppLog.unexpectedExitText().contains("the dead run's last words"), "preserved at once")

        AppLog.error(.app, "the background run's own lines")   // which iOS then reclaims, unseen
        _ = AppLog.currentLaunchText()

        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly, "still reported, now that there is a screen")
        XCTAssertTrue(AppLog.unexpectedExitText().contains("the dead run's last words"),
                      "and the evidence is the dead run's log")
        XCTAssertFalse(AppLog.unexpectedExitText().contains("the background run's own lines"),
                       "not the background run's")
    }

    /// The same, from a marker that can't be read: the background launch still flags it as
    /// preserved, so the foreground launch doesn't copy the background run's log over the evidence.
    func testAnUnreadableMarkerFoundAtABackgroundLaunchKeepsTheDeadRunsLog() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")
        let url = try XCTUnwrap(markerURL)

        AppLog.error(.app, "the dead run's last words")
        _ = AppLog.currentLaunchText()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0x00, 0x7B]).write(to: url, options: .atomic)

        SessionTermination.detectAtLaunch(.background, after: AppLog.rollLogFiles())
        XCTAssertTrue(AppLog.unexpectedExitText().contains("the dead run's last words"), "preserved at once")

        AppLog.error(.app, "the background run's own lines")
        _ = AppLog.currentLaunchText()

        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly, "still reported, now that there is a screen")
        XCTAssertFalse(AppLog.unexpectedExitText().contains("the background run's own lines"),
                       "and the evidence is still the dead run's log")
    }

    /// Dismissing the banner is not consent to destroy the evidence.
    func testAcknowledgingKeepsThePreservedLog() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        AppLog.error(.app, "something worth keeping")
        // Drains the log's IO queue as well as flushing: `flush()` only *enqueues* the write, so
        // rolling straight after it can move an empty file. Production doesn't hit this — the roll
        // happens at launch, long after the previous run's writes landed.
        _ = AppLog.currentLaunchText()
        SessionTermination.markForegroundActive()
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())

        XCTAssertFalse(AppLog.unexpectedExitText().isEmpty, "the dead run's log was copied aside")
        SessionTermination.acknowledge()
        XCTAssertFalse(SessionTermination.previousLaunchEndedUnexpectedly, "the banner goes")
        XCTAssertFalse(AppLog.unexpectedExitText().isEmpty, "the evidence stays")
    }

    /// Clear Diagnostics is what removes it, and it must actually reach this third file — the whole
    /// point of which is that nothing else ever rolls or overwrites it.
    func testClearDiagnosticsErasesThePreservedLog() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        AppLog.error(.app, "something worth keeping")
        // Drains the log's IO queue as well as flushing: `flush()` only *enqueues* the write, so
        // rolling straight after it can move an empty file. Production doesn't hit this — the roll
        // happens at launch, long after the previous run's writes landed.
        _ = AppLog.currentLaunchText()
        SessionTermination.markForegroundActive()
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertFalse(AppLog.unexpectedExitText().isEmpty)

        AppLog.eraseFiles()
        XCTAssertTrue(AppLog.unexpectedExitText().isEmpty,
                      "Clear Diagnostics promises to erase what a report draws on, and a report draws on this")
    }

    /// `flushNow` is what puts a crash's last lines on disk. The roll here stands in for the next
    /// launch finding a dead run: nothing between the log call and the roll gets a chance to flush,
    /// which is the whole of what a crash is from the log's point of view.
    func testFlushNowPutsTheLineOnDiskBeforeACrashCouldTakeIt() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        AppLog.info(.camera, "Connect: hardware connect requested (flushNow test)")
        AppLog.flushNow()
        AppLog.rollLogFiles()

        XCTAssertTrue(AppLog.previousLaunchText().contains("hardware connect requested (flushNow test)"),
                      "the dead run's log has the line that preceded the crash")
    }

    /// The control: logged but only buffered, the line is not in what the next launch finds.
    func testWithoutFlushNowTheLineBeforeACrashIsLost() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        AppLog.info(.camera, "Connect: hardware connect requested (unflushed control)")
        AppLog.rollLogFiles()

        XCTAssertFalse(AppLog.previousLaunchText().contains("hardware connect requested (unflushed control)"),
                       "buffered, not written: a crash here loses it")
    }

    /// A run that dies before writing anything must not inherit the log of the run before it.
    func testARunThatLeftNoLogDoesNotInheritTheOneBeforeIt() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        // Run A, which wrote its log, then ended normally.
        AppLog.info(.app, "run A — an older session")
        AppLog.flushNow()
        // Run B launches (A's lines roll into previous.log), is in the foreground, writes nothing.
        AppLog.rollLogFiles()
        SessionTermination.markForegroundActive()
        // Run C launches after B died.
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())

        XCTAssertTrue(SessionTermination.previousLaunchEndedUnexpectedly, "B's death is still detected")
        XCTAssertFalse(AppLog.previousLaunchText().contains("run A"),
                       "A is not B's previous launch log")
        XCTAssertFalse(AppLog.unexpectedExitText().contains("run A"),
                       "and A is not preserved as the session that ended unexpectedly")
        XCTAssertEqual(AppLog.unexpectedExitText().trimmingCharacters(in: .newlines),
                       AppLog.noLogFromDeadRun, "the preserved log says there was nothing to preserve")
    }

    /// The same mistake one file along: a later death that left no log must not leave an *earlier*
    /// death's preserved log in place, to be read as this one's.
    func testANewDeathWithNoLogReplacesAnEarlierPreservedOne() throws {
        try XCTSkipIf(markerURL == nil, "no App Group container in this test host")

        // First death, with a log, preserved at the next launch.
        AppLog.info(.app, "the first crash's last line")
        AppLog.flushNow()
        SessionTermination.markForegroundActive()
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())
        XCTAssertTrue(AppLog.unexpectedExitText().contains("the first crash's last line"))
        SessionTermination.acknowledge()

        // That launch dies too, in the foreground, before writing anything — what it logged is only
        // buffered, and nothing here flushes — and the next one starts.
        SessionTermination.detectAtLaunch(.foreground, after: AppLog.rollLogFiles())

        XCTAssertFalse(AppLog.unexpectedExitText().contains("the first crash's last line"),
                       "the earlier crash's log is not presented as this one's")
        XCTAssertEqual(AppLog.unexpectedExitText().trimmingCharacters(in: .newlines),
                       AppLog.noLogFromDeadRun)
    }
}
