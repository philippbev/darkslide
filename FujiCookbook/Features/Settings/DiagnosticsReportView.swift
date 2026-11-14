import SwiftUI
import SwiftData
import UIKit

/// A report screen's contents, frozen when captured: report text, camera report and test summary.
///
/// Captured independently of the mutable `CompatibilityReportRecorder.report`. The owning Camera
/// Test persists this value so canceled shares and relaunches can return to the same evidence.
struct DiagnosticsReportSnapshot: Codable, Equatable {
    var capturedAt: Date
    var reportText: String
    var cameraReport: CameraCompatibilityReport?
    var summary: [String]
    var sessionID: String? = nil

    /// The session's report: its retained snapshot when it has one, otherwise a new capture.
    ///
    /// A new capture uses `candidate` only when that report is from the session's camera and, for
    /// an archived session, from the same visit; otherwise it is built from the session's own
    /// answers. A caller that needs a fresh capture clears `reportSnapshot` first.
    @MainActor
    static func forSession(_ session: GuidedTestSession, report candidate: CameraCompatibilityReport?) -> Self {
        if var snapshot = session.reportSnapshot {
            // Snapshots saved by earlier builds have no `sessionID`. The owning session supplies
            // it without changing any captured camera evidence.
            if snapshot.sessionID == nil { snapshot.sessionID = session.id }
            return snapshot
        }
        let usable = candidate.flatMap { report -> CameraCompatibilityReport? in
            guard belongsToSessionBody(report, session: session) else { return nil }
            if !session.isLive {
                // A report from a later visit to the same body is not the archived session's report.
                guard report.updatedAt <= session.updatedAt,
                      report.guidedTests?.contains(where: {
                          $0.sessionID == session.id && $0.updatedAt == session.updatedAt
                      }) == true else { return nil }
            }
            return report
        }
        var report = usable ?? sessionOnlyReport(session)
        report.record(guidedTest: .init(session: session))
        var text = report.textRendering
        let capturedAt = Date()
        if usable != nil, session.isLive {
            let log = scopedActivityText(entries: AppLog.entries, startedAt: session.startedAt,
                                         capturedAt: capturedAt)
            if !log.isEmpty { text += "\n\n" + log }
        }
        return Self(capturedAt: capturedAt, reportText: text,
                    cameraReport: report, summary: CameraTestSummary.lines(session), sessionID: session.id)
    }

    /// Entries carry full dates, unlike the on-disk log's time-only lines. Filtering the typed
    /// buffer excludes a prior demo/body without guessing dates across midnight or relaunches.
    static func scopedActivityText(entries: [AppLog.Entry], startedAt: Date, capturedAt: Date) -> String {
        let selected = entries.filter {
            $0.timestamp >= startedAt && $0.timestamp <= capturedAt
                && ($0.category == .camera || $0.category == .kitchen)
        }
        guard !selected.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        var lines = ["— App activity during this test —",
                     "Bounded camera/Kitchen context from the current app launch, \(formatter.string(from: startedAt)) to \(formatter.string(from: capturedAt)). Earlier buffered or previous-launch activity may be absent. Events are associated by time, not individually identified to a camera."]
        lines += selected.map {
            "\(formatter.string(from: $0.timestamp)) [\($0.category.rawValue)] \($0.isError ? "! " : "")\($0.message)"
        }
        return lines.joined(separator: "\n")
    }

    /// Recovery can change after a test finishes. Reproject only that session over its retained
    /// camera evidence; never fetch the currently connected body or append new global logs.
    @MainActor
    static func refreshing(session: GuidedTestSession, reportSnapshot snapshot: Self) -> Self {
        guard var report = snapshot.cameraReport, belongsToSessionBody(report, session: session) else {
            var fresh = session
            fresh.reportSnapshot = nil
            return forSession(fresh, report: nil)
        }
        let priorRendering = report.textRendering
        report.record(guidedTest: .init(session: session))
        let text = snapshot.reportText.contains(priorRendering)
            ? snapshot.reportText.replacingOccurrences(of: priorRendering, with: report.textRendering)
            : report.textRendering
        return Self(capturedAt: CameraCompatibilityReport.timestamp(), reportText: text,
                    cameraReport: report, summary: CameraTestSummary.lines(session), sessionID: session.id)
    }

