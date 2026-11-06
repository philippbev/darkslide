import Foundation
import Observation

/// Owns the compatibility report for the connected body and the bounded PTP trace behind it: what
/// the last connect learned (`GetDeviceInfo`, every slot read with its raw bytes, the read-only
/// sweep on an unrecognized body, the transaction trace) and what every operation since recorded.
/// `CameraConnector.disconnect()` leaves it in place, so a tester can share it after unplugging, and
/// `persist()` mirrors it to disk so it also outlives the launch.
@MainActor
@Observable
final class CompatibilityReportRecorder {

    private(set) var report: CameraCompatibilityReport?

    /// Records only while `isTracing` is on: through the connect sequence, and around each push,
    /// restore, probe and conversion. Keepalive pings in between would fill the bounded trace with
    /// traffic that says nothing new about the body.
    let trace = PTPTraceRecorder()

    var isTracing: Bool {
        get { trace.isRecording }
        set { trace.isRecording = newValue }
    }

    /// The push history's answers for the per-slot undo.
    var history: SlotHistory { SlotHistory(report: report) }

    /// A fresh report for a new session, traced from here on.
    func begin(_ report: CameraCompatibilityReport) {
        self.report = report
        trace.reset()
    }

    /// Changes the report in place; does nothing when there is no report. `change` must not call
    /// back into the recorder: that would be a second modify of `report` inside the first, which
    /// Swift's exclusivity check aborts the process for.
    func update(_ change: (inout CameraCompatibilityReport) -> Void) {
        guard report != nil else { return }
        // Cannot fail: the guard above. `report!` as the inout argument modifies in place; copying
        // the report out and back would copy its notes and slot reads on every note.
        change(&report!)
    }

    func note(_ text: String) {
        update { $0.note(text) }
    }

    func noteOnce(_ text: String) {
        update { $0.noteOnce(text) }
    }

    /// Snapshot the trace into the report and write it to disk. Called at every stage boundary so
    /// a crash mid-session still leaves the last complete stage behind.
    func persist() {
        guard var report else { return }
        report.transactions = trace.snapshot
        report.transactionsDropped = trace.droppedCount
        self.report = report
        CameraReportStore.save(report)
    }

    /// Carries the stored report's pushes, guided tests, property sweep, profile harvests and
    /// develops into this session's report when both describe the same body (`describesSameBody`).
    /// Does nothing for a different body or when nothing is stored, and does not write to disk.
    ///
    /// `begin` makes a fresh report every connect and the store keeps only the newest, so without
    /// this a tester who pushed, unplugged and plugged back in would lose the record of what the
    /// camera refused, and the Camera Test's power cycle would erase the push it is there to check.
    /// Called after `GetDeviceInfo`, because the serial hash this matches on arrives with it.
    func carryHistoryForward() {
        guard let previous = CameraReportStore.loadLatest(), var report,
              report.describesSameBody(as: previous) else { return }
        report.adoptPushHistory(from: previous)
        if let carried = report.pushes?.count, carried > 0 {
            CameraLog.info("Report: carried \(carried) earlier push record(s) forward for this body")
        }
        report.adoptGuidedTests(from: previous)
        report.adoptPropertySweep(from: previous)
        report.adoptProfileHarvests(from: previous)
        report.adoptDevelops(from: previous)
        self.report = report
    }

    /// Appends a failed connect to the live report, else the stored one, and saves it; creates a
    /// minimal report only when neither exists.
    ///
    /// The report is one file overwritten per connect, so a fresh report here would let a failed
    /// reconnect erase the session before it, just when the tester is most likely to send a report.
    func recordConnectionFailure(stage: String, reason: String, productName: String? = nil,
                                 usb: USBIdentity? = nil, identification: String? = nil,
                                 authorization: (control: String, contents: String)? = nil) {
        var report = self.report ?? CameraReportStore.loadLatest()
            ?? CameraCompatibilityReport.beginUnreached()
        report.record(connectionFailure: stage, reason: reason, productName: productName,
                      usb: usb, identification: identification, authorization: authorization)
        self.report = report
        CameraReportStore.save(report)
    }

    /// Records a guided test in the report for the session's own body (the live report, else the
    /// stored one) and saves it. Records nothing when that report, or the connected camera, is a
    /// different body: a user may reopen an old test with another camera connected, and that must
    /// change neither body's report. Refusing loses nothing, because the session keeps its own
    /// report snapshot. `connectedProductName` is nil when nothing is connected.
    func recordGuidedTest(_ session: GuidedTestSession, connectedProductName: String?) {
        let candidate = report ?? CameraReportStore.loadLatest()
        if let candidate, !DiagnosticsReportSnapshot.belongsToSessionBody(candidate, session: session) {
            return
        }
        if let connectedProductName, session.cameraProductName != connectedProductName { return }
        var report = candidate ?? DiagnosticsReportSnapshot.sessionOnlyReport(session)
        report.record(guidedTest: .init(session: session))
        self.report = report
        CameraReportStore.save(report)
    }

    /// Clear Diagnostics for the live report: strips it to its drift baseline, or drops it when no
    /// applied push is left, as `CameraReportStore.stripLatestToDriftBaseline()` does to the file.
    /// Leaves the trace's recording state alone.
    ///
    /// `DiagnosticsReportView` prefers the live report over the file, so clearing only the file
    /// would leave a connected camera's slot contents, raw bytes and trace in the next report. The
    /// trace goes too: `persist()` snapshots it into the report and only `begin` resets it, so the
    /// next persist would write the cleared transactions back.
    func clear() {
        trace.discardRecorded()
        guard var report else { return }
        report.stripToDriftBaseline()
        self.report = report.pushes == nil ? nil : report
    }
}
