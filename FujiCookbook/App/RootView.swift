import SwiftUI
import SwiftData

/// Top-level tab layout: Recipes, Rolls, Darkroom and Camera. The labels follow
/// the darkroom vocabulary (design system v2.6); the types behind them keep their old names for now.
struct RootView: View {
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(CameraServices.self) private var camera
    @Environment(OwnedCameras.self) private var ownedCameras
    @Environment(\.modelContext) private var modelContext
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
        .focusedSceneValue(\.appRouter, router)
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
        .task {
            await StarterRecipe.seedIfNeeded(into: modelContext)
        }
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
                    .foregroundStyle(DSColor.textPrimary)
                Text(ReportSurfaces.current.reportsEnabled
                     ? "Darkslide closed on its own while you were using it. Its log was kept, and a report is the only way this gets fixed."
                     : "Darkslide closed on its own while you were using it. Its log was kept in the diagnostics report.")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
                HStack(spacing: 16) {
                    Button(ReportSurfaces.current.unexpectedExitAction) {
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
                    .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(DSColor.background)
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
                Tab("Recipes", systemImage: "rectangle.stack", value: AppTab.library) {
                    LibraryView()
                }
                Tab("Rolls", systemImage: "film", value: AppTab.chapters) {
                    ChaptersListView()
                }
                Tab("Darkroom", systemImage: "camera.filters", value: AppTab.kitchen) {
                    KitchenView()
                }
                Tab("Camera", systemImage: "camera.aperture", value: AppTab.camera) {
                    CameraView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: selection) {
                LibraryView()
                    .tabItem { Label("Recipes", systemImage: "rectangle.stack") }
                    .tag(AppTab.library)

                ChaptersListView()
                    .tabItem { Label("Rolls", systemImage: "film") }
                    .tag(AppTab.chapters)

                KitchenView()
                    .tabItem { Label("Darkroom", systemImage: "camera.filters") }
                    .tag(AppTab.kitchen)

                CameraView()
                    .tabItem { Label("Camera", systemImage: "camera.aperture") }
                    .tag(AppTab.camera)
            }
        }
    }
}