    /// Whether `report` is from the camera `session` tested.
    ///
    /// A model match is not enough: when either side has a serial hash, both must match, even for
    /// old sessions, so two cameras of one model never share evidence. A session that reached no
    /// camera matches only an unreached report generated after it started.
    static func belongsToSessionBody(_ report: CameraCompatibilityReport, session: GuidedTestSession) -> Bool {
        guard let productName = session.cameraProductName else {
            return report.camera.productName == "(no camera reached)"
                && report.generatedAt >= session.startedAt
        }
        guard report.camera.productName == productName,
              report.camera.transport == session.transport else { return false }
        if report.camera.serialHash != nil || session.serialHash != nil {
            guard SerialHash.same(report.camera.serialHash, session.serialHash) else { return false }
        }
        return true
    }

    /// When an old report is unavailable, the tester's saved answers still make a useful report.
    /// They do not justify borrowing slots, firmware, conversions or logs from another camera.
    @MainActor
    static func sessionOnlyReport(_ session: GuidedTestSession) -> CameraCompatibilityReport {
        var report: CameraCompatibilityReport
        if let name = session.cameraProductName {
            report = .begin(productName: name, transport: session.transport ?? "unknown", usb: nil,
                            modelID: session.identifiedModelID, identification: session.identification ?? "unknown",
                            firmwareVersion: session.firmwareVersion, verification: session.verification,
                            assumedSlotCount: nil)
            // No `serialHashScheme`, because the session records none: the hash still matches this
            // body on this device, and `forSharing` drops it from anything shared.
            report.camera.serialHash = session.serialHash
        } else {
            report = .beginUnreached()
        }
        report.generatedAt = session.startedAt
        report.updatedAt = session.updatedAt
        report.connectionID = nil
        report.traceStartedAt = nil
        report.traceScope = "unavailable"
        report.note("The original camera diagnostics were unavailable for this test. Only the saved session evidence is included; app/device metadata describes report assembly.")
        return report
    }

    struct Export {
        var text: String
        var technicalText: String
        var cameraReport: CameraCompatibilityReport?

        /// Every export passes through here, so an unkeyed serial hash stored by an earlier build
        /// is in none of them: not the JSON, and not a text rendering frozen before the upgrade.
        /// See `CameraCompatibilityReport.forSharing`.
        init(text: String, technicalText: String, cameraReport: CameraCompatibilityReport?) {
            self.text = CameraCompatibilityReport.withoutUnkeyedSerialHashLines(text)
            self.technicalText = CameraCompatibilityReport.withoutUnkeyedSerialHashLines(technicalText)
            self.cameraReport = cameraReport?.forSharing
        }

        /// The camera report as the bytes Share attaches, for the Camera Data disclosure and its
        /// Copy button. The encoder sorts keys, so one report always encodes the same way.
        var cameraJSON: String? { cameraReport.map { String(decoding: $0.json, as: UTF8.self) } }

        /// `text` as the `.txt`, and `cameraReport` as the JSON beside it.
        func shareable(for presentation: DiagnosticsReportView.Presentation) -> ShareableReport {
            presentation == .standalone
                ? SupportMail.problemReport(text: text, cameraReport: cameraReport)
                : SupportMail.testResults(text: text, cameraReport: cameraReport)
        }
    }

    /// What a report screen shows, copies and shares. Report a Problem sends its capture as it
    /// is; a Camera Test sends the note-projected test results.
    func export(for presentation: DiagnosticsReportView.Presentation, note: String?,
                sessionID: String? = nil) -> Export {
        presentation == .standalone
            ? Export(text: reportText, technicalText: reportText, cameraReport: cameraReport)
            : testResults(note: note, sessionID: sessionID)
    }

