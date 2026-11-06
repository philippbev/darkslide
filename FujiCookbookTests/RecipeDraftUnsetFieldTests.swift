import XCTest
@testable import FujiCookbook

/// "Not set" is a state a recipe can genuinely be in. The editor used to coerce every field to a
/// default on open and write it back on Save, so opening a four-field scan and tapping Save turned
/// it into a sixteen-field recipe of zeroes — in SwiftData and in export.
///
/// It isn't only tidiness. `FujiRawConvProfile.patch` writes *nothing* for an unset field so the RAF
/// keeps its as-shot sentinel, which that file's own comment says is the difference between a clean
/// conversion and a global color cast.
///
/// **Narrowed, deliberately.** Six fields default rather than staying absent: film simulation →
/// PROVIA, dynamic range → Auto, and grain, D-Range Priority and the two Color Chrome effects →
/// Off. A recipe is a description of a look, and for those six a field left out was inherited from
/// whatever the destination bank already held — so one recipe produced two looks on two cameras and
/// the push called both "written and verified". The other ten have no neutral value to default
/// *to*, so the principle below is still theirs: a tone of 0 or a sharpness of 0 is a choice
/// somebody makes, not an absence.
@MainActor
final class RecipeDraftUnsetFieldTests: XCTestCase {

    /// The original bug, now scoped: open a recipe, change nothing, Save. Everything without a
    /// neutral default comes back untouched; the six that have one arrive carrying it.
    func testANoOpSaveInventsNothingBeyondTheSixDefaults() {
        let original = RecipeSettings(filmSimulation: .classicNeg, dynamicRange: .dr400, clarity: 1)
        let recipe = Recipe(name: "Scanned", settings: original)

        var expected = original
        expected.grain = GrainEffect(strength: .off, size: nil)
        expected.colorChromeEffect = .off
        expected.colorChromeFXBlue = .off
        expected.dRangePriority = .off

        let assembled = RecipeDraft(from: recipe).assembleSettings()
        XCTAssertEqual(assembled, expected, "the six default; nothing else is invented")
        XCTAssertNil(assembled.highlightTone, "and a tone the recipe never set stays absent")
        XCTAssertNil(assembled.sharpness)
        XCTAssertNil(assembled.whiteBalance)
    }

    /// Field by field, so a regression names itself instead of failing one opaque equality.
    func testEveryUnsetFieldSurvivesTheRoundTrip() {
        let recipe = Recipe(name: "Scanned", settings: RecipeSettings(filmSimulation: .acros))
        let draft = RecipeDraft(from: recipe)

        XCTAssertNil(draft.wbMode, "white balance, in the draft")
        XCTAssertNil(draft.sharpness, "sharpness, in the draft")
        // The six that default, seen at the point the editor shows them.
        XCTAssertEqual(draft.grainStrength, .off, "grain, in the draft")
        XCTAssertEqual(draft.dynamicRange, .auto, "dynamic range, in the draft")
        XCTAssertEqual(draft.dRangePriority, .off, "D-range priority, in the draft")

        let s = draft.assembleSettings()
        XCTAssertEqual(s.grain?.strength, .off, "grain")
        XCTAssertEqual(s.colorChromeEffect, .off, "color chrome effect")
        XCTAssertEqual(s.colorChromeFXBlue, .off, "color chrome FX blue")
        XCTAssertEqual(s.dynamicRange, .auto, "dynamic range")
        XCTAssertEqual(s.dRangePriority, .off, "D-range priority")
        XCTAssertNil(s.whiteBalance, "white balance")
        XCTAssertNil(s.highlightTone, "highlight tone")
        XCTAssertNil(s.shadowTone, "shadow tone")
        XCTAssertNil(s.color, "color")
        XCTAssertNil(s.sharpness, "sharpness")
        XCTAssertNil(s.highISONR, "high ISO NR")
        XCTAssertNil(s.clarity, "clarity")
        XCTAssertNil(s.monochromaticColorWC, "monochromatic WC")
        XCTAssertNil(s.monochromaticColorMG, "monochromatic MG")
    }

