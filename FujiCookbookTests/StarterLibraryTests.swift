import XCTest
import SwiftData
@testable import FujiCookbook

@MainActor
final class StarterLibraryTests: XCTestCase {
    private var retainedContainer: ModelContainer?

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelStore.schema,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                             cloudKitDatabase: .none))
        retainedContainer = container
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func recipesInRollOrder(_ context: ModelContext) throws -> [Recipe] {
        try context.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// Each entry's name finds its bundled file, and the file has to carry the same name and pass
    /// the importer's validation.
    func testBundledFilesDecodeUnderTheirOwnNames() throws {
        for entry in StarterLibrary.recipes {
            let loaded = try StarterLibrary.load(entry)
            XCTAssertEqual(loaded.recipe.name, entry.name)
            XCTAssertEqual(loaded.recipe.authoredForModel, "X100VI")
        }
    }

    func testBundledSettingsAreTheOnesShipped() throws {
        let simulations = try StarterLibrary.recipes.map { try StarterLibrary.load($0).recipe.settings.filmSimulation }
        XCTAssertEqual(simulations, [.acrosYe, .classicNeg, .realaAce])
    }

    /// Copies written by every build on every device have to match, so the identities never change.
    func testIdentitiesArePinned() {
        XCTAssertEqual(StarterLibrary.recipeUUIDs.map(\.uuidString), [
            "A37634E7-80CD-43FD-97DF-27F0D0F423DF",
            "8AA7D12C-C8D8-40D4-B643-4BCAA0B70DC7",
            "11A8ADE1-FCE0-480E-957A-6F438E921846",
        ])
        XCTAssertEqual(StarterLibrary.rollUUID.uuidString, "5775D737-49FC-4922-BD06-E69B6CDC0FE5")
    }

    func testAddingSavesTheRecipesAndARollThatHoldsThemInOrder() async throws {
        let context = try context()
        try await StarterLibrary.add(to: context)
        let recipes = try recipesInRollOrder(context)
        XCTAssertEqual(recipes.map(\.name), ["Acros Pro", "FUJICOLOR 400", "NATURAL"])
        XCTAssertEqual(recipes.map(\.uuid), StarterLibrary.recipeUUIDs)
        XCTAssertTrue(recipes.allSatisfy { $0.updatedAt == $0.createdAt }, "untouched copies")

        let rolls = try context.fetch(FetchDescriptor<Chapter>())
        XCTAssertEqual(rolls.count, 1)
        XCTAssertEqual(rolls.first?.uuid, StarterLibrary.rollUUID)
        XCTAssertEqual(rolls.first?.name, StarterLibrary.rollName)
        XCTAssertEqual(rolls.first?.recipeUUIDs, StarterLibrary.recipeUUIDs)
        XCTAssertEqual(rolls.first?.updatedAt, rolls.first?.createdAt)
        XCTAssertFalse(context.hasChanges)
    }

    func testAddingTwiceKeepsOneCopyOfEach() async throws {
        let context = try context()
        try await StarterLibrary.add(to: context)
        try await StarterLibrary.add(to: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 1)
    }

    /// The user deleted one recipe and the roll: adding again restores just those.
    func testAddingFillsInOnlyWhatIsMissing() async throws {
        let context = try context()
        try await StarterLibrary.add(to: context)
        let kept = try recipesInRollOrder(context)
        kept[0].isFavorite = true
        kept[0].touch()
        context.delete(kept[1])
        try context.fetch(FetchDescriptor<Chapter>()).forEach(context.delete)
        try context.save()

        try await StarterLibrary.add(to: context)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(Set(recipes.map(\.uuid)), Set(StarterLibrary.recipeUUIDs))
        XCTAssertEqual(recipes.count, 3)
        XCTAssertTrue(recipes.contains { $0.isFavorite }, "the edited copy stays as it was")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 1)
    }

    // MARK: Seeding

    private func freshDefaults() throws -> UserDefaults {
        let suiteName = "StarterLibraryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testANewLibraryIsSeededOnce() async throws {
        let context = try context()
        let defaults = try freshDefaults()
        await StarterLibrary.seedIfNeeded(into: context, defaults: defaults)
        let seeded = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(Set(seeded.map(\.uuid)), Set(StarterLibrary.recipeUUIDs))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Chapter>()).map(\.uuid), [StarterLibrary.rollUUID])
        XCTAssertTrue(defaults.bool(forKey: StarterLibrary.seededDefaultsKey))

        // Deleted by the user, they stay deleted.
        seeded.forEach(context.delete)
        try context.fetch(FetchDescriptor<Chapter>()).forEach(context.delete)
        try context.save()
        await StarterLibrary.seedIfNeeded(into: context, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 0)
    }

    func testALibraryInUseIsMarkedDoneAndLeftAlone() async throws {
        let context = try context()
        let defaults = try freshDefaults()
        context.insert(Recipe(name: "Mine"))
        try context.save()
        await StarterLibrary.seedIfNeeded(into: context, defaults: defaults)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.map(\.name), ["Mine"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 0)
        XCTAssertTrue(defaults.bool(forKey: StarterLibrary.seededDefaultsKey))
    }

    // MARK: Collapsing copies

    private let starter = StarterLibrary.recipes[0]

    /// A copy as another device's install would have written it.
    private func insertCopy(in context: ModelContext, createdAt: Date) -> Recipe {
        let copy = Recipe(uuid: starter.uuid, name: starter.name, createdAt: createdAt, updatedAt: createdAt)
        context.insert(copy)
        return copy
    }

    private let earlier = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let later = Date(timeIntervalSinceReferenceDate: 800_086_400)

    func testDuplicatesAreSpottedAmongStartersOnly() {
        let other = UUID()
        XCTAssertFalse(StarterLibrary.hasDuplicates(recipeUUIDs: StarterLibrary.recipeUUIDs + [other, other]))
        XCTAssertTrue(StarterLibrary.hasDuplicates(recipeUUIDs: StarterLibrary.recipeUUIDs + [starter.uuid]))
    }

    func testUntouchedCopiesCollapseToTheOldest() throws {
        let context = try context()
        _ = insertCopy(in: context, createdAt: later)
        _ = insertCopy(in: context, createdAt: earlier)
        try StarterLibrary.collapseCopies(in: context)
        let kept = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(kept.map(\.createdAt), [earlier])
        XCTAssertFalse(context.hasChanges)
    }

    func testAnEditedCopyOutlivesAnUntouchedOne() throws {
        let context = try context()
        _ = insertCopy(in: context, createdAt: earlier)
        let favorited = insertCopy(in: context, createdAt: later)
        favorited.isFavorite = true
        favorited.touch()
        try StarterLibrary.collapseCopies(in: context)
        let kept = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(kept.map(\.persistentModelID), [favorited.persistentModelID])
        XCTAssertEqual(kept.first?.uuid, starter.uuid)
    }

    func testTwoEditedCopiesAreBothKeptUnderSeparateIdentities() throws {
        let context = try context()
        let older = insertCopy(in: context, createdAt: earlier)
        let newer = insertCopy(in: context, createdAt: later)
        older.touch()
        newer.touch()
        try StarterLibrary.collapseCopies(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 2)
        XCTAssertEqual(older.uuid, starter.uuid)
        XCTAssertNotEqual(newer.uuid, starter.uuid)
    }

    func testOneCopyIsLeftAlone() throws {
        let context = try context()
        _ = insertCopy(in: context, createdAt: earlier)
        try context.save()
        try StarterLibrary.collapseCopies(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 1)
    }

    func testUntouchedRollCopiesCollapseToTheOldest() throws {
        let context = try context()
        context.insert(StarterLibrary.makeRoll(at: later))
        context.insert(StarterLibrary.makeRoll(at: earlier))
        try StarterLibrary.collapseCopies(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Chapter>()).map(\.createdAt), [earlier])
    }

    func testAnEditedRollOutlivesAnUntouchedOne() throws {
        let context = try context()
        context.insert(StarterLibrary.makeRoll(at: earlier))
        let renamed = StarterLibrary.makeRoll(at: later)
        renamed.name = "Mine"
        renamed.touch()
        context.insert(renamed)
        try StarterLibrary.collapseCopies(in: context)
        let kept = try context.fetch(FetchDescriptor<Chapter>())
        XCTAssertEqual(kept.map(\.name), ["Mine"])
        XCTAssertEqual(kept.first?.uuid, StarterLibrary.rollUUID)
    }
}
