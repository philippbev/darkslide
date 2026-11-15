import SwiftUI
import SwiftData

/// Carries how the SwiftData store came up at launch, set by the app.
private struct CloudStoreStateKey: EnvironmentKey {
    static let defaultValue = CloudStoreState.local
}

extension EnvironmentValues {
    var cloudStoreState: CloudStoreState {
        get { self[CloudStoreStateKey.self] }
        set { self[CloudStoreStateKey.self] = newValue }
    }
}

/// App settings: display, cameras, iCloud sync, export, help and feedback, diagnostics, about.
struct SettingsView: View {
    @Environment(CameraServices.self) private var camera
    @Environment(OwnedCameras.self) private var ownedCameras
    @Environment(\.cloudStoreState) private var cloudStoreState
    @Environment(\.dismiss) private var dismiss

    @Environment(\.modelContext) private var modelContext

    /// Library size for the Export section, counted in `.task`. A `@Query` would fetch every recipe
    /// and fault each one's photos to show two numbers; `fetchLibrary()` fetches the objects only
    /// when the user exports.
    @State private var recipeCount = 0
    @State private var chapterCount = 0

    /// Opt-in iCloud sync preference (off by default). Applied at the next launch — see `FujiCookbookApp`.
    @AppStorage(FujiCookbookApp.iCloudSyncKey) private var iCloudSyncEnabled = false

    /// Opt-in developer/diagnostic surfaces (off by default) — see `DiagnosticMode`.
    @AppStorage(DiagnosticMode.key) private var diagnosticMode = false

    /// Light, Dark or System (the default). `FujiCookbookApp` applies it — see `AppearancePreference`.
    @AppStorage(AppearancePreference.key, store: SharedDefaults.suite)
    private var appearance: AppearancePreference = .system

    @State private var showingRestartPrompt = false
    @State private var showingDiagnosticsClearConfirm = false
    /// Set after a successful Clear Diagnostics so the row can confirm it did something — the
    /// things it erases are all off-screen, so without this the tap has no visible effect at all.
    @State private var diagnosticsCleared = false
    @State private var diagnosticsError: String?
    @State private var recoveryBackups: [GuidedRecoveryRecord] = []
    @State private var recoveryExport: ShareBundle.Presented?
    @State private var recoveryExportStatus: String?
    @State private var backupShareItem: ShareItem?
    @State private var backupError: String?
    @State private var backupRunner = RecipeExportRunner()
    @State private var showingBackupPhotoChoice = false

    /// Whether this device is signed in to iCloud (needed for sync to actually move data).
    private var signedInToICloud: Bool { FileManager.default.ubiquityIdentityToken != nil }

    private var syncStatus: (text: String, icon: String, color: Color) {
        if !cloudStoreState.isCloudKit {
            return ("Local only", "icloud.slash", .secondary)
        } else if !signedInToICloud {
            return ("Not signed in to iCloud", "exclamationmark.icloud", DSColor.caution)
        } else {
            return ("Syncing via iCloud", "checkmark.icloud", .green)
        }
    }

