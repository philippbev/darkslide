import XCTest
import SwiftData
@testable import FujiCookbook

/// Where an archive number goes with a recipe: a full backup carries it and a restore keeps it
/// (the next free one on a collision), a shared file leaves it out, and two recipes holding the
/// same number after a sync keep it on the older one.
@MainActor
final class ArchiveNumberTravelTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ArchiveNumberTravelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        containers = []
        super.tearDown()
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelStore.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        containers.append(container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    private func numbered(_ name: String, _ number: Int, day: Int = 1, in context: ModelContext) -> Recipe {
        let recipe = Recipe(name: name, settings: RecipeSettings(filmSimulation: .provia, clarity: number),
                            createdAt: date(day))
        recipe.archiveNumber = number
        context.insert(recipe)
        return recipe
    }

    private func restore(_ data: Data, into context: ModelContext) throws {
        let file = try RecipePortability.decodeFile(data)
        try RecipeImporter.applyBatch(file.allRecipes, chapters: file.chapters ?? [], resolutions: [:], into: context)
        try RecipeArchiveNumbering.assignMissing(in: context, defaults: defaults)
    }

    private func numbers(in context: ModelContext) throws -> [String: Int] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Recipe>()).map { ($0.name, $0.archiveNumber) })
    }

    // MARK: Backup and restore

    func testABackupCarriesTheNumberAndARestoreKeepsIt() throws {
        let source = try context()
        let first = numbered("Kodachrome", 3, in: source)
        let second = numbered("Tri-X", 7, in: source)
        let data = try RecipePortability.encodeBackup(recipes: [first, second], chapters: [], includePhotos: false)

        XCTAssertEqual(try RecipePortability.decodeFile(data).allRecipes.map(\.archiveNumber), [3, 7])

        let target = try context()
        try restore(data, into: target)
        XCTAssertEqual(try numbers(in: target), ["Kodachrome": 3, "Tri-X": 7])
    }

    func testARestoredNumberTheLibraryAlreadyHasGoesToTheNextFree() throws {
        let source = try context()
        let backedUp = numbered("Kodachrome", 2, in: source)
        let data = try RecipePortability.encodeBackup(recipes: [backedUp], chapters: [], includePhotos: false)

        let target = try context()
        _ = numbered("Local One", 1, in: target)
        _ = numbered("Local Two", 2, in: target)
        try target.save()
        try restore(data, into: target)

        XCTAssertEqual(try numbers(in: target), ["Local One": 1, "Local Two": 2, "Kodachrome": 3])
    }

    func testABackupWrittenBeforeArchiveNumbersStillRestores() throws {
        // A backup from before the key existed: no `archiveNumber` anywhere.
        let json = """
        {"schema": "fuji-recipe", "version": 1, "recipes": [{"name": "Old Backup", "uuid": "\(UUID().uuidString)",
          "settings": {"filmSimulation": "PROVIA"}}]}
        """
        let file = try RecipePortability.decodeFile(Data(json.utf8))
        XCTAssertNil(file.allRecipes.first?.archiveNumber)

        let target = try context()
        _ = numbered("Local", 5, in: target)
        try target.save()
        try restore(Data(json.utf8), into: target)
        XCTAssertEqual(try numbers(in: target)["Old Backup"], 6)
    }

    func testAnOverwriteKeepsTheLibrarysNumber() throws {
        let target = try context()
        let local = numbered("Kodachrome", 4, in: target)
        try target.save()
        var incoming = RecipePortability.portable(from: local, includeIdentity: true, includeArchiveNumber: true)
        incoming.archiveNumber = 9
        try RecipeImporter.applyBatch([incoming], chapters: [], resolutions: [0: .overwrite], into: target)
        XCTAssertEqual(local.archiveNumber, 4)
    }

    // MARK: Shared files

    func testSharedFilesLeaveTheNumberOut() throws {
        let source = try context()
        let recipe = numbered("Kodachrome", 12, in: source)
        let chapter = Chapter(name: "Street", recipeUUIDs: [recipe.uuid])
        source.insert(chapter)

        let single = try RecipePortability.decodeFile(RecipePortability.encodeSingle(recipe))
        let many = try RecipePortability.decodeFile(RecipePortability.encodeMany([recipe]))
        let snapshot = try XCTUnwrap(RecipeExportSnapshot.chapter(chapter, recipes: [recipe], includePhotos: false))
        let shared = try RecipePortability.decodeFile(RecipePortability.encode(snapshot))

        for file in [single, many, shared] {
            XCTAssertEqual(file.allRecipes.map(\.archiveNumber), [nil])
        }
        // The raw JSON doesn't name the key either.
        let raw = String(decoding: try RecipePortability.encodeSingle(recipe), as: UTF8.self)
        XCTAssertFalse(raw.contains("archiveNumber"))
    }

    func testAnImportedSharedRecipeGetsTheNextFreeNumber() throws {
        let source = try context()
        let shared = numbered("Shared", 12, in: source)
        let data = try RecipePortability.encodeSingle(shared)

        let target = try context()
        _ = numbered("Local", 3, in: target)
        try target.save()
        try restore(data, into: target)
        XCTAssertEqual(try numbers(in: target)["Shared"], 4)
    }

    // MARK: iCloud duplicates

    func testTheOlderRecipeKeepsANumberTwoDevicesBothGave() throws {
        let library = try context()
        let older = numbered("Made on the iPhone", 5, day: 1, in: library)
        let newer = numbered("Made on the iPad", 5, day: 2, in: library)
        _ = numbered("Other", 6, day: 3, in: library)
        try library.save()

        XCTAssertEqual(try RecipeArchiveNumbering.assignMissing(in: library, defaults: defaults), 1)

        XCTAssertEqual(older.archiveNumber, 5)
        XCTAssertEqual(newer.archiveNumber, 7)
    }

    func testTheNumberingNoticesASharedNumber() {
        XCTAssertEqual(ArchiveNumberingState(numbers: [1, 2, 2, 0]),
                       ArchiveNumberingState(numbers: [2, 1, 0, 2]))
        let state = ArchiveNumberingState(numbers: [1, 2, 2, 0])
        XCTAssertEqual(state.unnumbered, 1)
        XCTAssertEqual(state.sharedNumbers, 1)
        XCTAssertEqual(state.highest, 2)
        XCTAssertTrue(state.needsWork)
        XCTAssertFalse(ArchiveNumberingState(numbers: []).needsWork)
    }

    func testSharedNumbersInThePlanKeepTheOlderAndRenumberTheRestInOrder() {
        typealias Entry = RecipeArchiveNumbering.Entry<Int>
        let entries = [Entry(id: 1, uuid: UUID(), number: 3, createdAt: date(5)),
                       Entry(id: 2, uuid: UUID(), number: 3, createdAt: date(2)),
                       Entry(id: 3, uuid: UUID(), number: 3, createdAt: date(9)),
                       Entry(id: 4, uuid: UUID(), number: 0, createdAt: date(7))]
        let plan = RecipeArchiveNumbering.plan(for: entries, highWater: 3)
        // 2 is oldest and keeps 3; then by createdAt: 1 (day 5), 4 (day 7), 3 (day 9).
        XCTAssertEqual(plan.assignments, [1: 4, 4: 5, 3: 6])
    }
}
