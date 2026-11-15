import SwiftUI
import SwiftData

/// A Chapter's slots at a glance, with the actions to edit it or push the whole set to the camera.
/// The push reuses the standard safe-write flow (`PushView`) with the chapter's slot order pre-filled.
struct ChapterDetailView: View {
    @Bindable var chapter: Chapter

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CameraServices.self) private var camera
    @Environment(AISettings.self) private var aiSettings
    @Environment(AppRouter.self) private var router
    @Query(Recipe.listFetch(sortBy: [SortDescriptor(\Recipe.name)])) private var allRecipes: [Recipe]

    @State private var showingEditor = false
    @State private var showingPush = false
    @State private var showingDeleteConfirm = false
    @State private var showingShareOptions = false
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var exportRunner = RecipeExportRunner()

    @AppStorage(RememberedCamera.displayNameKey) private var rememberedName = ""
    @AppStorage(RememberedCamera.slotCountKey) private var rememberedSlotCount = 0

    private func recipe(for id: UUID) -> Recipe? { allRecipes.first { $0.uuid == id } }
    private var isEmpty: Bool { chapter.recipeUUIDs.isEmpty }

    private var canPush: Bool { camera.slotWriter.canPush }

    /// The recipes a shared file would carry: the chapter's slots that still have a recipe.
    private var shareableRecipes: [Recipe] { chapter.recipeUUIDs.compactMap(recipe(for:)) }

    /// The camera this chapter's slots are measured against: the connected one when it can be pushed
    /// to, else the last one that could. Nil when there is no such camera, or while a connected body
    /// can't be pushed to — the push row already says why, and another camera's slot count would
    /// only muddle it.
    private var slotFit: (camera: RememberedCamera, isConnected: Bool)? {
        if camera.session.isConnected {
            guard canPush, let model = camera.session.model,
                  let live = RememberedCamera(displayName: model.displayName, slotCount: camera.slotReader.effectiveSlotCount)
            else { return nil }
            return (live, true)
        }
        return RememberedCamera(displayName: rememberedName, slotCount: rememberedSlotCount).map { ($0, false) }
    }

    /// Slots this chapter fills that `slotFit`'s camera doesn't have.
    private var slotsLeftOut: [Int] { slotFit.map { chapter.slotsBeyond($0.camera.slotCount) } ?? [] }

    private var freeSlots: Int { max(Chapter.maxSlots - chapter.recipeUUIDs.count, 0) }

    /// Only with something to build around, room to grow, library recipes outside the chapter, and
    /// the recommender set up (`AISettings.canRecommend`). Also gated on `FeatureFlags.ideasEnabled`,
    /// since the row jumps to the Ideas tab, which is hidden without it.
    private var canFillOut: Bool {
        FeatureFlags.ideasEnabled && !isEmpty && chapter.hasFreeSlot && aiSettings.canRecommend
            && allRecipes.count > chapter.recipeUUIDs.count
    }

    /// Why the chapter can't be pushed right now, or nil when the push row is live. A note in place
    /// of the button, because a disabled tinted row still reads as tappable.
    private var pushBlockedReason: String? {
        if isEmpty { return "Add recipes to this roll to push it." }
        // The Connect row sits right below this, so the note only has to name the blocker.
        if !camera.session.isConnected { return "Connect a camera to push this roll." }
        if !canPush {
            return camera.slotWriter.pushBlockReason ?? "Push isn't available for \(camera.session.model?.displayName ?? "this camera")."
        }
        return nil
    }

    var body: some View {
        List {
            Section {
                if isEmpty {
                    Text("This roll has no recipes yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(chapter.recipeUUIDs.enumerated()), id: \.element) { index, id in
                        LabeledContent {
                            Text(recipe(for: id)?.name ?? "Missing recipe")
                                .foregroundStyle(recipe(for: id) == nil ? .red : .secondary)
                        } label: {
                            Text("C\(index + 1)")
                            if let fit = slotFit, slotsLeftOut.contains(index + 1) {
                                Text("Not on the \(fit.camera.displayName)")
                            }
                        }
                    }
                }
            } header: {
                Text("Slots (\(chapter.recipeUUIDs.count)/\(Chapter.maxSlots))")
            } footer: {
                if let fit = slotFit, !slotsLeftOut.isEmpty {
                    Text("Pushing writes each recipe to the matching custom slot (C1, C2, …) on the connected camera. The \(fit.camera.displayName)\(fit.isConnected ? "" : " you last connected") has \(fit.camera.slotCount) custom slots, so \(Chapter.slotRunLabel(slotsLeftOut)) \(slotsLeftOut.count == 1 ? "is" : "are") left out.")
                } else {
                    Text("Pushing writes each recipe to the matching custom slot (C1, C2, …) on the connected camera.")
                }
            }

            if canFillOut {
                Section {
                    Button { fillOutWithIdeas() } label: {
                        Label("Fill Out with Ideas…", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Pins these \(chapter.recipeUUIDs.count) recipes and asks the model to fill the remaining \(freeSlots) slot\(freeSlots == 1 ? "" : "s") with library recipes that cover what they don't.")
                }
            }

            Section {
                if let reason = pushBlockedReason {
                    Text(reason).foregroundStyle(.secondary)
                } else {
                    Button { showingPush = true } label: {
                        Label("Push Roll to Camera…", systemImage: "square.and.arrow.up")
                    }
                }
                // An empty chapter has nothing to push regardless of the camera, so the connection
                // prompt would just be noise there.
                if !isEmpty, !camera.session.isConnected {
                    ConnectInCameraTabButton()
                }
            }
        }
        .navigationTitle(chapter.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button { initiateShare() } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                        .disabled(shareableRecipes.isEmpty)
                    Divider()
                    Button(role: .destructive) { showingDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { ChapterEditorView(chapter: chapter, isNew: false) }
        }
        .sheet(isPresented: $showingPush) {
            NavigationStack {
                PushView(preselectedRecipe: nil, preassignedSlots: chapter.slotAssignments)
            }
        }
        .sheet(item: $shareItem) { ShareSheet(items: $0.urls) }
        .confirmationDialog("Share Roll", isPresented: $showingShareOptions, titleVisibility: .visible) {
            Button("Include Sample Photos") { share(includePhotos: true) }
            Button("Recipes Only") { share(includePhotos: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file holds this roll and its recipes. Opening it in Darkslide restores both.")
        }
        .alert("Export Failed", isPresented: Binding(isPresent: $exportError)) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .exportProgress(exportRunner)
        .confirmationDialog("Delete “\(chapter.name)”?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Roll", role: .destructive) {
                modelContext.delete(chapter)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the roll only. The recipes in it stay in your library.")
        }
    }

    /// Ask whether to embed photos when a recipe in the chapter has any; otherwise export straight
    /// away.
    private func initiateShare() {
        if shareableRecipes.contains(where: { !$0.sortedPhotos.isEmpty }) { showingShareOptions = true }
        else { share(includePhotos: false) }
    }

    private func share(includePhotos: Bool) {
        guard let snapshot = RecipeExportSnapshot.chapter(chapter, recipes: allRecipes,
                                                          includePhotos: includePhotos) else { return }
        exportRunner.start(snapshot, named: chapter.name) { result in
            switch result {
            case .success(let url): shareItem = ShareItem(url: url)
            case .failure(let error): exportError = error.localizedDescription
            }
        }
    }

    /// Hand this chapter to the Ideas tab with its recipes pinned, so the model fills the free slots.
    /// Nothing here changes until the user acts on the result.
    private func fillOutWithIdeas() {
        router.ideaSeed = IdeaSeed(anchorUUIDs: chapter.recipeUUIDs,
                                   slotTarget: Chapter.maxSlots,
                                   sourceChapter: IdeaSeed.SourceChapter(chapter))
        router.selectedTab = .ideas
    }
}
