import SwiftUI
import SwiftData
import PhotosUI

/// A staged sample photo in the editor. Edits are held locally and only committed on Save, so
/// Cancel discards added/removed photos just like it discards the other field changes.
struct PhotoDraft: Identifiable {
    let id: UUID
    /// Compressed full-size JPEG bytes.
    let full: Data
    /// Thumbnail JPEG bytes for in-editor display.
    let thumbnail: Data
    /// The persisted photo this draft came from, or nil for a newly added one.
    let existing: RecipePhoto?

    /// Stage the recipe's persisted photos for editing.
    static func drafts(for recipe: Recipe) -> [PhotoDraft] {
        recipe.sortedPhotos.map {
            PhotoDraft(id: $0.uuid, full: $0.imageData, thumbnail: $0.thumbnailData, existing: $0)
        }
    }

    /// Commit staged photo changes to the recipe's relationship: delete removed ones, insert new
    /// ones, and renumber `sortOrder` to match the current order.
    static func commit(_ drafts: [PhotoDraft], to recipe: Recipe, in modelContext: ModelContext) {
        let keptIDs = Set(drafts.compactMap { $0.existing?.uuid })
        for photo in (recipe.photos ?? []) where !keptIDs.contains(photo.uuid) {
            modelContext.delete(photo)
        }
        for (index, draft) in drafts.enumerated() {
            if let existing = draft.existing {
                existing.sortOrder = index
            } else {
                let photo = RecipePhoto(imageData: draft.full,
                                        thumbnailData: draft.thumbnail,
                                        sortOrder: index)
                photo.recipe = recipe
                modelContext.insert(photo)
            }
        }
    }
}

/// The editor's staged photos, and the order they opened in, so the editor can tell whether
/// closing it loses anything.
struct StagedPhotos {
    var drafts: [PhotoDraft]
    /// The ids in the order the editor opened with. Each staged photo keeps its persisted photo's
    /// id, so any add, remove or move makes `drafts` differ from this.
    private let openedIDs: [PhotoDraft.ID]

    init(_ drafts: [PhotoDraft]) {
        self.drafts = drafts
        openedIDs = drafts.map(\.id)
    }

    /// Whether a photo has been added, removed or moved since the editor opened.
    var hasChanges: Bool { drafts.map(\.id) != openedIDs }
}

/// The editor's "Sample Photos" form section: staged thumbnails, the system photo picker, and the
/// resize/compress pipeline. Owns its picker and error state; the staged drafts belong to the editor.
struct RecipePhotoSection: View {
    @Binding var photoDrafts: [PhotoDraft]

    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var photoError: String?

    private var remainingPhotoSlots: Int { max(0, Recipe.maxPhotos - photoDrafts.count) }

    private let rowThumbnailSize: CGFloat = 56

    var body: some View {
        Section {
            ForEach(Array(photoDrafts.enumerated()), id: \.element.id) { index, draft in
                photoRow(draft, index: index)
            }
            .onMove { photoDrafts.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { photoDrafts.remove(atOffsets: $0) }

            addPhotosRow
                .onChange(of: pickerSelection) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await addPickedPhotos(items) }
                }
                .alert("Couldn't Add Photo", isPresented: Binding(isPresent: $photoError)) {
                    Button("OK", role: .cancel) {}
                } message: { Text(photoError ?? "") }

            if isProcessingPhotos {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Processing…").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sample Photos")
        } footer: {
            Text("Up to \(Recipe.maxPhotos) photos (\(photoDrafts.count)/\(Recipe.maxPhotos) used). The first photo is the cover — it's the library thumbnail and the first image on the recipe page. Press and hold a photo to reorder, swipe to remove. Photos are resized and compressed on import, so full-resolution camera files aren't stored.")
        }
    }

    /// The picker, or — once every slot is used — a note in its place, because a disabled tinted
    /// row still reads as tappable. One row either way, so the change handler and the error alert
    /// stay attached when the last picked photo fills the set.
    @ViewBuilder
    private var addPhotosRow: some View {
        if remainingPhotoSlots == 0 {
            Text("All \(Recipe.maxPhotos) photos are used. Swipe one away to make room.")
                .foregroundStyle(.secondary)
        } else {
            PhotosPicker(selection: $pickerSelection,
                         maxSelectionCount: remainingPhotoSlots,
                         matching: .images,
                         photoLibrary: .shared()) {
                Label(photoDrafts.isEmpty ? "Add Photos" : "Add More",
                      systemImage: "photo.badge.plus")
            }
            // Only for the moment a pick is being processed; the "Processing…" row below says so.
            .disabled(isProcessingPhotos)
        }
    }

    private func photoRow(_ draft: PhotoDraft, index: Int) -> some View {
        HStack(spacing: 12) {
            thumbnail(draft)
            Text(index == 0 ? "Cover" : "Photo \(index + 1)")
                .font(.subheadline)
                .foregroundStyle(index == 0 ? .primary : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func thumbnail(_ draft: PhotoDraft) -> some View {
        Group {
            if let image = UIImage(data: draft.thumbnail) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: rowThumbnailSize, height: rowThumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: rowThumbnailSize, height: rowThumbnailSize)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
    }

    /// Load picked items, resize/compress them off the main thread, and stage the results.
    @MainActor
    private func addPickedPhotos(_ items: [PhotosPickerItem]) async {
        defer { pickerSelection = [] }
        isProcessingPhotos = true
        defer { isProcessingPhotos = false }

        var failed = false
        for item in items {
            guard remainingPhotoSlots > 0 else { break }
            guard let raw = try? await item.loadTransferable(type: Data.self) else {
                failed = true
                continue
            }
            let processed = await Task.detached(priority: .userInitiated) {
                PhotoProcessing.process(raw)
            }.value
            guard let processed else { failed = true; continue }
            photoDrafts.append(PhotoDraft(id: UUID(),
                                          full: processed.full,
                                          thumbnail: processed.thumbnail,
                                          existing: nil))
        }
        if failed {
            photoError = "Some photos couldn't be read and were skipped."
        }
    }
}
