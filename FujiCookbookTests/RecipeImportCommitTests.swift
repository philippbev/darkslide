import XCTest
import SwiftData
@testable import FujiCookbook

@MainActor
final class RecipeImportCommitTests: XCTestCase {
    private var retainedContainer: ModelContainer?

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelStore.schema,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                             cloudKitDatabase: .none))
        // Keep the backing store alive for the fixture, and do not start CloudKit mirroring for
        // an in-memory unit-test database on a simulator with no iCloud account.
        retainedContainer = container
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func testInvalidPhotosDoNotEraseExistingOnOverwriteButExplicitEmptyDoes() throws {
        let context = try context()
        let existing = Recipe(name: "Existing", settings: .neutral)
        let bytes = ImportTestFixtures.jpeg()
        existing.photos = [RecipePhoto(imageData: bytes, thumbnailData: bytes, sortOrder: 0)]
        context.insert(existing)
        for (photos, shouldRemain) in [([PortablePhoto(data: "broken!")], true), ([], false)] {
            let incoming = PortableRecipe(name: "Existing", settings: RecipeSettings(clarity: 2), photos: photos)
            let prepared = try RecipeImportPreparation.prepare(.data(ImportTestFixtures.data([incoming])))
            try RecipeImporter.applyBatch(prepared.recipes.map(\.recipe), chapters: [],
                                          prepared: prepared.recipes, resolutions: [0: .overwrite], into: context)
            XCTAssertEqual(existing.photos?.count, shouldRemain ? 1 : 0)
            if shouldRemain { XCTAssertEqual(existing.photos?.first?.imageData, bytes) }
        }
    }

    func testMissingStagedFileRollsBackEarlierInsertAndPreservesPriorPendingEdits() throws {
        let context = try context()
        let prior = Recipe(name: "Prior", settings: RecipeSettings(filmSimulation: .velvia))
        context.insert(prior)
        try context.save()
        prior.notes = "An unrelated pending edit"
        let first = PortableRecipe(name: "First", settings: RecipeSettings(filmSimulation: .provia))
        let second = PortableRecipe(name: "Second", settings: RecipeSettings(filmSimulation: .astia),
                                    photos: [PortablePhoto(data: ImportTestFixtures.jpeg().base64EncodedString())])
        let prepared = try RecipeImportPreparation.prepare(.data(ImportTestFixtures.data([first, second])))
        let missing = try XCTUnwrap(prepared.recipes[1].photos?.first?.imageURL)
        try FileManager.default.removeItem(at: missing)
        XCTAssertThrowsError(try RecipeImporter.applyBatch(prepared.recipes.map(\.recipe), chapters: [],
                                                          prepared: prepared.recipes, resolutions: [:], into: context))
        let saved = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.name, "Prior")
        XCTAssertEqual(saved.first?.notes, "An unrelated pending edit")
    }

    func testFullBackupRelinksChapterAndPreservesUnknownFieldsAndCustomName() throws {
        let context = try context()
        let firstID = UUID(), secondID = UUID()
        let first = PortableRecipe(name: "One", uuid: firstID, cameraName: "CUSTOM", cameraNameIsCustom: true,
                                   credit: "Photographer", authoredForModel: "FUTURE", notes: "Notes", tags: ["tag"],
                                   settings: RecipeSettings(filmSimulation: .velvia),
                                   unsupportedFields: ["unknown": .number(1e100)])
        let second = PortableRecipe(name: "Two", uuid: secondID, settings: RecipeSettings(shadowTone: 1.5))
        let chapter = PortableChapter(name: "Restored", recipeUUIDs: [secondID, firstID])
        let prepared = try RecipeImportPreparation.prepare(.data(ImportTestFixtures.data([first, second], chapters: [chapter])))
        try RecipeImporter.applyBatch(prepared.recipes.map(\.recipe), chapters: prepared.chapters,
                                      prepared: prepared.recipes, resolutions: [:], into: context)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let one = try XCTUnwrap(recipes.first { $0.name == "One" })
        let two = try XCTUnwrap(recipes.first { $0.name == "Two" })
        XCTAssertEqual(one.effectiveCameraName, "CUSTOM")
        XCTAssertEqual(one.credit, "Photographer")
        XCTAssertEqual(one.unsupportedFields, ["unknown": .number(1e100)])
        XCTAssertNil(two.settings.filmSimulation)
        XCTAssertNotEqual(one.uuid, firstID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Chapter>()).first?.recipeUUIDs, [two.uuid, one.uuid])
    }
}
