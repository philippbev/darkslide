import XCTest
import SwiftData
@testable import FujiCookbook

/// Sharing one chapter: what goes into the file, and that opening the file restores the chapter.
@MainActor
final class ChapterShareTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    /// A fresh in-memory library. CloudKit stays off: a unit-test store on a simulator has no
    /// iCloud account.
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelStore.schema,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                             cloudKitDatabase: .none))
        retainedContainers.append(container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func library(in context: ModelContext) -> (velvia: Recipe, chrome: Recipe, acros: Recipe) {
        let velvia = Recipe(name: "Velvia Daily", settings: RecipeSettings(filmSimulation: .velvia))
        let chrome = Recipe(name: "Chrome Street", settings: RecipeSettings(filmSimulation: .classicChrome))
        let acros = Recipe(name: "Acros Night", settings: RecipeSettings(filmSimulation: .acros))
        [velvia, chrome, acros].forEach(context.insert)
        return (velvia, chrome, acros)
    }

    private func importFile(_ data: Data, into context: ModelContext) throws {
        let prepared = try RecipeImportPreparation.prepare(.data(data))
        try RecipeImporter.applyBatch(prepared.recipes.map(\.recipe), chapters: prepared.chapters,
                                      prepared: prepared.recipes, resolutions: [:], into: context)
    }

    private func names(of chapter: Chapter, in context: ModelContext) throws -> [String] {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        return chapter.recipeUUIDs.compactMap { id in recipes.first { $0.uuid == id }?.name }
    }

    func testSnapshotHoldsTheChaptersRecipesInSlotOrderAndNothingElse() throws {
        let context = try context()
        let recipes = library(in: context)
        let chapter = Chapter(name: "Street", recipeUUIDs: [recipes.chrome.uuid, recipes.velvia.uuid])

        let snapshot = try XCTUnwrap(RecipeExportSnapshot.chapter(
            chapter, recipes: [recipes.velvia, recipes.chrome, recipes.acros], includePhotos: false))

        XCTAssertEqual(snapshot.entries.map(\.recipe.name), ["Chrome Street", "Velvia Daily"])
        XCTAssertEqual(snapshot.entries.map(\.recipe.uuid), [recipes.chrome.uuid, recipes.velvia.uuid],
                       "without its uuid a recipe can't be re-linked to the chapter on import")
        XCTAssertEqual(snapshot.chapters, [PortableChapter(name: "Street",
                                                           recipeUUIDs: [recipes.chrome.uuid, recipes.velvia.uuid])])
        XCTAssertEqual(snapshot.photoCount, 0)
    }

    func testSlotWhoseRecipeIsGoneIsLeftOutOfTheFileAndTheChapter() throws {
        let context = try context()
        let recipes = library(in: context)
        let chapter = Chapter(name: "Street", recipeUUIDs: [recipes.chrome.uuid, UUID(), recipes.acros.uuid])

        let snapshot = try XCTUnwrap(RecipeExportSnapshot.chapter(
            chapter, recipes: [recipes.velvia, recipes.chrome, recipes.acros], includePhotos: false))

        XCTAssertEqual(snapshot.entries.map(\.recipe.name), ["Chrome Street", "Acros Night"])
        XCTAssertEqual(snapshot.chapters?.first?.recipeUUIDs, [recipes.chrome.uuid, recipes.acros.uuid])
    }

    func testChapterWithNothingToShareGivesNoSnapshot() throws {
        let context = try context()
        let recipes = library(in: context)
        let all = [recipes.velvia, recipes.chrome, recipes.acros]

        XCTAssertNil(RecipeExportSnapshot.chapter(Chapter(name: "Empty"), recipes: all, includePhotos: false))
        XCTAssertNil(RecipeExportSnapshot.chapter(Chapter(name: "Orphaned", recipeUUIDs: [UUID()]),
                                                  recipes: all, includePhotos: false),
                     "a file without recipes is refused on import")
    }

    func testRecipeInTwoSlotsIsWrittenOnceAndKeepsBothSlots() throws {
        let context = try context()
        let recipes = library(in: context)
        let chapter = Chapter(name: "Twice", recipeUUIDs: [recipes.velvia.uuid, recipes.chrome.uuid, recipes.velvia.uuid])

        let snapshot = try XCTUnwrap(RecipeExportSnapshot.chapter(
            chapter, recipes: [recipes.velvia, recipes.chrome], includePhotos: false))
        XCTAssertEqual(snapshot.entries.map(\.recipe.name), ["Velvia Daily", "Chrome Street"])

        let destination = try self.context()
        try importFile(RecipePortability.encode(snapshot), into: destination)
        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<Chapter>()).first)
        XCTAssertEqual(try names(of: restored, in: destination), ["Velvia Daily", "Chrome Street", "Velvia Daily"])
        XCTAssertEqual(try destination.fetch(FetchDescriptor<Recipe>()).count, 2)
    }

    func testPhotosTravelOnlyWhenAsked() throws {
        let context = try context()
        let recipe = Recipe(name: "With Photo", settings: RecipeSettings(filmSimulation: .astia))
        let bytes = ImportTestFixtures.jpeg()
        recipe.photos = [RecipePhoto(imageData: bytes, thumbnailData: bytes, sortOrder: 0)]
        context.insert(recipe)
        let chapter = Chapter(name: "Photos", recipeUUIDs: [recipe.uuid])

        let without = try XCTUnwrap(RecipeExportSnapshot.chapter(chapter, recipes: [recipe], includePhotos: false))
        let with = try XCTUnwrap(RecipeExportSnapshot.chapter(chapter, recipes: [recipe], includePhotos: true))
        XCTAssertEqual(without.photoCount, 0)
        XCTAssertEqual(with.photoCount, 1)

        let file = try JSONDecoder().decode(RecipeFile.self, from: RecipePortability.encode(without))
        XCTAssertNil(file.allRecipes.first?.photos, "a recipes-only file omits the photos key")
    }

    func testOpeningASharedChapterInAnotherLibraryRestoresItInOrder() throws {
        let source = try context()
        let recipes = library(in: source)
        let chapter = Chapter(name: "Street", recipeUUIDs: [recipes.acros.uuid, recipes.velvia.uuid])
        source.insert(chapter)
        let snapshot = try XCTUnwrap(RecipeExportSnapshot.chapter(
            chapter, recipes: [recipes.velvia, recipes.chrome, recipes.acros], includePhotos: false))
        let data = try RecipePortability.encode(snapshot)

        let destination = try context()
        try importFile(data, into: destination)

        let imported = try destination.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(Set(imported.map(\.name)), ["Acros Night", "Velvia Daily"],
                       "a recipe outside the chapter doesn't travel with it")
        let restored = try destination.fetch(FetchDescriptor<Chapter>())
        XCTAssertEqual(restored.map(\.name), ["Street"])
        XCTAssertEqual(try names(of: restored[0], in: destination), ["Acros Night", "Velvia Daily"])
        XCTAssertEqual(imported.first { $0.name == "Acros Night" }?.settings.filmSimulation, .acros)
    }

    func testOpeningASharedChapterInItsOwnLibraryAddsNothing() throws {
        let context = try context()
        let recipes = library(in: context)
        let chapter = Chapter(name: "Street", recipeUUIDs: [recipes.chrome.uuid, recipes.velvia.uuid])
        context.insert(chapter)
        try context.save()
        let snapshot = try XCTUnwrap(RecipeExportSnapshot.chapter(
            chapter, recipes: [recipes.velvia, recipes.chrome, recipes.acros], includePhotos: false))

        // No resolutions: an identical recipe is skipped, as the review sheet defaults to.
        try importFile(RecipePortability.encode(snapshot), into: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Recipe>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Chapter>()).count, 1)
    }

    func testReceiverWhoAlreadyHasOneRecipeGetsTheChapterLinkedToIt() throws {
        let source = try context()
        let recipes = library(in: source)
        let chapter = Chapter(name: "Street", recipeUUIDs: [recipes.chrome.uuid, recipes.velvia.uuid])
        let snapshot = try XCTUnwrap(RecipeExportSnapshot.chapter(
            chapter, recipes: [recipes.velvia, recipes.chrome], includePhotos: false))

        let destination = try context()
        let owned = Recipe(name: "Velvia Daily", settings: RecipeSettings(filmSimulation: .velvia))
        destination.insert(owned)
        try destination.save()
        try importFile(RecipePortability.encode(snapshot), into: destination)

        XCTAssertEqual(try destination.fetch(FetchDescriptor<Recipe>()).count, 2, "the recipe already owned isn't doubled")
        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<Chapter>()).first)
        XCTAssertEqual(try names(of: restored, in: destination), ["Chrome Street", "Velvia Daily"])
        XCTAssertEqual(restored.recipeUUIDs.last, owned.uuid)
    }

    func testSharedFileIsNamedAfterTheChapter() {
        let date = Date(timeIntervalSince1970: 1_794_571_200) // 2026-11-13 12:00 UTC
        XCTAssertEqual(RecipeExporter.fileName(for: "Street / Night", on: date, in: TimeZone(identifier: "UTC")!),
                       "Street - Night 2026-11-13.fujirecipe")
    }
}
