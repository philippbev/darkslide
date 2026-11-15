import XCTest
@testable import FujiCookbook

/// A scanned recipe is nearly always someone else's — that is what makes the scanner worth having —
/// and `credit` is first-class everywhere else in the app: the editor writes it, `RecipePortability`
/// carries it through sharing. So the scanner reads it too.
///
/// The hard part isn't finding a name, it's knowing whether the name is the *author's*. A handle
/// sitting at the top of an Instagram screenshot belongs to whoever posted it, and a repost looks
/// exactly like an original. Crediting the wrong person is a worse failure than leaving a recipe
/// unattributed, so a name only becomes a credit when the model can say what made it one — these
/// pin that gate, in both directions.
final class AIRecipeCreditTests: XCTestCase {

    private func scanned(_ json: String) throws -> PortableRecipe {
        try JSONDecoder().decode(AIRecipePayload.self, from: Data(json.utf8))
            .toPortable(fallbackName: "Scanned Recipe")
    }

    /// The unambiguous case: the recipe names its own author.
    func testAStatedBylineBecomesTheCredit() throws {
        let recipe = try scanned("""
        {"name": "Harbour Light", "credit": "Northlight", "creditBasis": "STATED_BY_LINE"}
        """)

        XCTAssertEqual(recipe.credit, "Northlight")
    }

    /// The case that needs the caption: a handle is the author here only because the poster said so
    /// ("I made a Fujifilm recipe I can't stop using").
    func testAPosterWhoClaimsAuthorshipBecomesTheCredit() throws {
        let recipe = try scanned("""
        {"name": "PORT MORNING", "filmSimulation": "CLASSIC_CHROME",
         "credit": "harbour.walks", "creditBasis": "POSTER_CLAIMED_AUTHORSHIP"}
        """)

        XCTAssertEqual(recipe.credit, "harbour.walks")
        XCTAssertEqual(recipe.settings.filmSimulation, .classicChrome)
    }

    /// The whole point of the gate. A visible handle with nothing claiming authorship is a repost as
    /// far as we can tell, and a repost must not be credited.
    func testABareHandleWithNoBasisIsNotCredited() throws {
        let recipe = try scanned("""
        {"name": "PORT MORNING", "credit": "harbour.walks"}
        """)

        XCTAssertNil(recipe.credit, "a name with no evidence behind it is not a credit")
        XCTAssertEqual(recipe.name, "PORT MORNING", "the rest of the recipe still imports")
    }

    /// A basis we don't recognize is a basis we can't check, so it fails closed rather than open.
    func testAnUnrecognizedBasisIsNotCredited() throws {
        let recipe = try scanned("""
        {"credit": "somebody", "creditBasis": "SEEMED_LIKELY"}
        """)

        XCTAssertNil(recipe.credit)
    }

    /// A basis with nothing to attribute leaves the field genuinely unset rather than blank.
    func testABasisWithoutANameLeavesTheCreditUnset() throws {
        let blank = try scanned("""
        {"credit": "   ", "creditBasis": "STATED_BY_LINE"}
        """)
        XCTAssertNil(blank.credit, "whitespace is not a credit")

        let missing = try scanned("""
        {"creditBasis": "STATED_BY_LINE"}
        """)
        XCTAssertNil(missing.credit)
    }

    /// The schema is what tells the model the rule, so it has to offer both bases and no escape
    /// hatch — an "unknown" value would let a repost through by naming its own excuse.
    func testTheSchemaOffersBothBasesAndNoUnknown() {
        let properties = AIRecipeSchema.recipeProperties()

        XCTAssertEqual((properties["credit"] as? [String: Any])?["type"] as? String, "string")

        let basis = properties["creditBasis"] as? [String: Any]
        let values = basis?["enum"] as? [String]
        XCTAssertEqual(values.map(Set.init),
                       Set(["STATED_BY_LINE", "POSTER_CLAIMED_AUTHORSHIP"]),
                       "exactly the two kinds of evidence, and nothing else")
        XCTAssertEqual(Set(AIRecipeSchema.CreditBasis.allCases.map(\.rawValue)),
                       values.map(Set.init), "the schema and the gate read the same list")
    }
}
