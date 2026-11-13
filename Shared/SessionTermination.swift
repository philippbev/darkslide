import Foundation

/// Did the last run of this app end the way runs are supposed to end?
///
/// The app ships no crash reporter, so nothing notices a crash, and `previous.log`, which is the
/// entire story of one, is overwritten by the next launch. A tester who reopens the app twice
/// before thinking to send a report has already lost it. This is the smallest thing that closes
/// that: a marker file, checked at launch.
///
/// **The hard part is not detecting a death; it is not crying wolf.** iOS terminates suspended apps
/// constantly and entirely normally, and a naive "was the process still running?" flag reports every
/// one of those as a crash — which trains people to dismiss the prompt, at which point the feature
/// is worse than nothing. So the marker tracks **foreground presence**, not process lifetime: it is
/// written when the scene becomes active and removed the moment it stops being active. A marker
/// found at launch therefore means the app died *while the user was looking at it*.
///
/// That still covers two causes we cannot tell apart — a crash and a foreground jetsam kill. Both
/// are worth a log, and calling either one a crash would be a guess. Hence
/// `previousLaunchEndedUnexpectedly` rather than `crashed`, and hence the user-facing wording is
/// "ended unexpectedly" everywhere.
///
/// A force-quit never leaves a marker: opening the app switcher takes the scene out of `.active`
/// before a card can be swiped away (iPhone 17 Simulator, iOS 27.0, 2026-11-01).
///
/// The one foreground death the marker *can* explain is Xcode's. Stop and Run kill the app wherever
/// it is, and a developer's app is on screen most of the times Xcode does it, so the marker records
/// enough about its run — see `Run` — for the next launch to recognize those and stay quiet.
public enum SessionTermination {

    /// True when the previous run died in the foreground. Read once at launch, before the marker for
    /// this run is written, and cached until `acknowledge()` clears it.
    public private(set) static var previousLaunchEndedUnexpectedly = false

    /// What the marker records about the run that wrote it.
    struct Run: Codable, Equatable {
        /// The installed bundle's path. Every install gets its own bundle container, so a different
        /// path at the next launch means the app was installed again in between — and installing
        /// kills a running copy of the app, on screen or not.
        var bundlePath: String
        /// Under a debugger, the run ends when Xcode ends it: Stop, or Run again.
        var debuggerAttached: Bool
        /// Set by a background launch that found this marker and preserved the dead run's log, with
        /// no scene to report it on. The launch that has one reports it and leaves that log alone.
        var reportPending: Bool? = nil
    }

    /// A marker found at launch, as read back.
    enum Marker: Equatable {
        case run(Run)
        /// A bare timestamp, which builds before `Run` wrote.
        case olderBuild
        /// Contents that can't be read or decoded. Presence alone still means a foreground death.
        case unreadable
    }

    /// Where iOS put the app when it launched it. A silent CloudKit push (the `remote-notification`
    /// background mode, for iCloud sync) launches the app with no scene, and nobody is looking.
    public enum LaunchContext {
        case foreground
        case background
    }

    /// This run, as the marker records it. A seam for tests: the test host runs however it runs,
    /// and the tests need to stand in for a run under Xcode, or a reinstall, without being one.
    static var currentRun: () -> Run = {
        Run(bundlePath: Bundle.main.bundlePath, debuggerAttached: isDebuggerAttached)
    }

