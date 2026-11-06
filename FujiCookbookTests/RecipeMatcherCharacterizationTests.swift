import XCTest
import SwiftData
@testable import FujiCookbook

/// What `RecipeMatcher` does today, pinned exactly.
///
/// Written as a safety net rather than as a specification. `RecipeMatcher` is the most load-bearing
/// comparison code in the app — it drives the Kitchen's "which of my recipes does this photo look
/// like" — and until this file existed it had **no test coverage at all**: not the row list, not the
/// weights, not the film-simulation gate, not the tier ladder. The applicability consolidation
/// (`RecipeApplicability`) touches its neighbours, so the row model needed pinning before anything
/// moved near it.
///
/// Every expectation here is a record of behaviour, not a judgement of it. Three of them pin things
/// that are arguably wrong and are deliberately left alone: the soft-Off equivalence, the collapsed
/// Monochromatic Color and Grain rows, and the fact that nothing in this file consults
/// `isMonochrome`. A change to any of those should start by changing the expectation here, on
/// purpose.
final class RecipeMatcherCharacterizationTests: XCTestCase {

    // MARK: - The row list

    /// Rows are hand-listed in `compare`, not driven by `RecipeField.allCases`, so the list can
    /// drift from the field enum without anything noticing. This is what stops that.
    func testCompareReturnsTheSameRowsInTheSameOrderForEveryInput() {
        let expected = ["filmSimulation", "highlightTone", "shadowTone", "dynamicRange",
                        "whiteBalance.mode", "whiteBalance.shift", "color", "monochromaticColor",
                        "grain", "clarity", "colorChromeEffect", "colorChromeFXBlue",
                        "sharpness", "highISONR", "dRangePriority", "exposureBias", "noiseReduction"]

        XCTAssertEqual(RecipeMatcher.compare(photo: RecipeSettings(), recipe: RecipeSettings()).map(\.id),
                       expected, "two empty settings still produce the full row list")
        XCTAssertEqual(RecipeMatcher.compare(photo: .neutral, recipe: .neutral).map(\.id),
                       expected, "the row list does not depend on which fields are set")
        XCTAssertEqual(RecipeMatcher.compare(photo: monoPhoto, recipe: monoRecipe).map(\.id),
                       expected, "a monochrome pair produces the same rows as a colour one")
    }

    /// Film simulation scores 0 because the gate has already decided it — a candidate that reached
    /// scoring either agrees on it or has none. Exposure bias is what the frame used rather than
    /// what the recipe prescribes, and the decoder can never produce Noise Reduction at all.
    func testEveryRowsLabelAndWeightAreWhatTheyHaveAlwaysBeen() {
        let expected: [String: (label: String, weight: Double)] = [
            "filmSimulation": ("Film Simulation", 0),
            "highlightTone": ("Highlight Tone", 3),
            "shadowTone": ("Shadow Tone", 3),
            "dynamicRange": ("Dynamic Range", 3),
            "whiteBalance.mode": ("White Balance", 3),
            "whiteBalance.shift": ("WB Shift", 2),
            "color": ("Color", 2),
            "monochromaticColor": ("Monochromatic Color", 2),
            "grain": ("Grain Effect", 2),
            "clarity": ("Clarity", 2),
            "colorChromeEffect": ("Color Chrome Effect", 1),
            "colorChromeFXBlue": ("Color Chrome FX Blue", 1),
            "sharpness": ("Sharpness", 1),
            "highISONR": ("High ISO NR", 1),
            "dRangePriority": ("D-Range Priority", 1),
            "exposureBias": ("Exposure Bias", 0),
            "noiseReduction": ("Noise Reduction", 0)
        ]
        for row in RecipeMatcher.compare(photo: .neutral, recipe: .neutral) {
            let want = expected[row.id]
            XCTAssertEqual(row.label, want?.label, "label for \(row.id)")
            XCTAssertEqual(row.weight, want?.weight, "weight for \(row.id)")
        }
    }

    // MARK: - Verdicts

    func testTheFourAbsenceCombinationsEachGetTheirOwnVerdict() {
        func clarityRow(_ photo: Int?, _ recipe: Int?) -> FieldComparison.Verdict {
            RecipeMatcher.compare(photo: RecipeSettings(clarity: photo),
                                  recipe: RecipeSettings(clarity: recipe))
                .first { $0.id == "clarity" }!.verdict
        }
        XCTAssertEqual(clarityRow(2, 2), .same)
        XCTAssertEqual(clarityRow(2, 3), .different)
        XCTAssertEqual(clarityRow(2, nil), .missingInRecipe, "the photo has a value the recipe doesn't")
        XCTAssertEqual(clarityRow(nil, 2), .missingInPhoto, "the decoder's limitation, never scored against the recipe")
        XCTAssertEqual(clarityRow(nil, nil), .notCompared, "two unknowns are not a match")
    }