    /// One projection feeds both attachments and the on-screen technical preview. The current
    /// note appears once in readable text and in the matching session's JSON, while earlier tests'
    /// notes remain historical evidence. Frozen camera evidence is never mutated by note edits.
    func testResults(note: String?, sessionID explicitSessionID: String? = nil) -> Export {
        let records = cameraReport?.guidedTests ?? []
        let targetID = explicitSessionID ?? sessionID ?? (records.count == 1 ? records[0].sessionID : nil)
        let recordIndex = targetID.flatMap { id in records.firstIndex { $0.sessionID == id } }
        let storedNote = recordIndex.flatMap { records[$0].freeText }
        let trimmed = (note ?? storedNote)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentNote = trimmed?.isEmpty == false ? trimmed : nil

        var exportedCamera = cameraReport
        var technicalCamera = cameraReport
        if let recordIndex {
            exportedCamera?.guidedTests?[recordIndex].freeText = currentNote
            // The note has its own visible section above the technical block. Keep it in JSON,
            // but omit this one copy from the rendering; do not erase notes from other sessions.
            technicalCamera?.guidedTests?[recordIndex].freeText = nil
        }
        var technicalText = reportText
        if let original = cameraReport, let technicalCamera, recordIndex != nil {
            let oldRendering = original.textRendering
            technicalText = reportText.contains(oldRendering)
                ? reportText.replacingOccurrences(of: oldRendering, with: technicalCamera.textRendering)
                : technicalCamera.textRendering
        }
        var lines = ["Fuji Cookbook — camera test results", "",
                     "Report captured: \(ISO8601DateFormatter().string(from: capturedAt))", "",
                     "— Test summary —"]
        lines += summary.isEmpty ? ["No check summary is available. See the recorded evidence below; missing checks are not passing checks."] : summary
        if let currentNote { lines += ["", "— Tester note —", currentNote] }
        lines += ["", "— Technical evidence —", technicalText]
        return Export(text: lines.joined(separator: "\n"), technicalText: technicalText,
                      cameraReport: exportedCamera)
    }

}

/// Readable results for a Camera Test, or the general problem report. Nothing is shared
/// until the user chooses to send; showing a report never completes or archives the test.
struct DiagnosticsReportView: View {
    enum Presentation: Equatable { case standalone, cameraTest }

    var presentation: Presentation = .standalone
    var snapshot: DiagnosticsReportSnapshot? = nil
    var sessionID: String? = nil
    var summary: [String] = []
    var note: Binding<String>? = nil
    var onSnapshot: ((DiagnosticsReportSnapshot) -> Void)? = nil
    var onShareOutcome: ((ReportShareOutcome) -> Void)? = nil

    @Environment(CameraServices.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloudStoreState) private var cloudStoreState
    @Environment(\.modelContext) private var modelContext

    @AppStorage(DiagnosticMode.key) private var diagnosticMode = false
    @AppStorage(FujiCookbookApp.iCloudSyncKey) private var iCloudSyncEnabled = false
    @State private var cameraReport: CameraCompatibilityReport?
    @State private var report = ""
    @State private var capturedSnapshot: DiagnosticsReportSnapshot?
    @State private var detailsExpanded = false
    @State private var cameraDataExpanded = false
    @State private var hasLoaded = false

    private var isGuided: Bool { presentation != .standalone }
    /// Share, both Copy buttons and both on-screen renderings read this one export, so the screen
    /// shows and copies exactly what Share attaches.
    private var export: DiagnosticsReportSnapshot.Export {
        capturedSnapshot?.export(for: presentation, note: note?.wrappedValue, sessionID: sessionID)
            ?? .init(text: report, technicalText: report, cameraReport: cameraReport)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if isGuided, let note { noteEditor(note) }
                sendButton.disabled(!hasLoaded)
                if isGuided {
                    guidedTestFooter
                    summaryCard
                    DisclosureGroup("Technical Details", isExpanded: $detailsExpanded) {
                        reportCard.padding(.top, 10)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                } else {
                    reportCard
                }
                exportButtons.disabled(!hasLoaded)
                if cameraReport != nil { cameraData }
            }
            .padding(18)
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle(isGuided ? "Review & Share Test Results" : "Report a Problem")
        .navigationBarTitleDisplayMode(.inline)
        .task { captureReport() }
    }

