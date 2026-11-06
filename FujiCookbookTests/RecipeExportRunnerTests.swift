import XCTest
import SwiftData
@testable import FujiCookbook

/// Export runs off the main actor: the check reports its photos, stops when cancelled, and the
/// runner hands back a file only for the run still current.
@MainActor
final class RecipeExportRunnerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(for: SharedModelStore.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private func recipes(_ count: Int, photosEach: Int, prefix: String = "Recipe") -> [Recipe] {
        let image = ImportTestFixtures.jpeg()
        return (0..<count).map { index in
            let recipe = Recipe(name: "\(prefix) \(index)")
            context.insert(recipe)
            recipe.photos = (0..<photosEach).map {
                RecipePhoto(imageData: image, thumbnailData: image, sortOrder: $0)
            }
            return recipe
        }
    }

    // MARK: The check

    func testTheCheckReportsEachPhotoItRunsThroughImport() throws {
        let snapshot = RecipeExportSnapshot.many(recipes(3, photosEach: 2), includePhotos: true)
        var seen: [RecipeExportValidation.Progress] = []
        _ = try RecipePortability.encode(snapshot) { seen.append($0) }
        XCTAssertEqual(seen.map(\.completed), Array(0...6))
        XCTAssertTrue(seen.allSatisfy { $0.total == 6 })
    }

    func testAnExportWithoutPhotosReportsNoProgress() throws {
        let snapshot = RecipeExportSnapshot.many(recipes(3, photosEach: 2), includePhotos: false)
        var calls = 0
        _ = try RecipePortability.encode(snapshot) { _ in calls += 1 }
        XCTAssertEqual(calls, 0)
    }

    func testCancellingStopsTheCheckBeforeTheFileIsBuilt() async {
        let snapshot = RecipeExportSnapshot.many(recipes(3, photosEach: 2), includePhotos: true)
        let task = Task.detached {
            try RecipePortability.encode(snapshot) { progress in
                if progress.completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await task.value
            XCTFail("a cancelled export must not produce a file")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    // MARK: The file name

    func testTheFileNameEndsWithTheLocalDate() throws {
        let noon = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        XCTAssertEqual(RecipeExporter.fileName(for: "Fuji Cookbook Backup", on: noon),
                       "Fuji Cookbook Backup 2026-10-05.fujirecipe")
        XCTAssertEqual(RecipeExporter.fileName(for: "Harbour: Light/2", on: noon),
                       "Harbour- Light-2 2026-10-05.fujirecipe", "unsafe characters still become dashes")
        XCTAssertEqual(RecipeExporter.fileName(for: "  ", on: noon), "Recipe 2026-10-05.fujirecipe")
    }

    func testTheDateIsTheDayWhereTheUserIsNotUTC() throws {
        // Late evening west of Greenwich is already tomorrow in UTC; the name follows the user's day.
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        let lateEvening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5,
                                                                           hour: 23, minute: 30)))
        XCTAssertEqual(lateEvening.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()),
                       "2026-10-06", "precondition: in UTC it is already the next day")
        XCTAssertTrue(RecipeExporter.fileName(for: "Backup", on: lateEvening, in: losAngeles)
            .hasSuffix("2026-10-05.fujirecipe"))
    }

    // MARK: The runner

    func testTheRunnerDeliversAFileThatImportsAgain() async throws {
        let runner = RecipeExportRunner()
        let exported = recipes(2, photosEach: 1)
        let delivered = expectation(description: "export finished")
        var outcome: Result<URL, Error>?
        runner.start(.many(exported, includePhotos: true), named: "Runner Test") { result in
            outcome = result
            delivered.fulfill()
        }
        XCTAssertTrue(runner.isExporting)
        await fulfillment(of: [delivered], timeout: 10)
        XCTAssertFalse(runner.isExporting)
        XCTAssertNil(runner.progress)
        let url = try XCTUnwrap(outcome).get()
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Runner Test 20"), url.lastPathComponent)
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".fujirecipe"), url.lastPathComponent)
        let prepared = try RecipeImportPreparation.prepare(.file(url))
        XCTAssertEqual(prepared.recipes.map(\.recipe.name), exported.map(\.name))
        XCTAssertEqual(prepared.recipes.map { $0.photos?.count }, [1, 1])
    }

    func testARefusedExportComesBackAsTheError() async {
        let runner = RecipeExportRunner()
        let unsafe = Recipe(name: "Unsafe", settings: RecipeSettings(exposureBias: .infinity))
        let delivered = expectation(description: "refusal delivered")
        runner.start(.single(unsafe, includePhotos: false), named: "Unsafe") { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error as? RecipeExportError, .unsafeNumber(recipe: "Unsafe", field: "exposureBias"))
            } else {
                XCTFail("an unsafe number must not export")
            }
            delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: 10)
    }

    func testACancelledRunNeverCallsBack() async {
        let runner = RecipeExportRunner()
        let called = expectation(description: "no completion after cancel")
        called.isInverted = true
        runner.start(.many(recipes(3, photosEach: 2), includePhotos: true), named: "Cancelled") { _ in
            called.fulfill()
        }
        runner.cancel()
        XCTAssertFalse(runner.isExporting)
        XCTAssertNil(runner.progress)
        await fulfillment(of: [called], timeout: 1)
    }

    func testANewerRunReplacesAnOlderOne() async {
        let runner = RecipeExportRunner()
        let first = expectation(description: "the replaced run never calls back")
        first.isInverted = true
        let second = expectation(description: "the newer run delivers")
        runner.start(.many(recipes(2, photosEach: 2, prefix: "First"), includePhotos: true), named: "First") { _ in
            first.fulfill()
        }
        runner.start(.many(recipes(1, photosEach: 0, prefix: "Second"), includePhotos: false), named: "Second") { result in
            XCTAssertEqual(try? result.get().lastPathComponent.hasPrefix("Second 20"), true)
            second.fulfill()
        }
        await fulfillment(of: [second], timeout: 10)
        await fulfillment(of: [first], timeout: 0.5)
    }
}