    /// Tones compare within `toneEpsilon`, which is finer than the finest real step.
    func testTonesCompareWithinAnEpsilonRatherThanExactly() {
        func toneVerdict(_ photo: Double, _ recipe: Double) -> FieldComparison.Verdict {
            RecipeMatcher.compare(photo: RecipeSettings(highlightTone: photo),
                                  recipe: RecipeSettings(highlightTone: recipe))
                .first { $0.id == "highlightTone" }!.verdict
        }
        XCTAssertEqual(toneVerdict(2.0, 2.0), .same)
        XCTAssertEqual(toneVerdict(2.0, 2.01), .same, "inside the epsilon")
        XCTAssertEqual(toneVerdict(2.0, 2.5), .different, "half a step apart is a real difference")
    }

    // MARK: - The soft-Off equivalence

    /// A recipe that leaves a chrome effect nil agrees with a photo whose value is Off. Correct for
    /// photo matching and wrong for recipe comparison — which is exactly why it stays here and did
    /// **not** move into `RecipeApplicability`.
    func testARecipeWithNoChromeEffectAgreesWithAPhotosOff() {
        let rows = RecipeMatcher.compare(photo: RecipeSettings(colorChromeEffect: .off, colorChromeFXBlue: .off,
                                                              dRangePriority: .off),
                                         recipe: RecipeSettings())
        for id in ["colorChromeEffect", "colorChromeFXBlue", "dRangePriority"] {
            let row = rows.first { $0.id == id }!
            XCTAssertEqual(row.verdict, .same, "\(id) soft-Off")
            XCTAssertNil(row.recipeValue, "\(id) still renders the recipe side as absent")
            XCTAssertEqual(row.photoValue, "Off", "\(id) still renders the photo's real value")
        }
    }

    /// The equivalence is one-directional: an Off *recipe* against a nil photo is not a match.
    func testTheSoftOffEquivalenceDoesNotRunTheOtherWay() {
        let row = RecipeMatcher.compare(photo: RecipeSettings(), recipe: RecipeSettings(colorChromeEffect: .off))
            .first { $0.id == "colorChromeEffect" }!
        XCTAssertEqual(row.verdict, .missingInPhoto)
    }

    /// Only the three "off"-bearing enums get it — a nil Dynamic Range does not agree with anything.
    func testSoftOffDoesNotApplyToDynamicRange() {
        let row = RecipeMatcher.compare(photo: RecipeSettings(dynamicRange: .auto), recipe: RecipeSettings())
            .first { $0.id == "dynamicRange" }!
        XCTAssertEqual(row.verdict, .missingInRecipe)
    }

    // MARK: - Grain

    func testTwoOffGrainsAgreeWhateverSizeEitherRemembers() {
        let row = grainRow(GrainEffect(strength: .off, size: .large), GrainEffect(strength: .off, size: .small))
        XCTAssertEqual(row.verdict, .same, "an Off grain has no size to disagree about")
        XCTAssertEqual(row.photoValue, "Off")
        XCTAssertEqual(row.recipeValue, "Off")
    }

    /// A body with only a strength control yields a nil size. Forcing a mismatch on a control that
    /// body doesn't have would be a model artefact, not a real difference.
    func testWhenEitherSideHasNoGrainSizeOnlyTheStrengthIsCompared() {
        XCTAssertEqual(grainRow(GrainEffect(strength: .weak, size: nil),
                                GrainEffect(strength: .weak, size: .large)).verdict, .same)
        XCTAssertEqual(grainRow(GrainEffect(strength: .weak, size: .small),
                                GrainEffect(strength: .strong, size: nil)).verdict, .different)
    }

    func testWithBothSizesPresentTheSizeCounts() {
        XCTAssertEqual(grainRow(GrainEffect(strength: .weak, size: .small),
                                GrainEffect(strength: .weak, size: .large)).verdict, .different)
        XCTAssertEqual(grainRow(GrainEffect(strength: .weak, size: .large),
                                GrainEffect(strength: .weak, size: .large)).verdict, .same)
    }

    func testAGrainRowRendersStrengthAndSizeTheWayTheTableDoes() {
        XCTAssertEqual(grainRow(GrainEffect(strength: .weak, size: .large), nil).photoValue, "Weak, Large")
        XCTAssertEqual(grainRow(GrainEffect(strength: .strong, size: nil), nil).photoValue, "Strong")
        XCTAssertEqual(grainRow(GrainEffect(strength: .off, size: .small), nil).photoValue, "Off")
    }

