import SwiftUI
import SwiftData

/// Create or edit a Chapter: its name and up to `Chapter.maxSlots` recipes in slot order. Edits are
/// written to the chapter on Save; cancelling a new chapter deletes it.
struct ChapterEditorView: View {
    @Bindable var chapter: Chapter
    let isNew: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(Recipe.listFetch(sortBy: [SortDescriptor(\Recipe.name)])) private var allRecipes: [Recipe]

    @State private var draft: ChapterDraft
    @State private var showingPicker = false
    @State private var showingDiscardConfirm = false

    init(chapter: Chapter, isNew: Bool) {
        self._chapter = Bindable(wrappedValue: chapter)
        self.isNew = isNew
        _draft = State(initialValue: ChapterDraft(from: chapter))
    }

    private func recipe(for id: UUID) -> Recipe? { allRecipes.first { $0.uuid == id } }

    /// Recipes not already in this chapter, offered by the picker.
    private var availableRecipes: [Recipe] {
        allRecipes.filter { !draft.recipeUUIDs.contains($0.uuid) }
    }

    /// Why another recipe can't be added right now, or nil when the Add Recipe row is live. A note
    /// in place of the button, because a disabled tinted row still reads as tappable.
    private var addBlockedReason: String? {
        if draft.recipeUUIDs.count >= Chapter.maxSlots {
            return "All \(Chapter.maxSlots) slots are full. Swipe a recipe away to make room."
        }
        if allRecipes.isEmpty { return "Your library has no recipes to add yet." }
        if availableRecipes.isEmpty { return "Every recipe in your library is already in this chapter." }
        return nil
    }

    var body: some View {
        Form {
            Section { TextField("Chapter Name", text: $draft.name) }

            Section {
                if draft.recipeUUIDs.isEmpty {
                    Text("No recipes yet. Add up to \(Chapter.maxSlots).")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(draft.recipeUUIDs.enumerated()), id: \.element) { index, id in
                        LabeledContent("C\(index + 1)") {
                            Text(recipe(for: id)?.name ?? "Missing recipe")
                                .foregroundStyle(recipe(for: id) == nil ? .red : .secondary)
                        }
                    }
                    .onMove { draft.recipeUUIDs.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.recipeUUIDs.remove(atOffsets: $0) }
                }

                if let reason = addBlockedReason {
                    Text(reason).foregroundStyle(.secondary)
                } else {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add Recipe", systemImage: "plus")
                    }
                }
            } header: {
                Text("Slots (\(draft.recipeUUIDs.count)/\(Chapter.maxSlots))")
            } footer: {
                Text("Order is the slot order: the first recipe pushes to C1, the second to C2, and so on. Drag to reorder, swipe to remove.")
            }
        }
        .navigationTitle(isNew ? "New Chapter" : "Edit Chapter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !draft.recipeUUIDs.isEmpty { EditButton() }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { cancel() }
                    .confirmationDialog("Discard Changes?", isPresented: $showingDiscardConfirm,
                                        titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { discard() }
                        Button("Keep Editing", role: .cancel) {}
                    }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        // A new chapter is in the store before the editor opens and only Cancel deletes it, so a
        // swipe would leave it behind in the list. An existing chapter swipes away until it holds
        // an edit; from then on, Cancel is the way out and it asks first.
        .interactiveDismissDisabled(isNew || draft.hasChanges)
        .sheet(isPresented: $showingPicker) {
            RecipePickerSheet(title: "Add Recipe",
                              choices: availableRecipes.map(RecipeChoice.init),
                              mode: .single,
                              emptyMessage: "Every recipe is already in this chapter.") { picked in
                guard case .library(let uuid)? = picked.first else { return }
                if draft.recipeUUIDs.count < Chapter.maxSlots { draft.recipeUUIDs.append(uuid) }
            }
        }
    }

    private func save() {
        chapter.name = draft.name.trimmingCharacters(in: .whitespaces)
        chapter.recipeUUIDs = Array(draft.recipeUUIDs.prefix(Chapter.maxSlots))
        chapter.touch()
        dismiss()
    }

    private func cancel() {
        if draft.hasChanges { showingDiscardConfirm = true } else { discard() }
    }

    private func discard() {
        if isNew { modelContext.delete(chapter) }
        dismiss()
    }
}

