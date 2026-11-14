import SwiftUI
import SwiftData

/// The **Ideas** tab: the model assembles a chapter **from the user's own library** to fit a
/// shooting brief, a set of pinned recipes, or both; it never invents recipes. Pinned recipes are
/// kept, and the remaining slots go to recipes that cover what the pinned ones don't.
///
/// A request can arrive pre-filled through `AppRouter.ideaSeed`: a Chapter asking for its free
/// slots to be filled, or a past result being refined.
struct RecommenderView: View {
    @Environment(AISettings.self) private var aiSettings
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recommendation.createdAt, order: .reverse) private var history: [Recommendation]
    @Query(Recipe.listFetch(sortBy: [SortDescriptor(\Recipe.name)])) private var recipes: [Recipe]

    @State private var prompt = ""
    /// Recipes the model must keep, in the order they were chosen.
    @State private var anchorUUIDs: [UUID] = []
    @State private var slotTarget = Chapter.maxSlots
    /// Every recipe in the result being refined. Any of these the user unpins counts as rejected and
    /// is withheld from the next request, so "redo the rest" doesn't hand back what they just dropped.
    @State private var seededPickUUIDs: [UUID] = []
    @State private var sourceChapter: IdeaSeed.SourceChapter?

    @State private var isThinking = false
    @State private var errorMessage: String?
    /// Both destinations are value-based on this one path. Mixing `navigationDestination(item:)`
    /// with `navigationDestination(for:)` in a single stack makes SwiftUI re-append the item
    /// destination on top of any later value push, so opening a recipe from a result shows a
    /// duplicate result screen.
    @State private var path = NavigationPath()
    @State private var showingSettings = false
    @State private var showingAnchorPicker = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !aiSettings.canRecommend { setupSection }
                if recipes.isEmpty { emptyLibrarySection }
                if sourceChapter != nil { sourceChapterSection }
                promptSection
                anchorsSection
                if !recipes.isEmpty { sizeSection }
                askSection
                if !history.isEmpty { historySection }
            }
            .navigationTitle("Recipe Ideas")
            .navigationDestination(for: Recommendation.self) { recommendation in
                RecommendationResultView(recommendation: recommendation)
            }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingAnchorPicker) {
                RecipePickerSheet(title: "Build Around",
                                  choices: recipes.map(RecipeChoice.init),
                                  mode: .multiple(limit: Chapter.maxSlots),
                                  initialSelection: anchorUUIDs.map { RecipeRef.library($0) }) { picked in
                    anchorUUIDs = picked.compactMap { ref in
                        if case .library(let uuid) = ref { return uuid }
                        return nil
                    }
                    clampSlotTarget()
                }
            }
            .alert("Couldn't Get Ideas", isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onAppear { consumePendingSeed() }
            .onChange(of: router.ideaSeed) { _, _ in consumePendingSeed() }
            // The slot range depends on the library size, so keep the target inside it if recipes
            // are added or deleted while this screen is up.
            .onChange(of: recipes.count) { _, _ in clampSlotTarget() }
        }
    }

    // MARK: Sections

    private var setupSection: some View {
        Section {
            Label {
                Text(setupPrompt)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(DSColor.textSecondary)
            }
            Button { showingSettings = true } label: {
                Label("Set Up in Settings", systemImage: "gearshape")
            }
        }
    }

    /// What's still missing, in the order Settings asks for it.
    private var setupPrompt: String {
        if !aiSettings.isEnabled {
            return "Recipe ideas need AI features turned on in Settings."
        }
        if !aiSettings.hasAPIKey {
            return "Recipe ideas need a \(aiSettings.provider.displayName) API key."
        }
        return "Choose a \(aiSettings.provider.displayName) model for Ideas in Settings."
    }

    private var emptyLibrarySection: some View {
        Section {
            Label {
                Text("Ideas recommends recipes from your own library, and it's empty. Add or import some recipes in the Recipes tab first.")
            } icon: {
                Image(systemName: "tray").foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    private var sourceChapterSection: some View {
        Section {
            Label {
                Text("Filling out “\(sourceChapter?.name ?? "")”. Its recipes are pinned below, and the result can be written straight back to it.")
            } icon: {
                Image(systemName: "books.vertical").foregroundStyle(DSColor.signalText)
            }
            Button("Start Fresh Instead", role: .destructive) { resetComposer() }
        }
    }

    private var promptSection: some View {
        Section {
            TextField("Where are you shooting, and what's the vibe? e.g. \"A week in Lisbon in October — mostly street and food, some rainy evenings, going for a warm nostalgic look.\"",
                      text: $prompt, axis: .vertical)
                .lineLimit(4...10)
                .focused($promptFocused)
                .disabled(isThinking)
        } header: {
            Text(anchorUUIDs.isEmpty ? "Your Shooting Plans" : "Your Shooting Plans (Optional)")
        } footer: {
            if anchorUUIDs.isEmpty {
                Text("Mention the destination, season and weather, what you'll photograph, and the mood you're after.")
            } else {
                Text("Optional now that you've pinned recipes — but the more you say about the light and the subjects, the better the model can judge what's still missing.")
            }
        }
    }

    private var anchorsSection: some View {
        Section {
            if anchorUUIDs.isEmpty {
                Text("Nothing pinned — the model will choose the whole set.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(anchorUUIDs, id: \.self) { uuid in
                    if let recipe = recipe(for: uuid) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name)
                            Text(recipe.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Missing recipe").foregroundStyle(DSColor.caution)
                    }
                }
                .onDelete { offsets in
                    anchorUUIDs.remove(atOffsets: offsets)
                    clampSlotTarget()
                }
            }

            // A note in place of the button, because a disabled tinted row still reads as tappable.
            if recipes.isEmpty {
                Text("Your library has no recipes to pin yet.").foregroundStyle(.secondary)
            } else {
                Button {
                    promptFocused = false
                    showingAnchorPicker = true
                } label: {
                    Label(anchorUUIDs.isEmpty ? "Pick Recipes to Build Around" : "Change Pinned Recipes",
                          systemImage: "pin")
                }
                // Disabled only while a request is out. The ask row's progress already says so, so
                // no note replaces this button.
                .disabled(isThinking)
            }
        } header: {
            Text("Build Around (\(anchorUUIDs.count)/\(Chapter.maxSlots))")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recipes you already know you want. The model keeps every one, works out what they cover between them, and spends the remaining slots on recipes that cover what they don't. Swipe to unpin.")
                if !excludedUUIDs.isEmpty {
                    Label("\(excludedUUIDs.count) recipe\(excludedUUIDs.count == 1 ? "" : "s") you unpinned from the last result won't be suggested again this round.",
                          systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private var sizeSection: some View {
        Section {
            Stepper(value: $slotTarget, in: slotRange) {
                LabeledContent("Fill to", value: "\(slotTarget) slot\(slotTarget == 1 ? "" : "s")")
            }
            .disabled(isThinking || slotRange.lowerBound == slotRange.upperBound)
        } header: {
            Text("Chapter Size")
        } footer: {
            Text(sizeFooter)
        }
    }

    private var askSection: some View {
        Section {
            if let reason = askBlockedReason {
                Text(reason).foregroundStyle(.secondary)
            } else {
                Button { requestIdeas() } label: {
                    if isThinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Asking \(aiSettings.provider.displayName) with your key…")
                        }
                    } else {
                        Label(anchorUUIDs.isEmpty ? "Get Recipe Ideas" : "Complete the Chapter",
                              systemImage: "sparkles")
                    }
                }
                .disabled(isThinking)
            }
        } footer: {
            Text("The model picks only from your library — nothing is invented, and nothing changes until you save the result as a chapter. Every result is kept below.")
        }
    }

    private var historySection: some View {
        Section("Past Ideas") {
            ForEach(history) { recommendation in
                NavigationLink(value: recommendation) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendation.title)
                            .foregroundStyle(.primary)
                        if !recommendation.prompt.isEmpty {
                            Text(recommendation.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        HStack(spacing: 6) {
                            if recommendation.wasBuiltAroundAnchors {
                                Label("\(recommendation.anchoredPicks.count) pinned",
                                      systemImage: "pin.fill")
                            }
                            Text(recommendation.createdAt, format: .dateTime.day().month().year())
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(history[index]) }
            }
        }
    }

    // MARK: Derived state

    private func recipe(for uuid: UUID) -> Recipe? { recipes.first { $0.uuid == uuid } }

    /// At least as many slots as pinned recipes, and never more than the library holds or
    /// `Chapter.maxSlots`.
    private var slotRange: ClosedRange<Int> {
        let lower = max(anchorUUIDs.count, 1)
        let upper = max(lower, min(Chapter.maxSlots, max(recipes.count, 1)))
        return lower...upper
    }

    private var sizeFooter: String {
        let remaining = max(slotTarget - anchorUUIDs.count, 0)
        if anchorUUIDs.isEmpty {
            return "The model aims to fill C1–C\(slotTarget), and picks fewer if fewer genuinely fit."
        }
        if remaining == 0 {
            return "All \(slotTarget) slots are pinned. Raise the size or unpin a recipe to leave the model something to fill."
        }
        return "\(anchorUUIDs.count) pinned, \(remaining) for the model to fill (C1–C\(slotTarget))."
    }

    /// Recipes from the result being refined that the user has since unpinned — treated as rejected.
    private var excludedUUIDs: Set<UUID> {
        Set(seededPickUUIDs).subtracting(anchorUUIDs)
    }

    /// Why a request can't be made yet, shown as a note in place of the ask button because a
    /// disabled tinted row still reads as tappable. Nil when the row is a button: ready to ask, or
    /// a request is out and the button shows its progress.
    private var askBlockedReason: String? {
        if isThinking { return nil }
        if !aiSettings.canRecommend { return "Finish setting up AI features above to get ideas." }
        if recipes.isEmpty { return "Add recipes to your library to get ideas." }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && anchorUUIDs.isEmpty {
            return "Describe your shooting plans or pin a recipe to get ideas."
        }
        return nil
    }

    // MARK: Actions

    private func clampSlotTarget() {
        slotTarget = min(max(slotTarget, slotRange.lowerBound), slotRange.upperBound)
    }

    /// Apply a request handed over from another screen (a Chapter, or a result being refined).
    private func consumePendingSeed() {
        guard let seed = router.ideaSeed else { return }
        router.ideaSeed = nil
        prompt = seed.brief
        anchorUUIDs = seed.anchorUUIDs
        slotTarget = seed.slotTarget
        seededPickUUIDs = seed.previousPickUUIDs
        sourceChapter = seed.sourceChapter
        clampSlotTarget()
        // The seed fills the composer, so pop whatever is pushed over it: the result being refined,
        // or a result or recipe left open on this tab before a Chapter sent the seed.
        path = NavigationPath()
        promptFocused = false
    }

    private func resetComposer() {
        prompt = ""
        anchorUUIDs = []
        seededPickUUIDs = []
        sourceChapter = nil
        slotTarget = Chapter.maxSlots
        clampSlotTarget()
    }

    private func requestIdeas() {
        let brief = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let library = recipes.map(RecipeRecommender.LibraryEntry.init)
        let anchors = anchorUUIDs
        let excluded = excludedUUIDs
        let target = slotTarget
        let chapterUUID = sourceChapter?.uuid
        promptFocused = false
        Task {
            isThinking = true
            defer { isThinking = false }
            do {
                let result = try await RecipeRecommender.recommend(prompt: brief,
                                                                   library: library,
                                                                   anchors: anchors,
                                                                   slotTarget: target,
                                                                   excluded: excluded,
                                                                   provider: aiSettings.provider,
                                                                   apiKey: aiSettings.apiKey,
                                                                   modelID: aiSettings.recommenderModelID)
                let recommendation = Recommendation(prompt: brief,
                                                    title: result.title,
                                                    summary: result.summary,
                                                    modelID: aiSettings.recommenderModelID,
                                                    picks: result.picks,
                                                    slotTarget: target,
                                                    gaps: result.gaps,
                                                    sourceChapterUUID: chapterUUID)
                modelContext.insert(recommendation)
                resetComposer()
                path.append(recommendation)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