    private func captureReport() {
        guard !hasLoaded else { return }
        let captured: DiagnosticsReportSnapshot
        if let snapshot {
            captured = snapshot
        } else {
            cameraReport = camera.reports.report ?? CameraReportStore.loadLatest()
            captured = DiagnosticsReportSnapshot(capturedAt: Date(), reportText: assembleReport(),
                                                 cameraReport: cameraReport, summary: summary, sessionID: sessionID)
        }
        cameraReport = captured.cameraReport
        report = captured.reportText
        capturedSnapshot = captured
        hasLoaded = true
        if snapshot == nil { onSnapshot?(captured) }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your test results").font(.headline)
            if let capturedSnapshot, !capturedSnapshot.summary.isEmpty {
                ForEach(Array(capturedSnapshot.summary.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Open Technical Details to see the saved report.")
                    .font(.subheadline).foregroundStyle(DSColor.textSecondary)
            }
            Text("Your test progress stays saved when you share.")
                .font(.caption).foregroundStyle(DSColor.textSecondary)
        }
        .foregroundStyle(DSColor.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .themedCard(cornerRadius: 16)
    }

    private func noteEditor(_ note: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a note (optional)").font(.subheadline.weight(.semibold))
            TextEditor(text: note)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .accessibilityLabel("Optional note about your test")
        }
        .foregroundStyle(DSColor.textPrimary)
        .padding(14)
        .themedCard(cornerRadius: 16)
    }

    private var guidedTestFooter: some View {
        Button { dismiss() } label: {
            Label("Back to Camera Test", systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DSColor.signalText)
    }

    private var header: some View {
        Text([
            isGuided ? "Share your results even if everything worked: a clean run is as useful as one that finds a problem."
                     : "Read the report below, then share it with a note about what went wrong.",
            isGuided ? nil : "Includes app and device details, settings, and recent activity.",
            isGuided ? nil : cameraReport.map {
                $0.slots.reads.isEmpty
                    ? "It includes what your camera reported about itself and which film simulation was last written to each slot; its serial number is hashed."
                    : "It includes what your camera reported about itself and the recipes in its custom slots; its serial number is hashed."
            },
            isGuided ? "The report includes your answers, note, camera settings, app and device details, and camera activity. The camera’s serial number is coded; photos and file names are not attached." : nil,
            cameraReport == nil ? nil : (isGuided ? "Share both files: the text report and camera data (JSON)." : "Sharing includes readable text and a JSON copy of the camera evidence."),
            isGuided ? "Choose an app or Save to Files when the share sheet opens." : "Nothing is sent unless you send it.",
        ].compactMap { $0 }.joined(separator: " "))
            .font(.subheadline)
            .foregroundStyle(DSColor.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard(cornerRadius: 16)
    }

    private var sendButton: some View {
        ShareReportButton(title: isGuided ? "Share Test Results" : "Share This Report",
                          report: { export.shareable(for: presentation) },
                          preferAddressedMail: false,
                          onOutcome: onShareOutcome)
    }

    private var reportCard: some View {
        monospacedCard(export.technicalText)
    }

    /// The JSON attachment, verbatim. Collapsed by default: it is for the reader who wants to see
    /// every encoded field, including the few the text rendering leaves out.
    private var cameraData: some View {
        DisclosureGroup("Camera Data (JSON)", isExpanded: $cameraDataExpanded) {
            // Copy sits above the JSON: a full report runs to hundreds of lines.
            VStack(spacing: 10) {
                CopyButton(title: "Copy Camera Data", text: export.cameraJSON ?? "")
                    .buttonStyle(.outline)
                monospacedCard(export.cameraJSON ?? "")
            }
            .padding(.top, 10)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(DSColor.textPrimary)
    }

    /// In chunks, not one `Text`: a whole camera-report JSON in a single view renders blank.
    private func monospacedCard(_ text: String) -> some View {
        ReportTextColumn(text: text)
            .font(.caption.monospaced())
            .foregroundStyle(DSColor.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .themedCard(cornerRadius: 16)
    }

    private var exportButtons: some View {
        CopyButton(title: "Copy Report Text", text: export.text)
            .buttonStyle(.outline)
    }

    // MARK: The report

    /// The whole report, assembled once by `.task` into `report`.
    private func assembleReport() -> String {
        var lines = headerLines

        // The last camera the app talked to, in full — survives disconnect and relaunch, which is
        // the point: a tester opens this screen *after* the connect that went wrong.
        if let cameraReport {
            lines.append(contentsOf: ["", "— Camera compatibility report —", cameraReport.textRendering])
        }

        // Ahead of the ordinary previous-launch section, because it is the one a reader should see
        // first when it exists at all: `previous.log` is overwritten every launch, so a run that
        // ended unexpectedly is preserved separately and can be several launches old by now.
        let unexpected = AppLog.unexpectedExitText()
        if !unexpected.isEmpty {
            lines.append(contentsOf: ["", "— A session that ended unexpectedly —", unexpected])
        }

        // Before this launch's log, so the report reads forwards in time. This is the half that
        // survives a crash — see `AppLog.previousLaunchText`.
        let previous = AppLog.previousLaunchText()
        if !previous.isEmpty {
            lines.append(contentsOf: ["", "— Previous launch —", previous])
        }

        let current = AppLog.currentLaunchText()
        lines.append(contentsOf: ["", "— This launch —",
                                  current.isEmpty ? "(nothing logged yet)" : current])

        return lines.joined(separator: "\n")
    }

    /// Versions, settings and counts — the part every form of the report starts with.
    private var headerLines: [String] {
        var lines: [String] = [isGuided ? "Fuji Cookbook — camera test diagnostics" : "Fuji Cookbook — problem report", ""]
        lines += AppIdentity.reportLines
        lines.append("")
        lines.append("Sync         \(syncDescription)")
        lines.append("Diagnostics  \(diagnosticMode ? "on" : "off")")
        lines.append("")
        // `fetchCount`, not a `@Query`: the report prints only the numbers.
        lines.append("Recipes      \((try? modelContext.fetchCount(FetchDescriptor<Recipe>())).map(String.init) ?? "unavailable")")
        lines.append("Chapters     \((try? modelContext.fetchCount(FetchDescriptor<Chapter>())).map(String.init) ?? "unavailable")")
        lines.append("Camera       \(cameraDescription)")
        return lines
    }

    private var syncDescription: String {
        Self.syncDescription(syncEnabled: iCloudSyncEnabled, cloudStoreState: cloudStoreState)
    }

    /// The report's Sync value, from the sync preference and how the store came up at launch. A
    /// changed preference applies at the next launch, so when the two differ the value names both.
    /// A fallback names the failure in its bounded form only: the report leaves the device when the
    /// user shares it.
    static func syncDescription(syncEnabled: Bool, cloudStoreState: CloudStoreState) -> String {
        switch (syncEnabled, cloudStoreState) {
        case (false, .local), (false, .fellBack): return "off"
        case (false, .cloudKit): return "off from next launch — iCloud this launch"
        case (true, .cloudKit): return "on"
        case (true, .local): return "on from next launch — local this launch"
        case (true, .fellBack(let failure)): return "on, but fell back to local — \(failure.boundedDescription)"
        }
    }

    private var cameraDescription: String {
        guard let connected = camera.session.connected else { return "not connected" }
        let model = connected.registryModel?.id ?? connected.identification.confidence
        let firmware = connected.firmwareVersion.map { " fw \($0)" } ?? ""
        return "\(connected.productName) (\(model))\(firmware)"
    }
}
