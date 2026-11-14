import XCTest
import SwiftData
@testable import FujiCookbook

/// Archive numbers: handed out in order of creation, kept for good, never handed out twice, even
/// after the recipe that held one is deleted.
final class RecipeArchiveNumberingTests: XCTestCase {

    private typealias Numbering = RecipeArchiveNumbering
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RecipeArchiveNumberingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(day) * 86_400) }

    private func entry(_ id: Int, number: Int = 0, day: Int, uuid: UUID = UUID()) -> Numbering.Entry<Int> {
        Numbering.Entry(id: id, uuid: uuid, number: number, createdAt: date(day))
    }

    private func makeContext(url: URL? = nil) throws -> ModelContext {
        let configuration = url.map { ModelConfiguration(url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: SharedModelStore.schema, configurations: configuration))
    }

    // MARK: The plan

    func testAnUnnumberedLibraryIsNumberedOldestFirst() {
        let plan = Numbering.plan(for: [entry(1, day: 30), entry(2, day: 10), entry(3, day: 20)], highWater: 0)
        XCTAssertEqual(plan.assignments, [2: 1, 3: 2, 1: 3])
        XCTAssertEqual(plan.highWater, 3)
    }

    func testANewRecipeGetsTheNextNumber() {
        let plan = Numbering.plan(for: [entry(1, number: 1, day: 1), entry(2, number: 2, day: 2), entry(3, day: 3)],
                                  highWater: 2)
        XCTAssertEqual(plan.assignments, [3: 3])
    }

    func testADeletedRecipesNumberIsNotHandedOutAgain() {
        // Number 5 belonged to a recipe that is gone; the mark remembers it.
        let plan = Numbering.plan(for: [entry(1, number: 4, day: 1), entry(2, day: 2)], highWater: 5)
        XCTAssertEqual(plan.assignments, [2: 6])
    }

    func testNumbersFromAnotherDeviceRaiseTheCount() {
        // Synced in with 9, above this device's mark of 3.
        let plan = Numbering.plan(for: [entry(1, number: 9, day: 1), entry(2, day: 2)], highWater: 3)
        XCTAssertEqual(plan.assignments, [2: 10])
        XCTAssertEqual(plan.highWater, 10)
    }

    func testNumberedRecipesKeepTheirNumbers() {
        // An older recipe arriving unnumbered doesn't renumber the ones that have numbers.
        let plan = Numbering.plan(for: [entry(1, number: 1, day: 5), entry(2, day: 1)], highWater: 1)
        XCTAssertEqual(plan.assignments, [2: 2])
    }

    func testTiesInCreationDateFollowTheUUIDSoEveryRunAgrees() {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        let forward = Numbering.plan(for: [entry(1, day: 1, uuid: high), entry(2, day: 1, uuid: low)], highWater: 0)
        let backward = Numbering.plan(for: [entry(2, day: 1, uuid: low), entry(1, day: 1, uuid: high)], highWater: 0)
        XCTAssertEqual(forward.assignments, [2: 1, 1: 2])
        XCTAssertEqual(forward, backward)
    }

    func testCopiesSharingAUUIDStillGetANumberEach() {
        let shared = UUID()
        let plan = Numbering.plan(for: [entry(1, day: 1, uuid: shared), entry(2, day: 1, uuid: shared)], highWater: 0)
        XCTAssertEqual(Set(plan.assignments.values), [1, 2])
    }

    // MARK: In the store

    func testTheFirstRunNumbersRecipesSavedBeforeTheColumnExisted() throws {
        let context = try makeContext()
        let newest = Recipe(name: "Newest", createdAt: date(3))
        let oldest = Recipe(name: "Oldest", createdAt: date(1))
        let middle = Recipe(name: "Middle", createdAt: date(2))
        [newest, oldest, middle].forEach(context.insert)
        try context.save()
        XCTAssertEqual([oldest, middle, newest].map(\.archiveNumber), [0, 0, 0], "what lightweight migration leaves")

        XCTAssertEqual(try Numbering.assignMissing(in: context, defaults: defaults), 3)

        XCTAssertEqual([oldest, middle, newest].map(\.archiveNumber), [1, 2, 3])
        XCTAssertEqual(defaults.integer(forKey: Numbering.highWaterKey), 3)
        XCTAssertEqual(try Numbering.assignMissing(in: context, defaults: defaults), 0, "a second run changes nothing")
    }

    func testDeletingTheNewestRecipeDoesNotFreeItsNumber() throws {
        let context = try makeContext()
        let first = Recipe(name: "First", createdAt: date(1))
        let second = Recipe(name: "Second", createdAt: date(2))
        [first, second].forEach(context.insert)
        try Numbering.assignMissing(in: context, defaults: defaults)

        context.delete(second)
        try context.save()
        let third = Recipe(name: "Third", createdAt: date(3))
        context.insert(third)
        try Numbering.assignMissing(in: context, defaults: defaults)

        XCTAssertEqual(third.archiveNumber, 3)
    }

    func testARecipeInAnOpenEditorWaitsForItsNumber() throws {
        let context = try makeContext()
        let saved = Recipe(name: "Saved", createdAt: date(1))
        let draft = Recipe(name: "New Recipe", createdAt: date(2))
        [saved, draft].forEach(context.insert)
        try context.save()

        try Numbering.assignMissing(in: context, excluding: [draft.uuid], defaults: defaults)
        XCTAssertEqual(saved.archiveNumber, 1)
        XCTAssertEqual(draft.archiveNumber, 0)

        // Cancelled: the draft is deleted, and no number was spent on it.
        context.delete(draft)
        let next = Recipe(name: "Next", createdAt: date(3))
        context.insert(next)
        try Numbering.assignMissing(in: context, defaults: defaults)
        XCTAssertEqual(next.archiveNumber, 2)
    }

    func testNumbersSurviveReopeningTheStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-numbers-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        do {
            let context = try makeContext(url: url)
            context.insert(Recipe(name: "Kept", createdAt: date(1)))
            try Numbering.assignMissing(in: context, defaults: defaults)
        }
        let reopened = try makeContext(url: url)
        let recipes = try reopened.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.map(\.archiveNumber), [1])
    }
}
