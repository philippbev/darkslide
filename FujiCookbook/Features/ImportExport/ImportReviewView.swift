import SwiftUI
import SwiftData

/// Reviews imported recipes and resolves duplicates before they enter the library
/// (skip, keep both, or overwrite). Nothing is written until "Import".
struct ImportReviewView: View {
    let pending: PendingImport

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(Recipe.listFetch()) private var existing: [Recipe]

    @State private var resolutions: [Int: DuplicateResolution] = [:]
    @State private var importFailure: String?

    private var matches: [Int: DuplicateMatch] {
        var result: [Int: DuplicateMatch] = [:]
        for (i, portable) in pending.recipes.enumerated() {
            if let match = DuplicateResolver.match(for: portable, in: existing) {
                result[i] = match
            }
        }
        return result
    }

    var body: some View {
        // Read once per body pass: duplicate detection compares every pending recipe with the whole
        // library, so each row reading `matches` would repeat it.
        let matches = self.matches
        NavigationStack {
            List {
                Section {
                    ForEach(Array(pending.recipes.enumerated()), id: \.offset) { index, portable in
                        row(index: index, portable: portable, match: matches[index])
                    }
                } header: {
                    Text("\(pending.recipes.count) recipe\(pending.recipes.count == 1 ? "" : "s") in “\(pending.sourceName)”")
                } footer: {
                    if !matches.isEmpty {
                        Text("Some recipes match items already in your library. Choose how to handle each.")
                    }
                }

                if !pending.chapters.isEmpty {
                    Section {
                        Label("\(pending.chapters.count) chapter\(pending.chapters.count == 1 ? "" : "s") will be restored",
                              systemImage: "books.vertical")
                            .font(.subheadline)
                    } footer: {
                        Text("Chapters are re-linked to the imported recipes. Existing identical chapters are skipped.")
                    }
                }
            }
            .navigationTitle("Import Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { performImport() }
                }
            }
            .alert("Couldn't Import Recipes", isPresented: Binding(isPresent: $importFailure)) {
                Button("OK", role: .cancel) { importFailure = nil }
            } message: { Text(importFailure ?? "") }
        }
    }

    @ViewBuilder
    private func row(index: Int, portable: PortableRecipe, match: DuplicateMatch?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(portable.name).font(.headline)
            if let prepared = pending.preparedRecipes?[index], prepared.skippedPhotos > 0 {
                Label("\(prepared.skippedPhotos) unreadable photo\(prepared.skippedPhotos == 1 ? " was" : "s were") skipped."
                      + (prepared.photos == nil ? " Existing photos will be kept if you overwrite." : ""),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(DSColor.caution)
            }
            if portable.settings.filmSimulation == nil {
                // A recipe with no film simulation pushes PROVIA / Standard (`RecipeCompatibility`), so
                // it is the one omission that has to look like a warning here.
                Label("No film simulation set — pushed as-is, PROVIA / Standard is written.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(DSColor.caution)
            } else {
                Text(RecipeSettingsFormatter.summary(for: portable.settings)).font(.subheadline).foregroundStyle(.secondary)
            }
            if let match,
               let warning = Self.overwriteWarning(incoming: portable.settings, existing: match.existing.settings,
                                                   resolution: resolutions[index] ?? Self.defaultResolution(for: match)) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(DSColor.caution)
            }
            if let model = portable.authoredForModel, CameraModelRegistry.shared.model(withID: model) == nil {
                Label("Camera profile \(model) isn't known here — its fields are preserved", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(DSColor.caution)
            }
            if let match {
                Label(match.reason.description, systemImage: "doc.on.doc")
                    .font(.caption).foregroundStyle(DSColor.caution)
                Picker("Resolution", selection: binding(for: index, match: match)) {
                    ForEach(DuplicateResolution.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 2)
    }

    /// The warning for an overwrite that would clear the library recipe's film simulation, or `nil`.
    ///
    /// Overwrite replaces `settings` wholesale (`RecipeImporter.apply`), so an incoming recipe with no
    /// film simulation removes the existing one, and a push then writes PROVIA / Standard in its place.
    /// Static so tests can call it without building the view.
    static func overwriteWarning(incoming: RecipeSettings, existing: RecipeSettings,
                                 resolution: DuplicateResolution) -> String? {
        guard resolution == .overwrite, incoming.filmSimulation == nil,
              let kept = existing.filmSimulation else { return nil }
        return "Overwriting will remove this recipe's film simulation (currently \(kept.displayName))."
    }

    private func binding(for index: Int, match: DuplicateMatch) -> Binding<DuplicateResolution> {
        Binding(
            get: { resolutions[index] ?? Self.defaultResolution(for: match) },
            set: { resolutions[index] = $0 }
        )
    }

    private static func defaultResolution(for match: DuplicateMatch?) -> DuplicateResolution {
        RecipeImporter.defaultResolution(for: match)
    }

    private func performImport() {
        do {
            try RecipeImporter.applyBatch(pending.recipes, chapters: pending.chapters,
                                          prepared: pending.preparedRecipes, resolutions: resolutions,
                                          into: modelContext)
            dismiss()
        } catch {
            AppLog.error(.importExport, "Couldn't commit the import — \(AppLog.bounded(error))")
            importFailure = "The import couldn't be saved. Your existing library was kept. Free some device storage if needed, then try opening the file again."
        }
    }
}