    @ViewBuilder
    private var syncDiagnostics: some View {
        DisclosureGroup("Sync Details") {
            LabeledContent("Signed in to iCloud", value: signedInToICloud ? "Yes" : "No")
            Text("To delete existing iCloud data, open iOS Settings → your name → iCloud → Manage Account Storage.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if case .fellBack(let failure) = cloudStoreState {
                Text(failure.deviceOnlyDescription)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// Apple's standard Licensed Application EULA, which is what governs use of the app when it's
    /// installed from the App Store.
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// `docs/privacy-policy.md` as GitHub renders it. Darkslide isn't on the App Store, so this link
    /// is the only place the policy is published; if it moves (to bevier.cloud, say), only this
    /// URL changes.
    static let privacyPolicyURL = URL(string: "https://github.com/philippbev/darkslide/blob/main/docs/privacy-policy.md")!

    private var privacyPolicyRow: some View {
        Link(destination: Self.privacyPolicyURL) {
            LabeledContent("Privacy Policy") {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private var displaySection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("System follows the Light or Dark setting on this device.")
        }
    }

    private var myCamerasSection: some View {
        Section {
            NavigationLink {
                OwnedCamerasView()
            } label: {
                LabeledContent("My Cameras",
                               value: ownedCameras.modelIDs.isEmpty ? "None" : ownedCameras.modelIDs.joined(separator: ", "))
            }
        } header: {
            Text("Cameras")
        } footer: {
            Text("Your cameras come first on each recipe's Works With card and get their own chips in the Library filter. Connecting a camera adds it here.")
        }
    }

    private var iCloudSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: $iCloudSyncEnabled)
            LabeledContent("Status") {
                Label(syncStatus.text, systemImage: syncStatus.icon)
                    .foregroundStyle(syncStatus.color)
                    .labelStyle(.titleAndIcon)
            }
            if iCloudSyncEnabled != cloudStoreState.isCloudKit {
                Label("Restart the app to apply this change.", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(DSColor.caution)
            }
            syncDiagnostics
        } header: {
            Text("iCloud Sync")
        } footer: {
            Text(iCloudFooter)
        }
    }

    private var iCloudFooter: String {
        """
        Sync recipes, chapters, sample photos and Kitchen photos across devices using the same \
        iCloud account. Restart to apply changes. Turning sync off keeps existing iCloud data.
        """
    }

    /// Two Sections, because Clear Diagnostics needs its own footer: the first section's footer
    /// describes two rows with different payloads, and one footer covering the problem report alone
    /// would put a false sentence over Send Feedback.
    @ViewBuilder
    private var helpSection: some View {
        Section {
            NavigationLink {
                DiagnosticsReportView()
            } label: {
                Label(ReportSurfaces.current.diagnosticsTitle, systemImage: "exclamationmark.bubble")
            }
            if ReportSurfaces.current.showsSendFeedback {
                NavigationLink {
                    SendFeedbackView()
                } label: {
                    Label("Send Feedback", systemImage: "text.bubble")
                }
            }
        } header: {
            Text(ReportSurfaces.current.helpSectionTitle)
        } footer: {
            Text(helpFooter)
        }

        // Headerless on purpose: a continuation of the section above, and a header here would sit
        // two rows from the "Diagnostics" header on `diagnosticModeSection` and read as its twin.
        Section {
            Button(role: .destructive) {
                recoveryBackups = GuidedRecoveryStore.allRecords()
                showingDiagnosticsClearConfirm = true
            } label: {
                Label(diagnosticsCleared ? "Diagnostics Cleared" : "Clear Diagnostics",
                      systemImage: diagnosticsCleared ? "checkmark" : "trash")
            }
            .disabled(diagnosticsCleared || camera.session.status.isBusy)
            if let recoveryExportStatus {
                Text(recoveryExportStatus).font(.caption).foregroundStyle(DSColor.textSecondary)
            }
        } footer: {
            Text(clearDiagnosticsFooter)
        }
    }

    private var helpFooter: String {
        guard ReportSurfaces.current.reportsEnabled else {
            return """
            The diagnostics report shows app and device details, settings and recent activity. It \
            stays on this device.
            """
        }
        return """
        Problem reports include diagnostic data. Feedback includes your message and app and \
        device details. Review everything before sharing. Nothing is sent automatically.
        """
    }

    private var clearDiagnosticsFooter: String {
        """
        Delete logs and camera test data, including recovery backups and \
        Undo Last Push. Export recovery backups first if needed. Recipes and photos stay saved.
        """
    }

    /// Acknowledgments is a screen rather than a link because the app's license and its credits
    /// have to travel with the app.
    @ViewBuilder
    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: AppIdentity.versionString)
            NavigationLink("Acknowledgments") { AcknowledgmentsView() }
            privacyPolicyRow
            Link(destination: Self.termsOfUseURL) {
                LabeledContent("Terms of Use") {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                }
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Darkslide is an independent fork of Fuji Cookbook, created by Zachary Grimshaw and open source under the Apache License 2.0. It is not affiliated with Fuji Cookbook's authors or Grove House Studio LLC.")
                Text("Darkslide is not affiliated with, endorsed by, or sponsored by FUJIFILM Corporation.")
            }
        }
    }

    @ViewBuilder
    private var diagnosticModeSection: some View {
        Section {
            Toggle("Show Diagnostic Tools", isOn: $diagnosticMode)
            if diagnosticMode {
                Label("Diagnostic tools are on the Camera and Darkroom tabs. Turning this off disconnects the Demo Camera.",
                      systemImage: "wrench.and.screwdriver")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    DesignSystemGallery()
                } label: {
                    Label("Design System", systemImage: "swatchpalette")
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Show the Demo Camera, camera reports, write tests and photo profile details.")
        }
    }

    // Each section is its own property, and body's modifiers are split across `form` and the functions
    // below it: as one expression, body exceeds the type checker's time limit in Xcode 26.6, which CI
    // builds with, and the build fails.
    var body: some View {
        NavigationStack {
            presentingExport(presentingToggleAlerts(presentingDeletionDialogs(runningTasks(form))))
        }
    }

    private var form: some View {
        Form {
            displaySection

            myCamerasSection

            iCloudSection

            backupSection

            helpSection

            diagnosticModeSection

            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func runningTasks(_ content: some View) -> some View {
        content
            .task {
                recipeCount = (try? modelContext.fetchCount(FetchDescriptor<Recipe>())) ?? 0
                chapterCount = (try? modelContext.fetchCount(FetchDescriptor<Chapter>())) ?? 0
            }
            // Prompt only when the new setting actually differs from the running store (a real
            // pending change). Flipping back to the current state won't nag.
            .onChange(of: iCloudSyncEnabled) { _, newValue in
                showingRestartPrompt = (newValue != cloudStoreState.isCloudKit)
            }
            // Turning diagnostics off while the Demo Camera is connected would leave a session the
            // user can no longer reach the entry point for — drop it so the Camera tab reads clean.
            .onChange(of: diagnosticMode) { _, newValue in
                guard !newValue, camera.session.connected?.isDemo == true else { return }
                Task { await camera.connector.disconnect() }
            }
    }

    private func presentingDeletionDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog("Clear Diagnostics?", isPresented: $showingDiagnosticsClearConfirm,
                                titleVisibility: .visible) {
                if !recoveryBackups.isEmpty {
                    Button("Export Camera Recovery Backups") { exportRecoveryBackups() }
                }
                Button("Clear Including Recovery Data", role: .destructive) { clearDiagnostics() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Erases current, previous and unexpected-exit logs, Camera Test answers, saved report snapshots, and the original slot settings kept for test recovery. A test in progress is erased too.\n\nClearing removes the app's recovery backups and Undo Last Push. Export the originals first if you may need to restore the camera. Exporting does not erase anything; after saving the files, return here to choose Clear. A backup already saved outside the app is not affected.\n\nThe last camera report keeps the camera's identity and the film simulations written to its slots, and when, so later changes can still be flagged. Your recipe library and photos aren't touched.")
            }
            .sheet(item: $recoveryExport) { bundle in
                ReportShareSheet(items: bundle.items) { outcome in
                    recoveryExport = nil
                    recoveryExportStatus = outcome == .shared
                        ? "Backup files were handed to the selected app. Check that you saved them before clearing; no data has been erased."
                        : "Recovery data has not been erased. You can export again or cancel clearing."
                    if outcome == .failed {
                        diagnosticsError = "The backup export did not complete. The original recovery data is still saved; try exporting again before clearing."
                    }
                }
            }
            .alert("Diagnostics Could Not Be Cleared", isPresented: Binding(isPresent: $diagnosticsError)) {
                Button("OK", role: .cancel) {}
            } message: { Text(diagnosticsError ?? "") }
    }

    private func presentingToggleAlerts(_ content: some View) -> some View {
        content
            .alert("Restart to Apply", isPresented: $showingRestartPrompt) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("iCloud sync turns \(iCloudSyncEnabled ? "on" : "off") the next time the app starts. To quit, swipe up from the bottom of the screen and swipe the app away.")
            }
    }

    private func presentingExport(_ content: some View) -> some View {
        content
            .confirmationDialog("Export Recipes and Rolls", isPresented: $showingBackupPhotoChoice, titleVisibility: .visible) {
                Button("Include Sample Photos") { performBackup(includePhotos: true) }
                Button("Without Sample Photos") { performBackup(includePhotos: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Including photos makes the file larger.")
            }
            .sheet(item: $backupShareItem) { ShareSheet(items: $0.urls) }
            .alert("Export Failed", isPresented: Binding(isPresent: $backupError)) {
                Button("OK", role: .cancel) {}
            } message: { Text(backupError ?? "") }
            .exportProgress(backupRunner)
    }

    /// Export the actual original CameraBackup values, not today's slots or the last push's
    /// predecessor. Each file is the format Restore a Slot reads, named by session so two backups
    /// captured in the same minute don't collide.
    private func exportRecoveryBackups() {
        let files = recoveryBackups.map(\.exportFile)
        guard let first = files.first else { return }
        let report = ShareableReport(kind: .backup, address: "",
                                    body: "Darkslide original camera backups. Save these files before clearing recovery data.",
                                    fileName: first.fileName, data: first.data,
                                    mimeType: "application/json", extraFiles: Array(files.dropFirst()))
        do {
            recoveryExport = ShareBundle.Presented(kind: report.kind, items: try ShareBundle.items(for: report))
            recoveryExportStatus = "Exporting does not erase recovery data. Save the backup files before choosing Clear."
        } catch {
            diagnosticsError = "Recovery backups couldn't be prepared for export. Nothing was erased. \(error.localizedDescription)"
        }
    }

    private func clearDiagnostics() {
        guard !camera.session.status.isBusy else {
            diagnosticsError = "Wait for the current camera operation to finish before clearing its recovery data."
            return
        }
        // Recovery is a separate operational store. Never announce success after its removal
        // failed, or erase the test/log context needed to explain the outstanding originals.
        guard GuidedRecoveryStore.deleteAll() else {
            diagnosticsError = "Camera recovery records couldn't be removed. Your test records and logs were kept. Try again."
            return
        }
        GuidedTestStore.deleteAll()
        let remaining = [GuidedTestStore.latestURL, GuidedTestStore.historyURL].compactMap { $0 }
            .contains { FileManager.default.fileExists(atPath: $0.path) }
        guard !remaining else {
            diagnosticsError = "Camera recovery records were removed, but some saved tests or report snapshots couldn't be deleted. Logs were kept. Try again to finish clearing."
            return
        }
        AppLog.eraseFiles()
        CameraReportStore.stripLatestToDriftBaseline()
        camera.reports.clear()
        ShareBundle.clearStaging()
        recoveryBackups = []
        recoveryExportStatus = nil
        diagnosticsCleared = true
    }

    private var backupSection: some View {
        Section {
            // A note in place of the button, because a disabled tinted row still reads as tappable.
            if recipeCount == 0 {
                Text("Your library has no recipes to export yet.").foregroundStyle(.secondary)
            } else {
                Button { startBackup() } label: {
                    Label("Export Recipes and Rolls…", systemImage: "square.and.arrow.up.on.square")
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Save \(recipeCount) recipe\(recipeCount == 1 ? "" : "s") and \(chapterCount) roll\(chapterCount == 1 ? "" : "s") in one file to restore later or on another device. Darkroom photos aren’t included.")
        }
    }

    /// The full library, fetched on demand when the user actually exports — the only moment this
    /// screen needs more than the counts.
    private func fetchLibrary() throws -> (recipes: [Recipe], chapters: [Chapter]) {
        (try modelContext.fetch(FetchDescriptor<Recipe>()),
         try modelContext.fetch(FetchDescriptor<Chapter>()))
    }

    /// Ask about photos only when some recipe has them; otherwise export straight away.
    private func startBackup() {
        let recipes: [Recipe]
        do {
            recipes = try fetchLibrary().recipes
        } catch {
            backupError = error.localizedDescription
            return
        }
        if recipes.contains(where: { !$0.sortedPhotos.isEmpty }) {
            showingBackupPhotoChoice = true
        } else {
            performBackup(includePhotos: false)
        }
    }

    private func performBackup(includePhotos: Bool) {
        do {
            let (recipes, chapters) = try fetchLibrary()
            let snapshot = RecipeExportSnapshot.backup(recipes: recipes, chapters: chapters,
                                                       includePhotos: includePhotos)
            backupRunner.start(snapshot, named: "Darkslide Backup") { result in
                switch result {
                case .success(let url): backupShareItem = ShareItem(url: url)
                case .failure(let error): backupError = error.localizedDescription
                }
            }
        } catch {
            backupError = error.localizedDescription
        }
    }

}
