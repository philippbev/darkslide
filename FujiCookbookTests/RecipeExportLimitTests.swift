import XCTest
import SwiftData
import UIKit
@testable import FujiCookbook

/// An export must never produce a file the app's own import refuses: a backup that can't be
/// restored is worse than no backup.
@MainActor
final class RecipeExportLimitTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(for: SharedModelStore.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private func recipe(_ name: String, photoBytes: [Int] = [], notes: String = "") -> Recipe {
        let recipe = Recipe(name: name)
        recipe.notes = notes
        context.insert(recipe)
        recipe.photos = photoBytes.enumerated().map { index, count in
            RecipePhoto(imageData: Data(repeating: 0xFF, count: count),
                        thumbnailData: Data(repeating: 0xEE, count: 16), sortOrder: index)
        }
        return recipe
    }

    private func recipeWithPhotos(_ name: String, _ photos: [(full: Data, thumbnail: Data)]) -> Recipe {
        let recipe = recipe(name)
        recipe.photos = photos.enumerated().map { index, photo in
            RecipePhoto(imageData: photo.full, thumbnailData: photo.thumbnail, sortOrder: index)
        }
        return recipe
    }

    private func loadedPhotos(_ prepared: PreparedRecipeImport) throws -> [PhotoProcessing.Processed] {
        try prepared.recipes.flatMap { try ($0.photos ?? []).map { try $0.load() } }
    }

    /// Fine, repetitive detail compresses well as PNG but expands when import makes JPEG.
    private func expandingPNG() throws -> (source: Data, thumbnail: Data, prepared: PhotoProcessing.Processed) {
        let size = 1280
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size where (x + y) % 2 == 0 {
                let offset = (y * size + x) * 4
                pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: size, height: size, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let png = try XCTUnwrap(UIImage(cgImage: image).pngData())
        let thumbnail = try XCTUnwrap(PhotoProcessing.thumbnail(from: png))
        let prepared = try XCTUnwrap(PhotoProcessing.importedPhoto(png))
        XCTAssertGreaterThan(prepared.full.count + prepared.thumbnail.count, png.count + thumbnail.count,
                             "fixture must expose the original size underestimate")
        return (png, thumbnail, prepared)
    }

    private func limits(_ change: (inout RecipeImportLimits) -> Void) -> RecipeImportLimits {
        var limits = RecipeImportLimits.standard
        change(&limits)
        return limits
    }

    private func assertRefused(_ body: () throws -> Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case RecipeExportError.exceedsImportLimit = error else {
                return XCTFail("expected exceedsImportLimit, got \(error)", file: file, line: line)
            }
        }
    }

    func testABackupWithinTheLimitsImportsAgainUnderTheSameLimits() throws {
        let small = limits { $0.fileBytes = 64 * 1024 }
        let originals = [ImportTestFixtures.jpeg(), ImportTestFixtures.jpeg(width: 40, height: 30)]
        let photos = try originals.map { image in
            (full: image, thumbnail: try XCTUnwrap(PhotoProcessing.thumbnail(from: image)))
        }
        let recipes = [recipeWithPhotos("Harbour Light", photos), recipe("Port Morning")]
        let chapter = Chapter(name: "Morning", recipeUUIDs: recipes.map(\.uuid))
        let data = try RecipePortability.encodeBackup(recipes: recipes, chapters: [chapter], includePhotos: true,
                                                      limits: small)
        let prepared = try RecipeImportPreparation.prepare(.data(data), limits: small)
        XCTAssertEqual(prepared.recipes.map(\.recipe.name), recipes.map(\.name))
        XCTAssertEqual(prepared.chapters, [RecipePortability.portableChapter(from: chapter)])
        XCTAssertEqual(prepared.recipes[0].photos?.count, 2)
        XCTAssertNil(prepared.recipes[1].photos)
        XCTAssertTrue(prepared.recipes.allSatisfy { $0.skippedPhotos == 0 && $0.recipe.photos == nil })
        let restored = try loadedPhotos(prepared)
        XCTAssertEqual(restored.map(\.full), originals, "valid backup JPEGs must survive full preparation")
        XCTAssertTrue(restored.allSatisfy { !$0.thumbnail.isEmpty })
        XCTAssertLessThanOrEqual(restored.reduce(0) { $0 + $1.full.count + $1.thumbnail.count },
                                small.preparedPhotoBytes)
    }

    func testLegacyPNGExpansionIsRejectedBeforeAnUnrestorableExportIsProduced() throws {
        let fixture = try expandingPNG()
        let oldEstimate = fixture.source.count + fixture.thumbnail.count
        let normalized = fixture.prepared.full.count + fixture.prepared.thumbnail.count
        let budget = limits { $0.preparedPhotoBytes = oldEstimate + (normalized - oldEstimate) / 2 }
        let legacy = recipeWithPhotos("Legacy PNG", [(fixture.source, fixture.thumbnail)])
        // The old source+stored-thumbnail estimate fits, but the import's actual JPEGs do not.
        XCTAssertLessThanOrEqual(oldEstimate, budget.preparedPhotoBytes)
        XCTAssertGreaterThan(normalized, budget.preparedPhotoBytes)
        assertRefused { try RecipePortability.encodeSingle(legacy, includePhotos: true, limits: budget) }
        let unchecked = try RecipePortability.encode(.single(RecipePortability.portable(from: legacy, includePhotos: true)))
        XCTAssertThrowsError(try RecipeImportPreparation.prepare(.data(unchecked), limits: budget)) { error in
            guard case RecipeFileError.resourceLimit = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testExactNormalizedPhotoBudgetExportsOriginalPNGAndPreparesSuccessfully() throws {
        let fixture = try expandingPNG()
        let exact = limits { $0.preparedPhotoBytes = fixture.prepared.full.count + fixture.prepared.thumbnail.count }
        let legacy = recipeWithPhotos("Legacy PNG", [(fixture.source, fixture.thumbnail)])
        let data = try RecipePortability.encodeSingle(legacy, includePhotos: true, limits: exact)
        let encoded = try RecipePortability.decodeFile(data, limits: exact)
        XCTAssertEqual(encoded.allRecipes.first?.photos?.first?.data, fixture.source.base64EncodedString(),
                       "budget validation must not re-encode or replace the exported original")
        let prepared = try RecipeImportPreparation.prepare(.data(data), limits: exact)
        XCTAssertEqual(prepared.recipes.first?.photos?.count, 1)
        XCTAssertEqual(prepared.recipes.first?.skippedPhotos, 0)
        let loaded = try XCTUnwrap(loadedPhotos(prepared).first)
        XCTAssertEqual(loaded.full, fixture.prepared.full)
        XCTAssertEqual(loaded.thumbnail, fixture.prepared.thumbnail)
        XCTAssertEqual(loaded.full.count + loaded.thumbnail.count, exact.preparedPhotoBytes)
    }

    func testPreparedPhotoBudgetAccumulatesAcrossPhotosAndRecipes() throws {
        let fixture = try expandingPNG()
        let photo = (full: fixture.source, thumbnail: fixture.thumbnail)
        let perPhoto = fixture.prepared.full.count + fixture.prepared.thumbnail.count
        let recipes = [recipeWithPhotos("Two photos", [photo, photo]), recipeWithPhotos("One photo", [photo])]
        let short = limits { $0.preparedPhotoBytes = 3 * perPhoto - 1 }
        // Each recipe fits alone; the combined file must not reset its budget between recipes.
        for recipe in recipes {
            XCTAssertNoThrow(try RecipePortability.encodeSingle(recipe, includePhotos: true, limits: short))
        }
        assertRefused { try RecipePortability.encodeMany(recipes, includePhotos: true, limits: short) }
        let exact = limits { $0.preparedPhotoBytes = 3 * perPhoto }
        let data = try RecipePortability.encodeMany(recipes, includePhotos: true, limits: exact)
        let prepared = try RecipeImportPreparation.prepare(.data(data), limits: exact)
        XCTAssertEqual(prepared.recipes.map { $0.photos?.count }, [2, 1])
        XCTAssertTrue(prepared.recipes.allSatisfy { $0.skippedPhotos == 0 })
        let restored = try loadedPhotos(prepared)
        XCTAssertEqual(restored.count, 3)
        XCTAssertEqual(restored.reduce(0) { $0 + $1.full.count + $1.thumbnail.count }, exact.preparedPhotoBytes)
    }

    func testJPEGUsesRegeneratedThumbnailSizeInsteadOfStaleStoredThumbnail() throws {
        let jpeg = ImportTestFixtures.jpeg(width: 320, height: 240)
        let actual = try XCTUnwrap(PhotoProcessing.importedPhoto(jpeg))
        let staleThumbnail = Data([0])
        XCTAssertEqual(actual.full, jpeg)
        XCTAssertGreaterThan(actual.thumbnail.count, staleThumbnail.count)
        let legacy = recipeWithPhotos("Stale thumbnail", [(jpeg, staleThumbnail)])
        let oldEstimate = jpeg.count + staleThumbnail.count
        let normalized = actual.full.count + actual.thumbnail.count
        let short = limits { $0.preparedPhotoBytes = oldEstimate + (normalized - oldEstimate) / 2 }
        assertRefused { try RecipePortability.encodeSingle(legacy, includePhotos: true, limits: short) }
        let exact = limits { $0.preparedPhotoBytes = normalized }
        let data = try RecipePortability.encodeSingle(legacy, includePhotos: true, limits: exact)
        let prepared = try RecipeImportPreparation.prepare(.data(data), limits: exact)
        XCTAssertEqual(prepared.recipes.first?.photos?.count, 1)
        XCTAssertEqual(prepared.recipes.first?.skippedPhotos, 0)
        let loaded = try XCTUnwrap(loadedPhotos(prepared).first)
        XCTAssertEqual(loaded.full, jpeg)
        XCTAssertEqual(loaded.thumbnail, actual.thumbnail)
        XCTAssertEqual(loaded.full.count + loaded.thumbnail.count, exact.preparedPhotoBytes)
    }

    func testInvalidImageConsumesNoPreparedBudgetAndIsSkippedOnImport() throws {
        let legacy = recipeWithPhotos("Invalid image", [(Data("not an image".utf8), Data(repeating: 0, count: 100))])
        let emptyBudget = limits { $0.preparedPhotoBytes = 0 }
        let data = try RecipePortability.encodeSingle(legacy, includePhotos: true, limits: emptyBudget)
        let prepared = try RecipeImportPreparation.prepare(.data(data), limits: emptyBudget)
        XCTAssertEqual(prepared.recipes.count, 1)
        XCTAssertEqual(prepared.recipes.first?.skippedPhotos, 1)
        XCTAssertNil(prepared.recipes.first?.photos)
    }

    func testPhotosThatWouldOverflowTheFileAreRefusedBeforeEncoding() {
        let small = limits { $0.fileBytes = 4_096 }
        let recipes = [recipe("Harbour Light", photoBytes: [4_000])]
        // The pre-check alone refuses it, so the oversized JSON is never built.
        XCTAssertThrowsError(try RecipeExportValidation.check(recipes, includePhotos: true, limits: small))
        assertRefused { try RecipePortability.encodeMany(recipes, includePhotos: true, limits: small) }
    }

    func testTheSameRecipesExportWithoutTheirPhotos() throws {
        let small = limits { $0.fileBytes = 4_096 }
        let recipes = [recipe("Harbour Light", photoBytes: [4_000])]
        let data = try RecipePortability.encodeMany(recipes, includePhotos: false, limits: small)
        XCTAssertNoThrow(try RecipePortability.decodeFile(data, limits: small))
    }

    func testTheEncodedSizeIsCheckedAfterEncoding() {
        let small = limits { $0.fileBytes = 2_000 }
        let recipes = (1...20).map { recipe("Recipe \($0)", notes: String(repeating: "n", count: 200)) }
        assertRefused { try RecipePortability.encodeMany(recipes, limits: small) }
    }

    func testTooManyRecipesOrChaptersAreRefused() {
        let recipes = (1...3).map { recipe("Recipe \($0)") }
        assertRefused { try RecipePortability.encodeMany(recipes, limits: limits { $0.recipes = 2 }) }
        let chapters = (1...3).map { Chapter(name: "Chapter \($0)", recipeUUIDs: []) }
        assertRefused {
            try RecipePortability.encodeBackup(recipes: recipes, chapters: chapters, includePhotos: false,
                                               limits: limits { $0.chapters = 2 })
        }
    }

    func testMoreThanTheImportablePhotosPerRecipeIsRefused() {
        let crowded = recipe("Harbour Light", photoBytes: Array(repeating: 100, count: Recipe.maxPhotos + 1))
        assertRefused { try RecipePortability.encodeSingle(crowded, includePhotos: true) }
    }

    func testTheRefusalSaysHowToExportInstead() {
        let error = RecipeExportError.exceedsImportLimit(detail: "Too big.")
        XCTAssertEqual(error.errorDescription, "Too big. Nothing was exported.")
    }
}
