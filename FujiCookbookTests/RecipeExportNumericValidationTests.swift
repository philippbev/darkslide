import XCTest
import SwiftData
@testable import FujiCookbook

@MainActor
final class RecipeExportNumericValidationTests: XCTestCase {
    private enum EntryPoint: CaseIterable { case single, many, backup }
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

    private func encode(_ recipe: Recipe, using entryPoint: EntryPoint, includePhotos: Bool,
                        preceding: Recipe? = nil) throws -> Data {
        let recipes = preceding.map { [$0, recipe] } ?? [recipe]
        switch entryPoint {
        case .single:
            return try RecipePortability.encodeSingle(recipe, includePhotos: includePhotos)
        case .many:
            return try RecipePortability.encodeMany(recipes, includePhotos: includePhotos)
        case .backup:
            return try RecipePortability.encodeBackup(recipes: recipes, chapters: [], includePhotos: includePhotos)
        }
    }

    private func assertUnsafe(_ body: () throws -> Void, recipe: String, field: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case RecipeExportError.unsafeNumber(let actualRecipe, let actualField) = error else {
                return XCTFail("Expected export numeric error, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(actualRecipe, recipe, file: file, line: line)
            XCTAssertEqual(actualField, field, file: file, line: line)
            XCTAssertTrue(error.localizedDescription.contains("“\(recipe)”"), file: file, line: line)
            XCTAssertTrue(error.localizedDescription.contains("Nothing was exported"), file: file, line: line)
        }
    }

    func testEveryExportRejectsUnsafeStoredSettingsWithAndWithoutPhotos() throws {
        let context = try context()
        let safe = Recipe(name: "Safe first recipe")
        context.insert(safe)
        let cases: [(String, RecipeSettings)] = [
            ("highlightTone", .init(highlightTone: 1e100)),
            ("shadowTone", .init(shadowTone: -1e100)),
            ("exposureBias", .init(exposureBias: Double(Int32.max) + 1)),
            ("color", .init(color: Int.max)),
            ("sharpness", .init(sharpness: Int.min)),
            ("highISONR", .init(highISONR: Int(Int32.max) + 1)),
            ("clarity", .init(clarity: Int(Int32.min) - 1)),
            // Beside a `highISONR`, or the initialiser folds the value into that field instead.
            ("noiseReduction", .init(highISONR: 0, noiseReduction: Int.max)),
            ("monochromaticColorWC", .init(monochromaticColorWC: Int.max)),
            ("monochromaticColorMG", .init(monochromaticColorMG: Int.min)),
            ("whiteBalance.shiftRed", .init(whiteBalance: .init(mode: .auto, shiftRed: Int.max,
                                                                shiftBlue: 0, kelvin: nil))),
            ("whiteBalance.shiftBlue", .init(whiteBalance: .init(mode: .auto, shiftRed: 0,
                                                                 shiftBlue: Int.min, kelvin: nil))),
            ("whiteBalance.kelvin", .init(whiteBalance: .init(mode: .kelvin, shiftRed: 0,
                                                              shiftBlue: 0, kelvin: Int.max)))
        ]
        let image = ImportTestFixtures.jpeg()
        for (field, settings) in cases {
            let stored = Recipe(name: "Previously imported \(field)", settings: settings)
            stored.photos = [RecipePhoto(imageData: image, thumbnailData: image, sortOrder: 0)]
            context.insert(stored)
            try context.save()
            for entryPoint in EntryPoint.allCases {
                for includePhotos in [false, true] {
                    assertUnsafe({
                        _ = try self.encode(stored, using: entryPoint, includePhotos: includePhotos,
                                            preceding: safe)
                    }, recipe: "Previously imported \(field)", field: field)
                    XCTAssertEqual(stored.settings, settings, "Export must not repair or clamp stored values")
                    XCTAssertEqual(stored.sortedPhotos.first?.imageData, image)
                }
            }
        }
    }

    func testNonfiniteSettingsAreRejectedBeforeJSONEncoding() {
        for value in [Double.infinity, -Double.infinity, Double.nan] {
            let stored = Recipe(name: "Nonfinite", settings: RecipeSettings(exposureBias: value))
            for includePhotos in [false, true] {
                // Calling preflight alone proves this is not an incidental JSONEncoder failure.
                assertUnsafe({
                    try RecipeExportValidation.check([stored], includePhotos: includePhotos)
                }, recipe: "Nonfinite", field: "exposureBias")
                for entryPoint in EntryPoint.allCases {
                    assertUnsafe({
                        _ = try self.encode(stored, using: entryPoint, includePhotos: includePhotos)
                    }, recipe: "Nonfinite", field: "exposureBias")
                }
            }
            if value.isNaN { XCTAssertTrue(stored.settings.exposureBias?.isNaN == true) }
            else { XCTAssertEqual(stored.settings.exposureBias, value) }
        }
    }

    func testInt32EndpointsAndCameraRangeOutliersSurviveFullPreparation() throws {
        let context = try context()
        let boundarySettings: [RecipeSettings] = [Int32.min, Int32.max].map { endpoint in
            let integer = Int(endpoint)
            let double = Double(endpoint)
            let balance = WhiteBalance(mode: .kelvin, shiftRed: integer, shiftBlue: integer, kelvin: integer)
            return RecipeSettings(monochromaticColorWC: integer, monochromaticColorMG: integer,
                                  whiteBalance: balance, highlightTone: double, shadowTone: double,
                                  color: integer, sharpness: integer, highISONR: integer,
                                  clarity: integer, exposureBias: double, noiseReduction: integer)
        }
        let outlier = RecipeSettings(whiteBalance: .init(mode: .kelvin, shiftRed: 17, shiftBlue: -24,
                                                         kelvin: 12_345),
                                     highlightTone: 12.5, shadowTone: -12.25, color: -20,
                                     clarity: 25, exposureBias: 15.125)
        for settings in boundarySettings + [outlier] {
            let stored = Recipe(name: "Representable settings", settings: settings)
            context.insert(stored)
            try context.save()
            for entryPoint in EntryPoint.allCases {
                for includePhotos in [false, true] {
                    let bytes = try encode(stored, using: entryPoint, includePhotos: includePhotos)
                    let prepared = try RecipeImportPreparation.prepare(.data(bytes))
                    XCTAssertEqual(prepared.recipes.count, 1)
                    XCTAssertEqual(prepared.recipes.first?.recipe.settings, settings)
                    XCTAssertEqual(stored.settings, settings)
                }
            }
        }
    }

    func testUnknownLargeFiniteNumbersSurviveEveryExportAndFullPreparation() throws {
        let context = try context()
        let unknown: [String: JSONValue] = [
            "color": .number(1e100),
            "future": .object(["negative": .number(-1e200), "values": .array([.number(1e250), .null])])
        ]
        let settings = RecipeSettings(highlightTone: 12.5, color: -20)
        let stored = Recipe(name: "Future recipe", authoredForModelID: "FUTURE-1", settings: settings,
                            unsupportedFields: unknown)
        context.insert(stored)
        try context.save()
        for entryPoint in EntryPoint.allCases {
            for includePhotos in [false, true] {
                let bytes = try encode(stored, using: entryPoint, includePhotos: includePhotos)
                let prepared = try RecipeImportPreparation.prepare(.data(bytes))
                let restored = try XCTUnwrap(prepared.recipes.first?.recipe)
                XCTAssertEqual(restored.unsupportedFields, unknown)
                XCTAssertEqual(restored.authoredForModel, "FUTURE-1")
                XCTAssertEqual(restored.settings, settings)
                XCTAssertEqual(stored.unsupportedFields, unknown)
                XCTAssertEqual(stored.settings, settings)
            }
        }
    }
}
