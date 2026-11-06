import XCTest
@testable import FujiCookbook

/// "Not set" is a state a recipe can genuinely be in. These pin the two places that could
/// erase it without asking.
@MainActor
final class FilmSimulationStateTests: XCTestCase {

    /// Deliberate: `RecipeDraft` coerces a nil film simulation to PROVIA, and the push writes PROVIA
    /// for one too — a recipe describes a look, and a recipe without a film simulation would
    /// otherwise take on whatever the destination bank is wearing — so the editor showing PROVIA
    /// and the push writing PROVIA are the same answer, and the coercion is what keeps them from
    /// disagreeing.
    ///
    /// `RecipeSettings` still models absence, because an import or an AI scan can arrive without
    /// one; `RecipeCompatibility` is what tells the user which way it resolved.
    func testTheEditorShowsTheDefaultForAMissingFilmSimulation() {
        let recipe = Recipe(name: "Scanned", settings: RecipeSettings(dynamicRange: .dr400, clarity: 1))
        XCTAssertNil(recipe.settings.filmSimulation, "precondition: the stored recipe has none")

        let draft = RecipeDraft(from: recipe)

        XCTAssertEqual(draft.filmSim, .provia, "the editor shows what the push will write")
        XCTAssertEqual(draft.assembleSettings().filmSimulation, .provia)
        XCTAssertFalse(draft.isMono)
    }

    /// The control: a set sim survives the same trip untouched.
    func testTheEditorKeepsASetFilmSimulation() {
        let recipe = Recipe(name: "Kept", settings: RecipeSettings(filmSimulation: .realaAce))
        let draft = RecipeDraft(from: recipe)
        XCTAssertEqual(draft.assembleSettings().filmSimulation, .realaAce)
    }

    /// `RecipeImporter.apply(.overwrite)` replaces `settings` wholesale — the only import path that
    /// nulls an *existing* recipe. The review screen now says so, for exactly that case.
    func testOverwriteWarnsWhenItWouldRemoveAFilmSimulation() {
        let incoming = RecipeSettings(dynamicRange: .dr200)                  // no sim
        let existing = RecipeSettings(filmSimulation: .classicNeg)

        let warning = ImportReviewView.overwriteWarning(incoming: incoming, existing: existing, resolution: .overwrite)
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains("Classic Neg") ?? false, "names what would be lost: \(warning ?? "nil")")

        // And stays quiet in every case where nothing is lost.
        XCTAssertNil(ImportReviewView.overwriteWarning(incoming: incoming, existing: existing, resolution: .keepBoth))
        XCTAssertNil(ImportReviewView.overwriteWarning(incoming: incoming, existing: existing, resolution: .skip))
        XCTAssertNil(ImportReviewView.overwriteWarning(incoming: RecipeSettings(filmSimulation: .provia),
                                                       existing: existing, resolution: .overwrite))
        XCTAssertNil(ImportReviewView.overwriteWarning(incoming: incoming, existing: incoming, resolution: .overwrite))
    }
}
