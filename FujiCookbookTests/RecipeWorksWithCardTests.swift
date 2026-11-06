import XCTest
@testable import FujiCookbook

/// The Works With card's words: one short text and one spoken text per change, a title and glyph
/// per verdict, and the row label VoiceOver reads.
final class RecipeWorksWithCardTests: XCTestCase {

    func testEveryChangeHasShortTextAndSpokenText() {
        let cases: [(RecipeCameraFit.Change, String, String)] = [
            (.filmSimulationMissing(.classicNeg), "No Classic Neg.", "No Classic Neg."),
            (.fieldMissing(.clarity), "No Clarity", "No Clarity"),
            (.clamped(subject: "Highlight Tone", from: "+1.5", to: "+2"),
             "Highlight Tone +1.5 → +2", "Highlight Tone +1.5 clamped to +2"),
            (.magentaGreenAxisMissing, "Warm–cool axis only", "Warm–cool axis only"),
            (.grainSizeFixed, "Grain size not adjustable", "Grain size not adjustable"),
            (.whiteBalanceModeMissing(.autoWhitePriority), "No Auto (White Priority)", "No Auto (White Priority)")
        ]
        for (change, text, spoken) in cases {
            XCTAssertEqual(change.text, text)
            XCTAssertEqual(change.spokenText, spoken)
        }
    }

    func testVerdictTitlesAndSymbols() {
        XCTAssertEqual(RecipeCameraFit.Verdict.worksAsWritten.title, "Works as written")
        XCTAssertEqual(RecipeCameraFit.Verdict.worksWithChanges.title, "Works with changes")
        XCTAssertEqual(RecipeCameraFit.Verdict.notAvailable.title, "Not available")
        XCTAssertEqual(Set(RecipeCameraFit.Verdict.allCases.map(\.symbol)).count, 3, "three distinct glyphs")
    }

    func testCaveatTexts() {
        XCTAssertEqual(RecipeCameraFit.Caveat.noFilmSimulation.text,
                       "No film simulation set, so this checks the other settings only.")
        XCTAssertEqual(RecipeCameraFit.Caveat.preservedFields.text, "Some imported settings couldn't be checked.")
    }

    func testTheSpokenRowLabelReadsIdVerdictThenReasons() throws {
        let registry = CameraModelRegistry.shared
        let xT3 = try XCTUnwrap(registry.model(withID: "X-T3"))
        let missing = RecipeCameraFit(RecipeSettings(filmSimulation: .classicNeg), on: xT3)
        XCTAssertEqual(RecipeWorksWithCard.spokenLabel(for: missing), "X-T3, not available. No Classic Neg.")
        let fine = RecipeCameraFit(RecipeSettings(filmSimulation: .provia), on: xT3)
        XCTAssertEqual(RecipeWorksWithCard.spokenLabel(for: fine), "X-T3, works as written")
        let xPro1 = try XCTUnwrap(registry.model(withID: "X-Pro1"))
        let unverified = RecipeCameraFit(RecipeSettings(filmSimulation: .provia, highlightTone: 1.5), on: xPro1)
        XCTAssertEqual(RecipeWorksWithCard.spokenLabel(for: unverified),
                       "X-Pro1, works as written. Highlight Tone: range not verified")
    }
}
