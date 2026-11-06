import XCTest
import UniformTypeIdentifiers
@testable import FujiCookbook

/// Guards the one piece of app configuration that fails by *trapping* rather than by returning an
/// error: `UTType(exportedAs:)` requires its identifier to be declared in the host app's Info.plist,
/// and crashes the process if it isn't. Nothing else in the suite touches `UTType.fujiRecipe`, so
/// without this a rename that updated only one of the two places would ship and crash on the first
/// export rather than failing here.
final class RecipeUTITests: XCTestCase {

    func testExportedRecipeTypeResolves() {
        // Merely evaluating this would trap if Info.plist and UIKitBridges disagreed.
        let type = UTType.fujiRecipe
        XCTAssertEqual(type.identifier, "xyz.grovehouse.fujicookbook.recipe")
        XCTAssertTrue(type.conforms(to: .json), "a recipe file is JSON, and the picker relies on it")
    }

    /// The extension mapping is what keeps files exported before the rename openable — Launch
    /// Services matches `.fujirecipe` on this tag, not on the identifier.
    func testRecipeTypeOwnsTheFujirecipeExtension() {
        XCTAssertEqual(UTType.fujiRecipe.preferredFilenameExtension, "fujirecipe")
        XCTAssertEqual(UTType(filenameExtension: "fujirecipe", conformingTo: .json), UTType.fujiRecipe)
    }
}
