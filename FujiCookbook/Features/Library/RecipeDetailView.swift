import SwiftUI
import SwiftData
import UIKit

/// Read-only view of a saved recipe as an archive card — its number, the parameters it sets, its
/// slot name, which cameras run it — with its actions in a floating bar.
struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CameraServices.self) private var camera
    @Environment(AppRouter.self) private var router

    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var exportRunner = RecipeExportRunner()
    @State private var showingPush = false
    @State private var viewerIndex: Int?
    @State private var showingExportOptions = false
    @State private var showingCompare = false

    @Environment(OwnedCameras.self) private var ownedCameras
    /// By name, like the Library's chapter keys.
    @Query(sort: \Chapter.name) private var allChapters: [Chapter]
    /// The camera's slots as last read, for the SLOT field (`CameraSlotSnapshot`).
    @AppStorage(CameraSlotSnapshot.storageKey) private var slotSnapshotsJSON = ""
    @AppStorage(RememberedCamera.displayNameKey) private var rememberedCameraName = ""

    private var chapters: [Chapter] { allChapters.filter { $0.recipeUUIDs.contains(recipe.uuid) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.block) {
                archiveCard
                tags
                photos
                if !recipe.notes.isEmpty {
                    DSArchiveSection(title: "Notes") {
                        Text(recipe.notes)
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                DSArchiveSection(title: "Works With") {
                    RecipeWorksWithCard(settings: recipe.settings,
                                        hasPreservedFields: recipe.hasPreservedUnsupportedFields)
                }
                if recipe.hasPreservedUnsupportedFields {
                    preservedFields
                }
            }
            .padding(DSSpacing.screenMargin)
        }
        .background(DSColor.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { actionBar }
        // The name lives in the archive card; keep the bar title empty so it doesn't appear twice.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { recipe.isFavorite.toggle(); recipe.touch() } label: {
                    Image(systemName: recipe.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(recipe.isFavorite ? DSColor.textPrimary : DSColor.textSecondary)
                }
                .accessibilityLabel(recipe.isFavorite ? "Unfavorite" : "Favorite")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button { duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    // "Compare Settings", not "Compare": the Kitchen already offers to compare
                    // recipes, and means the developed images. This is the parameters.
                    Button { showingCompare = true } label: {
                        Label("Compare Settings…", systemImage: "arrow.left.arrow.right")
                    }
                    // The two sharing actions read as a pair: the visual card, then the file.
                    Button { openShareCard() } label: {
                        Label("Share Card…", systemImage: "photo.on.rectangle.angled")
                    }
                    Button { initiateShare() } label: { Label("Share / Export", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive) { showingDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingCompare) {
            RecipeCompareView(recipeA: recipe)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { RecipeEditorView(recipe: recipe, isNew: false) }
        }
        .sheet(item: $shareItem) { ShareSheet(items: $0.urls) }
        .sheet(isPresented: $showingPush) {
            NavigationStack { PushView(preselectedRecipe: recipe) }
        }
        .fullScreenCover(isPresented: Binding(isPresent: $viewerIndex)) {
            PhotoViewerView(photos: recipe.sortedPhotos, selection: viewerIndex ?? 0)
        }
        .confirmationDialog("Share Recipe", isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button("Include Sample Photos") { share(includePhotos: true) }
            Button("Recipe Only") { share(includePhotos: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Embedding photos makes the shared file larger.")
        }
        .confirmationDialog("Delete “\(recipe.name)”?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Recipe", role: .destructive) {
                modelContext.delete(recipe)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert("Export Failed", isPresented: Binding(isPresent: $exportError)) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .exportProgress(exportRunner)
    }

    // MARK: Archive card

    /// The recipe as an archive object: number and side fields, name and credit, the simulation's
    /// band, the settings, the slot name on a line of its own, and the barcode with the verdict for
    /// the user's camera.
    private var archiveCard: some View {
        let slotName = RecipeDetailArchive.slotNameField(name: recipe.effectiveCameraName,
                                                         isCustom: recipe.hasCustomCameraName)
        return DSArchiveCard {
            DSArchiveHeader(objectNumber: RecipeRow.objectNumber(recipe.archiveNumber),
                            fields: RecipeDetailArchive.sideFields(slot: lastReadSlot,
                                                                   chapterNames: chapters.map(\.name),
                                                                   createdAt: recipe.createdAt))
            DSRule()
            DSArchiveTitle(title: recipe.name, description: recipe.displayCredit.map { "Recipe by \($0)" })
            DSSimulationBand(simulation: recipe.settings.filmSimulation)
            DSDataSheet(fields: RecipeDetailArchive.dataSheetFields(for: recipe.settings))
            // Full width: a slot name runs up to 25 characters.
            DSSeparator()
            DSDataFieldCell(field: slotName)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
            DSRule()
            DSArchiveFooter(barcodeSeed: recipe.uuid.uuidString, text: footer)
        }
    }

    /// The slot the camera held this recipe in when last read; nil when it wasn't there, or the
    /// camera was never read.
    private var lastReadSlot: String? {
        CameraSlotSnapshot.all(from: slotSnapshotsJSON)[rememberedCameraName]?
            .slotLabels(for: [recipe])[recipe.uuid]
    }

    /// The verdict for the user's first camera, else the body the recipe was written for.
    private var footer: String {
        guard let model = ownedCameras.models.first ?? recipe.authoredForModel else { return "" }
        return RecipeDetailArchive.footer(cameraID: model.id, verdict: RecipeCameraFit(recipe.settings, on: model).verdict)
    }

    /// The chapters the recipe is in, then its own tags.
    @ViewBuilder
    private var tags: some View {
        if !chapters.isEmpty || !recipe.tags.isEmpty {
            DSFlowLayout {
                ForEach(chapters) { DSTag(text: $0.name, systemImage: "books.vertical") }
                ForEach(recipe.tags, id: \.self) { DSTag(text: "#\($0)") }
            }
        }
    }

    /// The sample photos as a strip of frames; a tap opens the full viewer.
    @ViewBuilder
    private var photos: some View {
        let photos = recipe.sortedPhotos
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("Photos   \(photos.count)").dsMetaMono(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSize.contactSheetSpacing) {
                        ForEach(Array(photos.enumerated()), id: \.element.uuid) { index, photo in
                            Button { viewerIndex = index } label: {
                                DSColor.panel
                                    .frame(width: 132, height: 88)
                                    .overlay {
                                        // Cached by uuid so the decode doesn't repeat on every body pass.
                                        if let image = ThumbnailCache.thumbnail(uuid: photo.uuid, data: photo.thumbnailData) {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        }
                                    }
                                    .clipped()
                            }
                            .buttonStyle(DSPlainPressStyle())
                            .accessibilityLabel("Sample photo \(index + 1)")
                        }
                    }
                    .padding(DSSize.contactSheetSpacing)
                    .background(DSColor.textPrimary)
                }
                .overlay(Rectangle().strokeBorder(DSColor.rule, lineWidth: DSLine.rule))
            }
        }
    }

    private var preservedFields: some View {
        DSArchiveSection(title: "Preserved Fields") {
            ForEach(recipe.unsupportedFields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .firstTextBaseline) {
                    Text(key).font(DSFont.subhead).foregroundStyle(DSColor.textSecondary)
                    Spacer()
                    Text(value.displayString).font(DSFont.valueMono).foregroundStyle(DSColor.textPrimary)
                }
            }
            Label("These came from another camera or app version, or from a camera that reported a value Fuji Cookbook doesn't recognize. Either way they're kept intact and re-exported unchanged, so nothing is silently lost — but they can't be shown properly or pushed back to a camera.",
                  systemImage: "exclamationmark.triangle")
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    // MARK: Action bar

    /// Push needs a connected body that we're allowed to write to, whose slot walk didn't fail — the
    /// same gate the Camera tab's Push tile uses, so the two screens never disagree about whether a
    /// push can happen.
    private var canPush: Bool { camera.slotWriter.canPush }

    /// The screen's primary action, always shown. Dimmed and inert while a push can't happen, with
    /// the status line and a line underneath saying why, so a tap on a dead key is never the way the
    /// user finds out.
    private var actionBar: some View {
        DSFloatingActionBar(status: pushStatus) {
            HStack(spacing: DSSpacing.m) {
                // An icon key, so the primary key keeps its whole label at every text size.
                DSIconKey(systemImage: "square.and.arrow.up", label: "Share") { initiateShare() }
                Button { showingPush = true } label: {
                    Label("Load onto Camera", systemImage: "arrow.up.to.line")
                }
                .buttonStyle(.dsPrimary)
                .disabled(!canPush)
            }
            pushHint
        }
    }

    /// "X100VI   Write  Read back  Verify": what a push does, and to which camera.
    private var pushStatus: String {
        guard camera.session.isConnected else { return "No camera connected" }
        let name = camera.session.model?.displayName ?? "Camera"
        return canPush ? "\(name)   Write  Read back  Verify" : "\(name)   Read only"
    }

    /// Why the key is dim, and — when it's just a missing connection — the way to fix it.
    @ViewBuilder
    private var pushHint: some View {
        if !camera.session.isConnected {
            Button { router.selectedTab = .camera } label: {
                Text("Connect in the Camera tab")
                    .font(DSFont.subhead.weight(.semibold))
                    .foregroundStyle(DSColor.signalText)
                    .frame(maxWidth: .infinity, minHeight: DSSize.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPlainPressStyle())
        } else if !canPush {
            Text(camera.slotWriter.pushBlockReason ?? "Push isn't available for \(camera.session.model?.displayName ?? "this camera").")
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Hand Frame & Fit this recipe and switch to the Kitchen. The photographs are picked there:
    /// a share card is framed like any other post, so it gets the same canvases, crops and carousel
    /// tiles as the rest of the tool rather than a second, weaker copy of them.
    private func openShareCard() {
        router.frameSeed = FrameSeed(recipeUUID: recipe.uuid)
        router.selectedTab = .kitchen
    }

    private func duplicate() {
        let copy = Recipe(name: "\(recipe.name) Copy",
                          cameraName: recipe.cameraName,
                          notes: recipe.notes,
                          tags: recipe.tags,
                          isFavorite: false,
                          credit: recipe.credit,
                          authoredForModelID: recipe.authoredForModelID,
                          settings: recipe.settings,
                          unsupportedFields: recipe.unsupportedFields)
        modelContext.insert(copy)
        for photo in recipe.sortedPhotos {
            let copiedPhoto = RecipePhoto(imageData: photo.imageData,
                                          thumbnailData: photo.thumbnailData,
                                          sortOrder: photo.sortOrder)
            copiedPhoto.recipe = copy
            modelContext.insert(copiedPhoto)
        }
    }

    /// Ask whether to embed photos when the recipe has any; otherwise export straight away.
    private func initiateShare() {
        if recipe.sortedPhotos.isEmpty { share(includePhotos: false) }
        else { showingExportOptions = true }
    }

    private func share(includePhotos: Bool) {
        exportRunner.start(.single(recipe, includePhotos: includePhotos), named: recipe.name) { result in
            switch result {
            case .success(let url): shareItem = ShareItem(url: url)
            case .failure(let error): exportError = error.localizedDescription
            }
        }
    }
}