    /// Grain gets the soft-Off equivalence too: a recipe that leaves grain nil agrees with a photo
    /// whose grain is Off.
    func testARecipeWithNoGrainAgreesWithAPhotosOff() {
        let row = grainRow(GrainEffect(strength: .off, size: nil), nil)
        XCTAssertEqual(row.verdict, .same)
        XCTAssertNil(row.recipeValue, "still renders the recipe side as absent")
        XCTAssertEqual(row.photoValue, "Off", "still renders the photo's real value")
    }

    /// Apart from a photo's Off against a nil recipe, one side absent is never agreement.
    func testAGrainPresentOnOneSideOnlyIsNotAMatch() {
        XCTAssertEqual(grainRow(GrainEffect(strength: .weak, size: .small), nil).verdict, .missingInRecipe)
        XCTAssertEqual(grainRow(nil, GrainEffect(strength: .off, size: nil)).verdict, .missingInPhoto,
                       "the equivalence is one-directional")
        XCTAssertEqual(grainRow(nil, nil).verdict, .notCompared)
    }

    // MARK: - Monochromatic Color

    /// The row is one collapsed row over both axes, and **nothing here consults `isMonochrome`** —
    /// a Monochromatic Color value on a colour simulation still scores. Both are deliberate for
    /// now; the compare spec splits the row in a later phase.
    func testMonochromaticColorIsOneRowOverBothAxesAndIgnoresTheFilmSimulation() {
        let onAColourSim = RecipeMatcher.compare(
            photo: RecipeSettings(filmSimulation: .provia, monochromaticColorWC: 3, monochromaticColorMG: 1),
            recipe: RecipeSettings(filmSimulation: .provia, monochromaticColorWC: 3, monochromaticColorMG: 1))
            .first { $0.id == "monochromaticColor" }!
        XCTAssertEqual(onAColourSim.verdict, .same, "a colour simulation does not suppress the row")
        XCTAssertEqual(onAColourSim.photoValue, "WC +3, MG +1")
    }

    /// A missing axis reads as 0 on both sides of the comparison, so WC 3 with no MG matches
    /// WC 3 with MG 0 — but only when each side has *something* set.
    func testAnAbsentAxisComparesAsZero() {
        XCTAssertEqual(monoRow(wcA: 3, mgA: nil, wcB: 3, mgB: 0).verdict, .same)
        XCTAssertEqual(monoRow(wcA: 3, mgA: nil, wcB: 3, mgB: 2).verdict, .different)
        XCTAssertEqual(monoRow(wcA: nil, mgA: nil, wcB: 3, mgB: nil).verdict, .missingInPhoto)
        XCTAssertEqual(monoRow(wcA: nil, mgA: nil, wcB: nil, mgB: nil).verdict, .notCompared)
    }

    func testMonochromaticColorRendersOnlyTheAxesThatAreSet() {
        XCTAssertEqual(monoRow(wcA: -2, mgA: nil, wcB: nil, mgB: nil).photoValue, "WC −2")
        XCTAssertEqual(monoRow(wcA: nil, mgA: 4, wcB: nil, mgB: nil).photoValue, "MG +4")
    }

    // MARK: - White Balance

