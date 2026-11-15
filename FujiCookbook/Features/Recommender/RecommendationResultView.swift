import SwiftUI
import SwiftData

/// One saved recommendation: the chapter in slot order, which picks the user pinned and which the
/// model added, and the situation each pick is there to handle. Each row opens the library recipe.
///
/// The picks still in the library can be saved as a new Chapter, written back to the Chapter the
/// request came from, or reopened in the composer to refine. Picks are always library recipes, so
/// a saved Chapter references them; nothing is copied.
struct RecommendationResultView: View {
    let recommendation: Recommendation

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(Recipe.listFetch()) private var allRecipes: [Recipe]
    @Query private var allChapters: [Chapter]

    @State private var showingChapterNamePrompt = false
    @State private var showingUpdateConfirm = false
    @State private var chapterName = ""
    @State private var statusMessage: String?

    /// Each pick resolved against the current library; `recipe` is nil when it was deleted since.
    private var resolvedPicks: [(pick: RecipePick, recipe: Recipe?)] {
        let byUUID = Dictionary(allRecipes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        return recommendation.picks.map { ($0, byUUID[$0.recipeUUID]) }
    }

    private var availableRecipes: [Recipe] { resolvedPicks.compactMap(\.recipe) }

    /// The chapter this set was built from, if it still exists.
    private var sourceChapter: Chapter? {
        guard let uuid = recommendation.sourceChapterUUID else { return nil }
        return allChapters.first { $0.uuid == uuid }
    }

    private var anchorCount: Int { recommendation.anchoredPicks.count }
    private var addedCount: Int { recommendation.addedPicks.count }

    var body: some View {
        List {
            overviewSection
            picksSection
            if !recommendation.gaps.isEmpty { gapsSection }
            if availableRecipes.isEmpty {
                // A note in place of Save, Update and Refine, because disabled tinted rows still
                // read as tappable. Every one of them needs at least one pick still in the library.
                Section {
                    Text("None of these recipes are in your library anymore, so this set can't be saved or refined.")
                        .foregroundStyle(.secondary)
                }
            } else {
                saveSection
                refineSection
            }
        }
        .navigationTitle(recommendation.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Save as Roll", isPresented: $showingChapterNamePrompt) {
            TextField("Roll Name", text: $chapterName)
            Button("Save") { saveChapter() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Groups these \(availableRecipes.count) recipes as a roll, ready to push to slots C1–C\(availableRecipes.count).")
        }
        .confirmationDialog("Update “\(sourceChapter?.name ?? "")”?",
                            isPresented: $showingUpdateConfirm, titleVisibility: .visible) {
            Button("Replace Slots") { updateSourceChapter() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces that roll's slots with these \(availableRecipes.count) recipes, in this order. The recipes themselves aren't changed.")
        }
        .alert("Done", isPresented: Binding(isPresent: $statusMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }

    // MARK: Sections

    private var overviewSection: some View {
        Section {
            if let summary = recommendation.summary {
                Text(summary)
            }
            if recommendation.wasBuiltAroundAnchors {
                LabeledContent("Built from") {
                    Text("\(anchorCount) pinned · \(addedCount) added")
                }
            }
            LabeledContent("Asked on", value: recommendation.createdAt, format: .dateTime.day().month().year())
            if !recommendation.modelID.isEmpty {
                LabeledContent("Model", value: AIModelCatalog.displayName(for: recommendation.modelID))
            }
        } footer: {
            if recommendation.prompt.isEmpty {
                Text("Built around the pinned recipes, with no shooting plans given.")
            } else {
                Text("You asked: “\(recommendation.prompt)”")
            }
        }
    }

    private var picksSection: some View {
        Section {
            ForEach(Array(resolvedPicks.enumerated()), id: \.element.pick.id) { index, entry in
                if let recipe = entry.recipe {
                    NavigationLink(value: recipe) {
                        pickRow(slot: index + 1, pick: entry.pick, recipe: recipe)
                    }
                } else {
                    Label {
                        Text("A recommended recipe is no longer in your library.")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("The Roll (\(recommendation.picks.count) slot\(recommendation.picks.count == 1 ? "" : "s"))")
        } footer: {
            if recommendation.wasBuiltAroundAnchors {
                Label("Pinned by you — the model kept these and built the rest around them.",
                      systemImage: "pin.fill")
            } else {
                Text("In slot order: the first recipe maps to C1, the slot you'd leave the camera on.")
            }
        }
    }

    private func pickRow(slot: Int, pick: RecipePick, recipe: Recipe) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 3) {
                Text("C\(slot)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                if pick.isAnchor {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(DSColor.signalText)
                }
            }
            .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                HStack(spacing: 6) {
                    if let role = pick.role {
                        Text(role)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(DSColor.signal.opacity(0.15), in: Capsule())
                    }
                    if let film = recipe.settings.filmSimulation {
                        Text(film.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let reason = pick.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var gapsSection: some View {
        Section {
            ForEach(recommendation.gaps, id: \.self) { gap in
                Label {
                    Text(gap)
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(DSColor.caution)
                }
            }
        } header: {
            Text("What Your Library Can't Cover")
        } footer: {
            Text("Situations these plans call for that no recipe you own fits — worth a new recipe before the trip.")
        }
    }

    private var saveSection: some View {
        Section {
            if let chapter = sourceChapter {
                Button {
                    showingUpdateConfirm = true
                } label: {
                    Label("Update “\(chapter.name)”", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Button {
                chapterName = recommendation.title
                showingChapterNamePrompt = true
            } label: {
                Label("Save as New Roll…", systemImage: "film")
            }
        } footer: {
            Text("The roll references these library recipes — nothing is copied or duplicated.")
        }
    }

    private var refineSection: some View {
        Section {
            Button {
                refine()
            } label: {
                Label("Refine These Ideas…", systemImage: "sparkles")
            }
        } footer: {
            Text("Reopens the request with all of these pinned. Unpin the ones you want replaced and ask again — the model fills those slots with something else and won't offer the ones you dropped.")
        }
    }

    // MARK: Actions

    private func saveChapter() {
        let name = chapterName.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? recommendation.title : name
        let uuids = availableRecipes.prefix(Chapter.maxSlots).map(\.uuid)
        guard !uuids.isEmpty else { return }
        modelContext.insert(Chapter(name: finalName, recipeUUIDs: Array(uuids)))
        statusMessage = "“\(finalName)” is in your Rolls tab."
    }

    private func updateSourceChapter() {
        guard let chapter = sourceChapter else { return }
        let uuids = availableRecipes.prefix(Chapter.maxSlots).map(\.uuid)
        guard !uuids.isEmpty else { return }
        chapter.recipeUUIDs = Array(uuids)
        chapter.touch()
        statusMessage = "“\(chapter.name)” now holds these \(uuids.count) recipes."
    }

    /// Hand the set back to the composer with every pick still in the library pinned, so the user
    /// can unpin the slots they want redone. `RecommenderView` takes the seed, pops back to the
    /// composer, and withholds the unpinned picks from the next request.
    private func refine() {
        let uuids = availableRecipes.prefix(Chapter.maxSlots).map(\.uuid)
        guard !uuids.isEmpty else { return }
        router.ideaSeed = IdeaSeed(anchorUUIDs: Array(uuids),
                                   brief: recommendation.prompt,
                                   slotTarget: max(recommendation.slotTarget, uuids.count),
                                   previousPickUUIDs: Array(uuids),
                                   sourceChapter: sourceChapter.map(IdeaSeed.SourceChapter.init))
    }
}
