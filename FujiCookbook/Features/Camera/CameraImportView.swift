import SwiftUI
import SwiftData

/// Import one, several, or all on-camera recipes into the library in a single action, with duplicate
/// handling.
struct CameraImportView: View {
    @Environment(CameraServices.self) private var camera
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(Recipe.listFetch()) private var existing: [Recipe]

    @State private var selected: Set<Int> = []
    @State private var resolutions: [Int: DuplicateResolution] = [:]
    @State private var didImport = false
    @State private var importSummary = ""
    @State private var saveAsChapter = false
    @State private var chapterName = ""

    private var occupiedSlots: [CameraSlot] { camera.occupiedSlots }

    private var defaultChapterName: String { "\(camera.session.model?.displayName ?? "Camera") Recipes" }

    var body: some View {
        List {
            if occupiedSlots.isEmpty {
                ContentUnavailableView("No Recipes on Camera", systemImage: "tray",
                                       description: Text("All custom slots are empty."))
            } else {
                Section {
                    ForEach(occupiedSlots) { slot in
                        slotRow(slot)
                    }
                } header: {
                    HStack {
                        Text("\(occupiedSlots.count) on camera")
                        Spacer()
                        Button(selected.count == occupiedSlots.count ? "Deselect All" : "Select All") {
                            toggleAll()
                        }.font(.callout)
                    }
                }

                Section {
                    Toggle("Also save as a Chapter", isOn: $saveAsChapter)
                    if saveAsChapter {
                        TextField(defaultChapterName, text: $chapterName)
                    }
                } header: {
                    Text("Chapter")
                } footer: {
                    Text("Groups the selected recipes into a chapter in camera-slot order (C1 first). Recipes already in your library are reused, not duplicated. Up to \(Chapter.maxSlots) slots.")
                }
            }
        }
        .navigationTitle("Import from Camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import (\(selected.count))") { performImport() }
                    .disabled(selected.isEmpty)
            }
        }
        .onAppear { if selected.isEmpty { selected = Set(occupiedSlots.map(\.index)) } }
        .alert("Import Complete", isPresented: $didImport) {
            Button("Done") { dismiss() }
        } message: { Text(importSummary) }
    }

    @ViewBuilder
    private func slotRow(_ slot: CameraSlot) -> some View {
        let portable = camera.slotReader.portableRecipe(for: slot)
        let match = portable.flatMap { DuplicateResolver.match(for: $0, in: existing) }
        VStack(alignment: .leading, spacing: 6) {
            Button { toggle(slot.index) } label: {
                HStack {
                    Image(systemName: selected.contains(slot.index) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(slot.index) ? DSColor.signalText : .secondary)
                    SlotRow(slot: slot)
                }
            }
            .buttonStyle(.plain)

            if selected.contains(slot.index), let match {
                Label(match.reason.description, systemImage: "doc.on.doc")
                    .font(.caption).foregroundStyle(DSColor.caution)
                Picker("Resolution", selection: resolutionBinding(slot.index, match: match)) {
                    ForEach(DuplicateResolution.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func resolutionBinding(_ index: Int, match: DuplicateMatch) -> Binding<DuplicateResolution> {
        Binding(
            get: { resolution(forSlot: index, match: match) },
            set: { resolutions[index] = $0 }
        )
    }

    private func resolution(forSlot index: Int, match: DuplicateMatch?) -> DuplicateResolution {
        guard match != nil, let chosen = resolutions[index] else {
            return RecipeImporter.defaultResolution(for: match)
        }
        return chosen
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
    }

    private func toggleAll() {
        selected = selected.count == occupiedSlots.count ? [] : Set(occupiedSlots.map(\.index))
    }

    private func performImport() {
        var added = 0, replaced = 0, skipped = 0
        // Slot index → resulting library recipe, for chapter ordering. A skipped slot maps to the
        // existing recipe it matched.
        var chapterEntries: [(slot: Int, uuid: UUID)] = []

        var usedNameKeys = Set(existing.map { RecipeImporter.nameKey($0.name) })
        for slot in occupiedSlots.sorted(by: { $0.index < $1.index }) where selected.contains(slot.index) {
            guard let portable = camera.slotReader.portableRecipe(for: slot) else { continue }
            let match = DuplicateResolver.match(for: portable, in: existing)
            let resolution = self.resolution(forSlot: slot.index, match: match)
            let result = RecipeImporter.apply(portable, resolution: resolution, match: match,
                                              into: modelContext, usedNameKeys: &usedNameKeys)
            switch result.outcome {
            case .added: added += 1
            case .replaced: replaced += 1
            case .skipped: skipped += 1
            }
            if let recipe = result.recipe { chapterEntries.append((slot.index, recipe.uuid)) }
        }

        var summary = "Added \(added), replaced \(replaced), skipped \(skipped)."

        if saveAsChapter && !chapterEntries.isEmpty {
            let ordered = chapterEntries.sorted { $0.slot < $1.slot }.map(\.uuid)
            let trimmed = chapterName.trimmingCharacters(in: .whitespaces)
            let chapter = Chapter(name: trimmed.isEmpty ? defaultChapterName : trimmed,
                                  recipeUUIDs: Array(ordered.prefix(Chapter.maxSlots)))
            modelContext.insert(chapter)
            let count = min(ordered.count, Chapter.maxSlots)
            summary += "\nSaved chapter “\(chapter.name)” with \(count) recipe\(count == 1 ? "" : "s")."
        }

        importSummary = summary
        didImport = true
    }
}