    /// Call once, from the app's `init`, with the result of that launch's `AppLog.rollLogFiles()`.
    ///
    /// The roll is what moves the dead run's lines from `current.log` into `previous.log`, and this
    /// is what copies them somewhere that never rolls. Before the roll, it would preserve the log of
    /// the run before the dead one.
    ///
    /// A background launch reads the marker but does not arm it: nobody is looking, so that run's
    /// death is iOS's business. What it finds it preserves at once — the dead run's log is in
    /// `previous.log` only until the next roll — and flags the marker as already preserved, so the
    /// launch that finally has a scene reports the death without copying its own predecessor's log
    /// over the evidence.
    public static func detectAtLaunch(_ context: LaunchContext, after rolledLogs: AppLog.RolledLogs) {
        previousLaunchEndedUnexpectedly = false
        if let marker = readMarker() {
            if let explanation = explainedEnding(of: marker) {
                // Info, not an error: nothing failed. Logged so a report still says how the run
                // ended, and why that wasn't raised.
                AppLog.info(.app, "Previous session ended in the foreground \(explanation), so it isn't reported")
                if context == .background { removeMarker() }
            } else if case .run(let dead) = marker, dead.reportPending == true {
                previousLaunchEndedUnexpectedly = true
                AppLog.error(.app, "Previous session ended unexpectedly while in the foreground — its log was preserved by an earlier launch")
            } else {
                previousLaunchEndedUnexpectedly = true
                AppLog.preserveLogFromUnexpectedExit(after: rolledLogs)
                // An error, not info: this is the line that tells a reader of a shared report to go
                // and look at the preserved log rather than wondering why the story starts mid-sentence.
                AppLog.error(.app, "Previous session ended unexpectedly while in the foreground — its log was preserved")
                if context == .background { flagReportPending(marker) }
            }
        }
        // Arm this run only when a person opened it. The scene-phase observer fires on a *change*
        // and so never for a foreground launch's initial `.active`, which is why it happens here; a
        // background-launched run is armed by `markForegroundActive` if a scene appears later.
        if context == .foreground { writeMarker() }
    }

    /// The scene became active: this run is now one whose disappearance would be a surprise.
    public static func markForegroundActive() { writeMarker() }

    /// The scene stopped being active. From here a termination is iOS doing its job, not a fault,
    /// so the marker comes off — this is the call that keeps the detector honest.
    public static func markForegroundEnded() { removeMarker() }

    /// Forget the detection for this launch, once it has been surfaced and dismissed. The preserved
    /// log stays: the user dismissing a banner is not the user saying the evidence can go.
    public static func acknowledge() { previousLaunchEndedUnexpectedly = false }

    /// Why a run that died in the foreground needs no report, or nil when nothing explains it.
    ///
    /// Both explanations are Xcode's, and neither reaches a TestFlight or App Store user's ordinary
    /// use: no update replaces an app that is on screen. The one real death this hides is a crash
    /// followed by an update before the next launch — a report about a build that is already gone.
    static func explainedEnding(of marker: Marker) -> String? {
        switch marker {
        case .olderBuild:
            // A newer build has been installed over the one that wrote it.
            return "and the app was reinstalled before this launch"
        case .unreadable:
            return nil
        case .run(let previous):
            if previous.debuggerAttached { return "under Xcode's debugger" }
            if previous.bundlePath != currentRun().bundlePath {
                return "and the app was reinstalled before this launch"
            }
            return nil
        }
    }

    // MARK: Marker

    private static var markerURL: URL? {
        SharedContainer.url?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("session-foreground.marker")
    }

    /// The marker, or nil when there is none. Presence is the signal; the contents only explain it.
    private static func readMarker() -> Marker? {
        guard let url = markerURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        if let run = try? JSONDecoder().decode(Run.self, from: data) { return .run(run) }
        if ISO8601DateFormatter().date(from: String(decoding: data, as: UTF8.self)) != nil { return .olderBuild }
        return .unreadable
    }

    /// Rewritten on every return to the foreground, so it describes the run as it is now — a
    /// debugger attached mid-run is recorded the next time the app comes back on screen.
    private static func writeMarker() {
        guard let url = markerURL, let contents = try? JSONEncoder().encode(currentRun()) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? contents.write(to: url, options: .atomic)
    }

    /// Apple's own test (QA1361): the kernel marks a process `P_TRACED` while a debugger is attached.
    private static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }

    private static func removeMarker() {
        guard let url = markerURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Rewrite the marker as already preserved, keeping the dead run's own record so the next launch
    /// explains it the same way this one did. An unreadable marker has no record to keep, so it gets
    /// this install's path and no debugger: what leaves the death unexplained at the next launch
    /// unless the app is reinstalled first.
    private static func flagReportPending(_ marker: Marker) {
        guard let url = markerURL else { return }
        var dead: Run
        if case .run(let record) = marker {
            dead = record
        } else {
            dead = Run(bundlePath: currentRun().bundlePath, debuggerAttached: false)
        }
        dead.reportPending = true
        guard let contents = try? JSONEncoder().encode(dead) else { return }
        try? contents.write(to: url, options: .atomic)
    }
}
