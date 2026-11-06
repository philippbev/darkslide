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

/// App settings: display, iCloud sync, export, AI features and keys, help and feedback,
/// diagnostics, about.
struct SettingsView: View {
    @Environment(AISettings.self) private var settings
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
    @State private var showingAIConsent = false
    @State private var showingCredentialDeleteConfirm = false
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

    /// Progress of the "which models can this key use?" lookup.
    @State private var modelRefresh: ModelRefreshState = .idle

    private enum ModelRefreshState: Equatable {
        case idle, loading, failed(String), loaded(Int)
    }

    /// Whether this device is signed in to iCloud (needed for sync to actually move data).
    private var signedInToICloud: Bool { FileManager.default.ubiquityIdentityToken != nil }

    private var syncStatus: (text: String, icon: String, color: Color) {
        if !cloudStoreState.isCloudKit {
            return ("Local only", "icloud.slash", .secondary)
        } else if !signedInToICloud {
            return ("Not signed in to iCloud", "exclamationmark.icloud", Theme.warning)
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

    /// The hosted copy of `docs/privacy-policy.md`. App Store Connect lists the policy too, so a new
    /// URL needs changing there as well.
    private static let privacyPolicyURL = URL(string: "https://fujicookbook.grovehouse.xyz/app-privacy/")!

    private var privacyPolicyRow: some View {
        Link(destination: Self.privacyPolicyURL) {
            LabeledContent("Privacy Policy") {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private var aiFeaturesSection: some View {
        Section {
            Toggle("Enable AI Features", isOn: aiEnableBinding)
        } header: {
            Text("AI Features")
        } footer: {
            Text("Scan recipe screenshots with your chosen AI provider, using your own API key. Turning AI off keeps your keys and model choices.")
        }
    }

    /// Provider, key, and model pickers — everything that only means anything while AI is on.
    @ViewBuilder
    private var aiConfigurationSections: some View {
        // A local `@Bindable`, because the pickers below bind to `settings` and `@Environment` offers no `$settings`.
        @Bindable var settings = settings
        if settings.isEnabled {
            Section {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }
                SecureField(settings.provider.keyFieldLabel, text: $settings.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await refreshModels(force: true) } }
                if settings.hasAPIKey {
                    Button { Task { await refreshModels(force: true) } } label: {
                        HStack {
                            Label("Refresh Models", systemImage: "arrow.clockwise")
                            if modelRefresh == .loading {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(modelRefresh == .loading)
                    switch modelRefresh {
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    case .loaded(let count):
                        Text("\(count) model\(count == 1 ? "" : "s") available with this key.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .idle, .loading:
                        EmptyView()
                    }
                } else {
                    Label("Enter your API key to continue.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Get an API key at \(settings.provider.apiKeyPageAddress). Keys are stored in this device’s Keychain and sent only to their provider. Your provider’s terms and limits apply.")
            }

            Section {
                AIModelPicker(title: "Model", provider: settings.provider,
                              selection: $settings.modelID)
                if settings.hasAPIKey, !settings.hasScanningModel {
                    Label("Choose a model to start scanning.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                }
            } header: {
                Text("Recipe Scanning")
            } footer: {
                Text("Turn a screenshot into a recipe you can review. Screenshots are sent to \(settings.provider.displayName).")
            }

            if FeatureFlags.ideasEnabled {
                Section {
                    AIModelPicker(title: "Model", provider: settings.provider,
                                  selection: $settings.recommenderModelID)
                    if settings.hasAPIKey, !settings.hasRecommenderModel {
                        Label("Choose a model to get recommendations.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warning)
                    }
                } header: {
                    Text("Recipe Ideas")
                } footer: {
                    Text("The Ideas tab asks the model which of your recipes fit what you're shooting. It can use a different model than scanning — a more capable one helps here.")
                }
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
                    .foregroundStyle(Theme.warning)
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
        iCloud account. Restart to apply changes. Turning sync off keeps existing iCloud data. \
        AI settings stay on this device.
        """
    }

    /// Deletion for the keys, kept outside the `isEnabled` block on purpose: the whole point is
    /// that it stays reachable once AI is switched off, which is exactly when a user goes looking
    /// for it and when the rest of the AI configuration disappears.
    @ViewBuilder
    private var credentialsSection: some View {
        if settings.hasAnyStoredKey {
            Section {
                Button(role: .destructive) {
                    showingCredentialDeleteConfirm = true
                } label: {
                    Label("Delete API Keys", systemImage: "key.slash")
                }
            } footer: {
                Text(credentialDeleteFooter)
            }
        }
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
                Label("Report a Problem", systemImage: "exclamationmark.bubble")
            }
            NavigationLink {
                SendFeedbackView()
            } label: {
                Label("Send Feedback", systemImage: "text.bubble")
            }
        } header: {
            Text("Help & Feedback")
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
                Text(recoveryExportStatus).font(.caption).foregroundStyle(Theme.ink2)
            }
        } footer: {
            Text(clearDiagnosticsFooter)
        }
    }

    private var helpFooter: String {
        """
        Problem reports include diagnostic data. Feedback includes your message and app and \
        device details. Review everything before sharing. Nothing is sent automatically.
        """
    }

    private var clearDiagnosticsFooter: String {
        """
        Delete logs, queued screenshots and camera test data, including recovery backups and \
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
                Text("Created by Zachary Grimshaw and open source under the Apache License 2.0. The App Store version is published by Grove House Studio LLC.")
                Text("Fuji Cookbook is not affiliated with, endorsed by, or sponsored by FUJIFILM Corporation.")
            }
        }
    }

    @ViewBuilder
    private var diagnosticModeSection: some View {
        Section {
            Toggle("Show Diagnostic Tools", isOn: $diagnosticMode)
            if diagnosticMode {
                Label("Diagnostic tools are on the Camera and Kitchen tabs. Turning this off disconnects the Demo Camera.",
                      systemImage: "wrench.and.screwdriver")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

            aiFeaturesSection

            aiConfigurationSections

            credentialsSection

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
            // Keyed so it re-runs when AI is switched on, the provider changes, or the key field goes
            // between empty and non-empty, not on every keystroke. Pick a provider, paste a key, and
            // the real model list arrives behind the picker.
            .task(id: "\(settings.isEnabled)|\(settings.provider.rawValue)|\(settings.hasAPIKey)") {
                guard settings.isEnabled else { return }
                await refreshModels(force: false)
                adoptPreferredModels()
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
            .confirmationDialog("Delete API Keys?", isPresented: $showingCredentialDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    settings.deleteAllCredentials()
                    modelRefresh = .idle
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes \(credentialDeleteSubject) from this device and resets your model choices. To revoke these keys, delete them in your provider account too.")
            }
            .confirmationDialog("Clear Diagnostics?", isPresented: $showingDiagnosticsClearConfirm,
                                titleVisibility: .visible) {
                if !recoveryBackups.isEmpty {
                    Button("Export Camera Recovery Backups") { exportRecoveryBackups() }
                }
                Button("Clear Including Recovery Data", role: .destructive) { clearDiagnostics() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Erases current, previous and unexpected-exit logs, queued screenshots, Camera Test answers, saved report snapshots, and the original slot settings kept for test recovery. A test in progress is erased too.\n\nClearing removes the app's recovery backups and Undo Last Push. Export the originals first if you may need to restore the camera. Exporting does not erase anything; after saving the files, return here to choose Clear. A backup already saved outside the app is not affected.\n\nThe last camera report keeps the camera's identity and the film simulations written to its slots, and when, so later changes can still be flagged. Your recipe library and photos aren't touched.")
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
            .alert("Turn On AI Features?", isPresented: $showingAIConsent) {
                Button("Turn On") {
                    settings.isEnabled = true
                    UserDefaults.standard.set(Date(), forKey: AISettings.disclosureAcknowledgedDateKey)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("AI features send your data, including recipe screenshots shared from other apps, to your chosen provider (Anthropic or OpenAI) using your own API key. Your provider’s terms apply.\n\nEntering a key or switching providers may send that provider’s key to load available models. Fuji Cookbook never receives any of it.")
            }
    }

    private func presentingExport(_ content: some View) -> some View {
        content
            .confirmationDialog("Export Recipes and Chapters", isPresented: $showingBackupPhotoChoice, titleVisibility: .visible) {
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
                                    body: "Fuji Cookbook original camera backups. Save these files before clearing recovery data.",
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
        ScreenshotInbox.removeAll()
        ShareBundle.clearStaging()
        recoveryBackups = []
        recoveryExportStatus = nil
        diagnosticsCleared = true
    }

    /// "your Anthropic key" / "your Anthropic and OpenAI keys" / "all of your keys" — the dialog
    /// names what will actually go, because keys are stored per provider and the user may have more
    /// on the device than the picker is showing.
    private var credentialDeleteSubject: String {
        let names = settings.storedKeyProviders.map(\.displayName)
        switch names.count {
        case 0: return "your stored keys"
        case 1: return "your \(names[0]) key"
        case 2: return "your \(names[0]) and \(names[1]) keys"
        default: return "all of your keys"
        }
    }

    private var credentialDeleteFooter: String {
        let stored = settings.storedKeyProviders.count == 1
            ? "1 key saved on this device."
            : "\(settings.storedKeyProviders.count) keys saved on this device."
        return "\(stored) Deleting them also resets your model choices."
    }

    /// The Enable AI Features switch, gated: flipping it on presents the disclosure alert, and
    /// nothing is enabled until "Turn On" is tapped. No user data goes to an AI provider before
    /// that: key entry, in-app scans and the Share Extension all wait for this switch. Turning off
    /// stays immediate.
    private var aiEnableBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in
                if newValue { showingAIConsent = true } else { settings.isEnabled = false }
            }
        )
    }

    /// Ask the provider which models this key can actually use. Failure is never fatal: the
    /// picker keeps whatever it was already showing, so a refresh that can't reach the network
    /// leaves the user no worse off than before.
    private func refreshModels(force: Bool) async {
        let provider = settings.provider
        let key = settings.trimmedKey
        guard !key.isEmpty else {
            modelRefresh = .idle
            return
        }
        guard force || !AIModelCatalog.hasFetchedModels(for: provider) else { return }

        modelRefresh = .loading
        do {
            let models = try await AIModelCatalog.refresh(provider: provider, apiKey: key)
            modelRefresh = .loaded(models.count)
            adoptPreferredModels()
        } catch let error as AIClient.CallError {
            modelRefresh = .failed(error.summary(provider: provider))
        } catch {
            modelRefresh = .failed(error.localizedDescription)
        }
    }

    /// Choose a model for the current provider when the user hasn't, ranking whatever that
    /// provider actually returned. Never overrides an existing choice — including one typed into
    /// the custom field — so this only ever fills a blank.
    private func adoptPreferredModels() {
        let models = AIModelCatalog.models(for: settings.provider)
        guard !models.isEmpty else { return }
        if settings.modelID.isEmpty,
           let pick = AIModelCatalog.preferred(from: models, for: .scanning) {
            settings.modelID = pick
        }
        if settings.recommenderModelID.isEmpty,
           let pick = AIModelCatalog.preferred(from: models, for: .ideas) {
            settings.recommenderModelID = pick
        }
    }

    private var backupSection: some View {
        Section {
            // A note in place of the button, because a disabled tinted row still reads as tappable.
            if recipeCount == 0 {
                Text("Your library has no recipes to export yet.").foregroundStyle(.secondary)
            } else {
                Button { startBackup() } label: {
                    Label("Export Recipes and Chapters…", systemImage: "square.and.arrow.up.on.square")
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Save \(recipeCount) recipe\(recipeCount == 1 ? "" : "s") and \(chapterCount) chapter\(chapterCount == 1 ? "" : "s") in one file to restore later or on another device. Kitchen photos aren’t included.")
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
            backupRunner.start(snapshot, named: "Fuji Cookbook Backup") { result in
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

/// A model picker plus a free-text escape hatch.
///
/// The currently-selected id **always** gets a row. SwiftUI renders a blank selection, with no
/// warning at all, whenever the binding matches no child's tag — and between per-provider defaults,
/// fetched lists that vary by key, and ids typed in by hand, a selection outside the visible list
/// is routine here rather than exotic.
private struct AIModelPicker: View {
    let title: String
    let provider: AIProvider
    @Binding var selection: String

    private var rows: [AIModelInfo] {
        var models = AIModelCatalog.models(for: provider)
        if !selection.isEmpty, !models.contains(where: { $0.id == selection }) {
            models.insert(AIModelInfo(id: selection, displayName: selection), at: 0)
        }
        return models
    }

    var body: some View {
        if rows.isEmpty {
            // No list and no selection: say so rather than rendering an empty Picker, which
            // SwiftUI draws as a blank row with no explanation.
            LabeledContent(title) {
                Text("Add a key to load models").foregroundStyle(.secondary)
            }
        } else {
            Picker(title, selection: $selection) {
                ForEach(rows) { Text($0.displayName).tag($0.id) }
            }
        }
        DisclosureGroup("Enter Model ID") {
            TextField("Model ID", text: $selection)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
        }
    }
}
