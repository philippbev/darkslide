import SwiftUI
import SwiftData

/// Top-level tab layout: Recipes, Chapters, Ideas (behind a flag), Kitchen and Camera.
struct RootView: View {
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(AISettings.self) private var aiSettings
    @Environment(CameraServices.self) private var camera
    @Environment(OwnedCameras.self) private var ownedCameras
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    /// Seeded from the launch-time detection. The banner's buttons also `acknowledge()` it, so a
    /// window opened later doesn't show the banner again.
    @State private var showUnexpectedExit = SessionTermination.previousLaunchEndedUnexpectedly
    @State private var showingUnexpectedExitReport = false

    var body: some View {
        @Bindable var coordinator = importCoordinator
        @Bindable var router = router

        tabs(selection: $router.selectedTab)
        .safeAreaInset(edge: .top) { unexpectedExitBanner }
        .sheet(isPresented: $showingUnexpectedExitReport) {
            NavigationStack { DiagnosticsReportView() }
        }
        .environment(router)
        // On the connection, not on the tabs' redraws: a removal in My Cameras holds until that
        // camera next connects, and a recovery re-assigns an equal value and so does not fire this.
        .onChange(of: camera.session.connected) { _, connected in
            if let connected { ownedCameras.noteConnected(connected) }
        }
        .sheet(item: $coordinator.pendingImport) { pending in
            ImportReviewView(pending: pending)
        }
        .alert("Couldn't Import Recipe",
               isPresented: Binding(isPresent: $coordinator.importError)) {
            Button("OK", role: .cancel) { coordinator.importError = nil }
        } message: {
            Text(coordinator.importError ?? "")
        }
        // The Share Extension can't open the app, so its work is picked up here, on launch and on
        // each return to the foreground: recipes it saved to the store, then screenshots it queued.
        .task {
            ShareExtensionSaves.adopt(into: modelContext)
            // After the extension's work is adopted, so a recipe it saved counts as a library in use.
            await StarterRecipe.seedIfNeeded(into: modelContext)
            await importCoordinator.processSharedScreenshots(using: aiSettings)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Before the inbox drain, not after: the extension may have saved a recipe while we were
            // backgrounded, and this context still has the library as it was before that.
            ShareExtensionSaves.adopt(into: modelContext)
            importCoordinator.startSharedScreenshotScan(using: aiSettings)
        }
        .blockingProgress("Reading shared screenshot…", isPresented: coordinator.isScanningSharedScreenshots)
        .overlay {
            if coordinator.isPreparingImport {
                CancellableProgressOverlay(
                    title: "Preparing recipes…",
                    detail: coordinator.importProgress.map { "\($0.completed) of \($0.total) recipes" },
                    onCancel: coordinator.cancelImport)
            }
        }
    }

    /// The app has no crash reporter, so this banner is the only thing that can ask for a report at
    /// the moment one is worth most — the launch straight after a session that died.
    ///
    /// **"Ended unexpectedly", never "crashed."** A marker left behind by a foreground death covers
    /// a crash and a foreground jetsam kill, and nothing here can tell them apart, so naming it a
    /// crash would be a claim the code can't support. See `SessionTermination`.
    ///
    /// Dismissal hides the banner and leaves the evidence alone: `previous.log` was already copied
    /// somewhere that never rolls, and a person tapping "Dismiss" is not a person saying the evidence
    /// can go. Clear Diagnostics is what erases it.
    @ViewBuilder
    private var unexpectedExitBanner: some View {
        if showUnexpectedExit {
            VStack(alignment: .leading, spacing: 8) {
                Label("The last session ended unexpectedly", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Fuji Cookbook closed on its own while you were using it. Its log was kept, and a report is the only way this gets fixed.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                HStack(spacing: 16) {
                    Button("Report a Problem") {
                        showingUnexpectedExitReport = true
                        showUnexpectedExit = false
                        SessionTermination.acknowledge()
                    }
                    .font(.subheadline.weight(.semibold))
                    Button("Dismiss") {
                        showUnexpectedExit = false
                        SessionTermination.acknowledge()
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.paper)
            .themedCard(cornerRadius: 16)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    /// Tab layout. On iOS 18+ we use the sidebar-adaptable style (sidebar on iPad, bottom bar on
    /// iPhone) so the Library nav bar keeps full width and its filter + add buttons stay visible
    /// instead of collapsing into the system overflow menu. iOS 17 falls back to the classic tab bar.
    @ViewBuilder
    private func tabs(selection: Binding<AppTab>) -> some View {
        if #available(iOS 18.0, *) {
            TabView(selection: selection) {
                Tab("Recipes", systemImage: "tray.full", value: AppTab.library) {
                    LibraryView()
                }
                Tab("Chapters", systemImage: "books.vertical", value: AppTab.chapters) {
                    ChaptersListView()
                }
                if FeatureFlags.ideasEnabled {
                    Tab("Ideas", systemImage: "sparkles", value: AppTab.ideas) {
                        RecommenderView()
                    }
                }
                Tab("Kitchen", systemImage: "frying.pan", value: AppTab.kitchen) {
                    KitchenView()
                }
                Tab("Camera", systemImage: "cable.connector", value: AppTab.camera) {
                    CameraView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: selection) {
                LibraryView()
                    .tabItem { Label("Recipes", systemImage: "tray.full") }
                    .tag(AppTab.library)

                ChaptersListView()
                    .tabItem { Label("Chapters", systemImage: "books.vertical") }
                    .tag(AppTab.chapters)

                if FeatureFlags.ideasEnabled {
                    RecommenderView()
                        .tabItem { Label("Ideas", systemImage: "sparkles") }
                        .tag(AppTab.ideas)
                }

                KitchenView()
                    .tabItem { Label("Kitchen", systemImage: "frying.pan") }
                    .tag(AppTab.kitchen)

                CameraView()
                    .tabItem { Label("Camera", systemImage: "cable.connector") }
                    .tag(AppTab.camera)
            }
        }
    }
}