    func testTheModeRowCarriesKelvinAndTheShiftRowCarriesTheShift() {
        let rows = RecipeMatcher.compare(
            photo: RecipeSettings(whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 1, shiftBlue: -2, kelvin: 5500)),
            recipe: RecipeSettings(whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 1, shiftBlue: -2, kelvin: 5500)))
        let mode = rows.first { $0.id == "whiteBalance.mode" }!
        let shift = rows.first { $0.id == "whiteBalance.shift" }!
        XCTAssertEqual(mode.photoValue, "5500K", "a Kelvin mode renders the temperature in place of the mode name")
        XCTAssertEqual(mode.verdict, .same)
        XCTAssertEqual(shift.photoValue, "R+1 B−2")
        XCTAssertEqual(shift.verdict, .same)
    }

    func testTwoKelvinModesAtDifferentTemperaturesDisagreeOnTheModeRowAlone() {
        let rows = RecipeMatcher.compare(
            photo: RecipeSettings(whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 0, shiftBlue: 0, kelvin: 5500)),
            recipe: RecipeSettings(whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 0, shiftBlue: 0, kelvin: 7000)))
        XCTAssertEqual(rows.first { $0.id == "whiteBalance.mode" }!.verdict, .different)
        XCTAssertEqual(rows.first { $0.id == "whiteBalance.shift" }!.verdict, .same, "the shift is untouched by the temperature")
    }

    /// Kelvin only counts when the mode uses it — two Daylight recipes with different stored
    /// temperatures still agree.
    func testAStoredTemperatureIsIgnoredOutsideColorTemperatureMode() {
        let rows = RecipeMatcher.compare(
            photo: RecipeSettings(whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 0, shiftBlue: 0, kelvin: 5500)),
            recipe: RecipeSettings(whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 0, shiftBlue: 0, kelvin: 7000)))
        XCTAssertEqual(rows.first { $0.id == "whiteBalance.mode" }!.verdict, .same)
        XCTAssertEqual(rows.first { $0.id == "whiteBalance.mode" }!.photoValue,
                       WhiteBalanceMode.daylight.displayName)
    }

    // MARK: - Matching the library

    @MainActor
    func testAnIdenticalRecipeMatchesExactlyAndADifferentSimulationIsGatedOut() throws {
        let context = try makeContext()
        let photo = fullSettings
        let twin = Recipe(name: "Twin", settings: fullSettings)
        let otherSim = Recipe(name: "Other", settings: {
            var s = fullSettings; s.filmSimulation = .velvia; return s
        }())
        context.insert(twin); context.insert(otherSim)

        let result = RecipeMatcher.match(photo: photo, against: [twin, otherSim])
        XCTAssertEqual(result.tier, .exact)
        XCTAssertEqual(result.best?.recipe.name, "Twin")
        XCTAssertEqual(result.best?.score, 1.0)
        XCTAssertTrue(result.best!.differences.isEmpty)
        XCTAssertEqual(result.simulationNearMisses.map(\.recipe.name), ["Other"],
                       "the gated-out recipe is reported rather than silently dropped")
    }

    /// A recipe with no film simulation stays eligible but can never read as exact or close.
    @MainActor
    func testARecipeWithNoFilmSimulationIsCappedBelowClose() throws {
        let context = try makeContext()
        var bare = fullSettings
        bare.filmSimulation = nil
        let recipe = Recipe(name: "Unnamed look", settings: bare)
        context.insert(recipe)

        let result = RecipeMatcher.match(photo: fullSettings, against: [recipe])
        XCTAssertEqual(result.tier, .closest, "eligible, but capped")
        XCTAssertLessThan(result.best!.score, 0.85)
    }

    /// Below the compared-weight floor a recipe can only ever reach `.closest`, so a recipe that
    /// sets one weight-1 field cannot be announced as a perfect match.
    @MainActor
    func testARecipeThatBarelyComparesCannotOutrankTheFloor() throws {
        let context = try makeContext()
        let thin = Recipe(name: "Thin", settings: RecipeSettings(filmSimulation: .classicChrome, sharpness: 1))
        context.insert(thin)

        let result = RecipeMatcher.match(photo: RecipeSettings(filmSimulation: .classicChrome, sharpness: 1),
                                         against: [thin])
        XCTAssertEqual(result.best?.score, 1.0, "it does agree on everything compared")
        XCTAssertEqual(result.tier, .closest, "but too little was compared to call it exact")
    }

    @MainActor
    func testAnEmptyLibraryMatchesNothing() {
        let result = RecipeMatcher.match(photo: fullSettings, against: [])
        XCTAssertEqual(result.tier, .none)
        XCTAssertNil(result.best)
    }

    // MARK: - Fixtures

    private var fullSettings: RecipeSettings {
        RecipeSettings(filmSimulation: .classicChrome,
                       grain: GrainEffect(strength: .weak, size: .small),
                       colorChromeEffect: .strong, colorChromeFXBlue: .weak,
                       whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 1, shiftBlue: -2, kelvin: nil),
                       dynamicRange: .dr400, dRangePriority: .off,
                       highlightTone: 1.5, shadowTone: -1, color: 2, sharpness: 1,
                       highISONR: -2, clarity: 3)
    }

    private var monoPhoto: RecipeSettings {
        RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: -1)
    }

    private var monoRecipe: RecipeSettings {
        RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: -1)
    }

    private func grainRow(_ photo: GrainEffect?, _ recipe: GrainEffect?) -> FieldComparison {
        RecipeMatcher.compare(photo: RecipeSettings(grain: photo), recipe: RecipeSettings(grain: recipe))
            .first { $0.id == "grain" }!
    }

    private func monoRow(wcA: Int?, mgA: Int?, wcB: Int?, mgB: Int?) -> FieldComparison {
        RecipeMatcher.compare(photo: RecipeSettings(monochromaticColorWC: wcA, monochromaticColorMG: mgA),
                              recipe: RecipeSettings(monochromaticColorWC: wcB, monochromaticColorMG: mgB))
            .first { $0.id == "monochromaticColor" }!
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelStore.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        return ModelContext(container)
    }
}
