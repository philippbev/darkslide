import XCTest
import SwiftData
@testable import FujiCookbook

@MainActor
final class StarterRecipeTests: XCTestCase {
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

    /// The button is labelled from `StarterRecipe.name`, so the bundled file has to carry that name
    /// and pass the importer's validation.
    func testBundledFileDecodesUnderItsOwnName() throws {
        let loaded = try StarterRecipe.load()
        XCTAssertEqual(loaded.recipe.name, StarterRecipe.name)
        XCTAssertEqual(loaded.recipe.credit, "Zachary Grimshaw")
        guard case .replace(let photos) = loaded.photos else { return XCTFail("Expected sample photos") }
        XCTAssertEqual(photos.count, 5)
    }

    func testAddingSavesTheRecipeWithItsPhotos() async throws {
        let context = try context()
        let added = try await StarterRecipe.add(to: context)
        let saved = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(saved.map(\.name), [StarterRecipe.name])
        XCTAssertEqual(added.sortedPhotos.count, 5)
        XCTAssertEqual(added.sortedPhotos.map(\.sortOrder), Array(0..<5))
        XCTAssertEqual(added.settings.filmSimulation, .provia)
        XCTAssertFalse(context.hasChanges)
    }

    /// Copies written by every build on every device have to match, so the identity never changes.
    func testIdentityIsPinned() {
        XCTAssertEqual(StarterRecipe.uuid.uuidString, "32784DB2-A466-4DA1-9899-88CFD7E32CD1")
    }

    func testAddedCopyCarriesTheStarterIdentityAndLooksUntouched() async throws {
        let added = try await StarterRecipe.add(to: try context())
        XCTAssertEqual(added.uuid, StarterRecipe.uuid)
        XCTAssertEqual(added.updatedAt, added.createdAt)
    }

    func testAddingTwiceKeepsOneCopy() async throws {
        let context = try context()
        let first = try await StarterRecipe.add(to: context)
        let second = try await StarterRecipe.add(to: context)
        XCTAssertEqual(second.persistentModelID, first.persistentModelID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 1)
    }

    // MARK: Seeding

    private func freshDefaults() throws -> UserDefaults {
        let suiteName = "StarterRecipeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testANewLibraryIsSeededOnce() async throws {
        let context = try context()
        let defaults = try freshDefaults()
        await StarterRecipe.seedIfNeeded(into: context, defaults: defaults)
        let seeded = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(seeded.map(\.uuid), [StarterRecipe.uuid])
        XCTAssertTrue(defaults.bool(forKey: StarterRecipe.seededDefaultsKey))

        // Deleted by the user, it stays deleted.
        context.delete(try XCTUnwrap(seeded.first))
        try context.save()
        await StarterRecipe.seedIfNeeded(into: context, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 0)
    }

    func testALibraryInUseIsMarkedDoneAndLeftAlone() async throws {
        let context = try context()
        let defaults = try freshDefaults()
        context.insert(Recipe(name: "Mine"))
        try context.save()
        await StarterRecipe.seedIfNeeded(into: context, defaults: defaults)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.map(\.name), ["Mine"])
        XCTAssertTrue(defaults.bool(forKey: StarterRecipe.seededDefaultsKey))
    }

    // MARK: Collapsing copies

    /// A copy as another device's install would have written it, without the photos.
    private func insertCopy(in context: ModelContext, createdAt: Date) -> Recipe {
        let copy = Recipe(uuid: StarterRecipe.uuid, name: StarterRecipe.name,
                          createdAt: createdAt, updatedAt: createdAt)
        context.insert(copy)
        return copy
    }

    private let earlier = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let later = Date(timeIntervalSinceReferenceDate: 800_086_400)

    func testUntouchedCopiesCollapseToTheOldest() throws {
        let context = try context()
        _ = insertCopy(in: context, createdAt: later)
        _ = insertCopy(in: context, createdAt: earlier)
        try StarterRecipe.collapseCopies(in: context)
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
        try StarterRecipe.collapseCopies(in: context)
        let kept = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(kept.map(\.persistentModelID), [favorited.persistentModelID])
        XCTAssertEqual(kept.first?.uuid, StarterRecipe.uuid)
    }

    func testTwoEditedCopiesAreBothKeptUnderSeparateIdentities() throws {
        let context = try context()
        let older = insertCopy(in: context, createdAt: earlier)
        let newer = insertCopy(in: context, createdAt: later)
        older.touch()
        newer.touch()
        try StarterRecipe.collapseCopies(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 2)
        XCTAssertEqual(older.uuid, StarterRecipe.uuid)
        XCTAssertNotEqual(newer.uuid, StarterRecipe.uuid)
    }

    func testOneCopyIsLeftAlone() throws {
        let context = try context()
        _ = insertCopy(in: context, createdAt: earlier)
        try context.save()
        try StarterRecipe.collapseCopies(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 1)
    }
}
