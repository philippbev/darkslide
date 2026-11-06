import XCTest
import UIKit
import ImageIO
@testable import FujiCookbook

enum ImportTestFixtures {
    static func data(_ recipes: [PortableRecipe], chapters: [PortableChapter]? = nil) throws -> Data {
        try RecipePortability.encode(RecipeFile(recipes: recipes, chapters: chapters))
    }

    static func jpeg(width: Int = 32, height: Int = 24) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).jpegData(withCompressionQuality: 0.8) {
            UIColor.orange.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func dimensions(_ bytes: Data) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
                try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int))
    }
}

@MainActor
final class RecipeImportPreparationTests: XCTestCase {
    func testUnsafeKnownNumbersAreRejectedWithoutChangingStoredDecoding() throws {
        for settings in [#"{"highlightTone":1e100}"#, #"{"shadowTone":-1e100}"#,
                         #"{"color":9223372036854775807}"#,
                         #"{"whiteBalance":{"mode":"AUTO","shiftRed":2147483648}}"#] {
            let data = Data("{\"schema\":\"fuji-recipe\",\"version\":1,\"recipe\":{\"name\":\"Test\",\"settings\":\(settings)}}".utf8)
            XCTAssertThrowsError(try RecipePortability.decodeFile(data)) {
                guard case RecipeFileError.unsafeNumber(recipe: 1, field: _) = $0 else {
                    return XCTFail("Unexpected error: \($0)")
                }
            }
            // This is also SwiftData's decoder: do not make an old saved recipe unreadable.
            XCTAssertNoThrow(try JSONDecoder().decode(RecipeSettings.self, from: Data(settings.utf8)))
        }
    }

    func testCameraRangeOutliersAndUnknownFieldsArePreserved() throws {
        let unknown: [String: JSONValue] = ["future": .object(["large": .number(1e100), "array": .array([.null, .bool(true)])])]
        let recipe = PortableRecipe(name: "Future body", cameraName: "MY CUSTOM", cameraNameIsCustom: true,
                                    credit: "Example author", authoredForModel: "FUTURE-1", notes: "A note",
                                    tags: ["sample"], settings: RecipeSettings(highlightTone: 12.5, color: -20),
                                    unsupportedFields: unknown)
        let result = try RecipeImportPreparation.prepare(.data(ImportTestFixtures.data([recipe])))
        XCTAssertEqual(result.recipes.first?.recipe, recipe)
        XCTAssertNil(result.recipes.first?.photos)
    }

    func testFileBudgetIsEnforcedForMemoryAndBoundedFileReads() throws {
        let data = try ImportTestFixtures.data([PortableRecipe(name: "Small", settings: .neutral)])
        var limits = RecipeImportLimits.standard
        limits.fileBytes = data.count
        XCTAssertNoThrow(try RecipePortability.decodeFile(data, limits: limits))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        XCTAssertEqual(try RecipeImportPreparation.read(url, limits: limits), data)
        limits.fileBytes -= 1
        XCTAssertThrowsError(try RecipePortability.decodeFile(data, limits: limits))
        XCTAssertThrowsError(try RecipeImportPreparation.read(url, limits: limits))
    }

    func testBatchAndPhotoCountLimitsRejectWithoutTruncating() throws {
        let recipe = PortableRecipe(name: "One", settings: .neutral)
        var limits = RecipeImportLimits.standard
        limits.recipes = 1
        XCTAssertThrowsError(try RecipePortability.decodeFile(ImportTestFixtures.data([recipe, recipe]), limits: limits))
        limits.chapters = 0
        XCTAssertThrowsError(try RecipePortability.decodeFile(
            ImportTestFixtures.data([recipe], chapters: [PortableChapter(name: "Chapter", recipeUUIDs: [])]), limits: limits))
        var tooManyPhotos = recipe
        tooManyPhotos.photos = Array(repeating: PortablePhoto(data: "invalid"), count: 6)
        XCTAssertThrowsError(try RecipeImportPreparation.prepare(.data(ImportTestFixtures.data([tooManyPhotos])))) {
            XCTAssertTrue($0.localizedDescription.contains("more than 5"))
        }
    }

    func testInvalidImagesAreSkippedWhileValidJPEGBytesAndOrderSurvive() throws {
        let first = ImportTestFixtures.jpeg()
        let second = ImportTestFixtures.jpeg(width: 40, height: 30)
        let recipe = PortableRecipe(name: "Pictures", settings: .neutral, photos: [
            PortablePhoto(data: first.base64EncodedString()), PortablePhoto(data: "not-base64!"),
            PortablePhoto(data: Data("not an image".utf8).base64EncodedString()),
            PortablePhoto(data: second.base64EncodedString())
        ])
        let result = try RecipeImportPreparation.prepare(.data(ImportTestFixtures.data([recipe])))
        let prepared = try XCTUnwrap(result.recipes.first)
        XCTAssertEqual(prepared.skippedPhotos, 2)
        XCTAssertNil(prepared.recipe.photos, "encoded payloads are released after staging")
        let photos = try XCTUnwrap(prepared.photos)
        XCTAssertEqual(photos.count, 2)
        XCTAssertEqual(try photos[0].load().full, first)
        XCTAssertEqual(try photos[1].load().full, second)
    }

    func testLargeImagesAreDownsampledAndImageBudgetsAreEnforced() throws {
        let original = ImportTestFixtures.jpeg(width: 2560, height: 1920)
        let recipe = PortableRecipe(name: "Large", settings: .neutral,
                                    photos: [PortablePhoto(data: original.base64EncodedString())])
        let data = try ImportTestFixtures.data([recipe])
        let result = try RecipeImportPreparation.prepare(.data(data))
        let photo = try XCTUnwrap(result.recipes.first?.photos?.first).load()
        let size = try ImportTestFixtures.dimensions(photo.full)
        let thumbnail = try ImportTestFixtures.dimensions(photo.thumbnail)
        XCTAssertEqual(size.0, 1280)
        XCTAssertEqual(size.1, 960)
        XCTAssertEqual(thumbnail.0, 240)
        var limits = RecipeImportLimits.standard
        limits.photoBytes = original.count - 1
        XCTAssertThrowsError(try RecipeImportPreparation.prepare(.data(data), limits: limits))
        limits.photoBytes = original.count
        limits.preparedPhotoBytes = 1
        XCTAssertThrowsError(try RecipeImportPreparation.prepare(.data(data), limits: limits))
    }

    func testPreparationDistinguishesAbsentEmptyAndWhollyInvalidPhotos() throws {
        let recipes = [PortableRecipe(name: "Absent", settings: .neutral),
                       PortableRecipe(name: "Empty", settings: .neutral, photos: []),
                       PortableRecipe(name: "Invalid", settings: .neutral, photos: [PortablePhoto(data: "invalid!")])]
        let result = try RecipeImportPreparation.prepare(.data(ImportTestFixtures.data(recipes)))
        XCTAssertNil(result.recipes[0].photos)
        XCTAssertEqual(result.recipes[1].photos?.count, 0)
        XCTAssertNil(result.recipes[2].photos)
        XCTAssertEqual(result.recipes[2].skippedPhotos, 1)
    }
}