    /// The control: a fully-specified recipe still round-trips intact, values and all. Without this
    /// the test above passes just as well on an editor that has stopped writing anything.
    func testASetFieldStillSurvivesTheRoundTrip() {
        let original = RecipeSettings(
            filmSimulation: .classicChrome,
            grain: GrainEffect(strength: .weak, size: .large),
            colorChromeEffect: .strong,
            colorChromeFXBlue: .weak,
            whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 3, shiftBlue: -2, kelvin: 6100),
            dynamicRange: .dr400,
            dRangePriority: .strong,
            highlightTone: -1.5,
            shadowTone: 2,
            color: 2,
            sharpness: -1,
            highISONR: -3,
            clarity: 4)
        let recipe = Recipe(name: "Complete", settings: original)

        XCTAssertEqual(RecipeDraft(from: recipe).assembleSettings(), original)
    }

    /// Zero is a value someone can mean. Clearing a field and setting it to 0 must not be the same
    /// edit — that conflation is what the old draft made unavoidable.
    func testAnExplicitZeroIsNotTheSameAsUnset() {
        let recipe = Recipe(name: "Scanned", settings: RecipeSettings(filmSimulation: .provia))
        var draft = RecipeDraft(from: recipe)
        XCTAssertNil(draft.assembleSettings().sharpness, "precondition")

        draft.sharpness = 0
        XCTAssertEqual(draft.assembleSettings().sharpness, 0, "a deliberate 0 is stored")

        draft.sharpness = nil
        XCTAssertNil(draft.assembleSettings().sharpness, "and clearing it goes back to absent")
    }

    /// An unset grain has no size to carry, and a grain of Off doesn't either — the size picker is
    /// hidden in both states, so neither may smuggle one into the settings.
    func testAnUnsetGrainCarriesNoSize() {
        let recipe = Recipe(name: "Scanned", settings: RecipeSettings(filmSimulation: .provia))
        var draft = RecipeDraft(from: recipe)
        draft.grainSize = .large

        XCTAssertNil(draft.assembleSettings().grain?.size,
                     "an Off grain carries no size, whatever the hidden picker remembers")

        draft.grainStrength = .off
        XCTAssertEqual(draft.assembleSettings().grain?.strength, .off, "Off is a real grain setting")
        XCTAssertNil(draft.assembleSettings().grain?.size, "but Off has no size")
    }

    /// The white balance shifts live inside `WhiteBalance`. With no mode there is no struct, so a
    /// non-zero shift left over in the draft has nowhere to go — and must not conjure one.
    func testShiftsDoNotConjureAWhiteBalance() {
        let recipe = Recipe(name: "Scanned", settings: RecipeSettings(filmSimulation: .provia))
        var draft = RecipeDraft(from: recipe)
        draft.wbShiftR = 4

        XCTAssertNil(draft.assembleSettings().whiteBalance, "no mode, no white balance")

        draft.wbMode = .daylight
        XCTAssertEqual(draft.assembleSettings().whiteBalance?.shiftRed, 4, "and the shift lands once one exists")
    }

    /// A field the chosen body doesn't have is still dropped — the model gate and the unset gate are
    /// two separate reasons a field doesn't get written, and both have to keep working.
    func testAnUnsupportedFieldIsStillDropped() throws {
        let xTransIII = try XCTUnwrap(CameraModelRegistry.shared.models.first { $0.sensorGeneration == .xTransIII },
                                      "the gate needs an X-Trans III body in the registry")
        let recipe = Recipe(name: "Modern", settings: RecipeSettings(filmSimulation: .provia, clarity: 3))
        var draft = RecipeDraft(from: recipe)
        draft.modelID = xTransIII.id

        XCTAssertFalse(xTransIII.supports(.clarity), "the gate needs a body without Clarity")
        XCTAssertNil(draft.assembleSettings().clarity, "a body without Clarity doesn't get one")
    }
}
