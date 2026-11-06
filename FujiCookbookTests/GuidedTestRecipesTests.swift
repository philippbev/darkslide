import XCTest
@testable import FujiCookbook

/// The recipes the guided write pass pushes.
///
/// These go onto testers' cameras, on twelve bodies nobody here owns, and they exist to make a
/// *failure* visible — so a recipe that arrives already clamped, already carrying a field the body
/// lacks, or already leaving a field to the slot's own bytes would produce exactly the confident,
/// uninformative report the write pass is meant to replace.
///
/// Menu facts for bodies the record leaves out (film lists, bank counts, controls) are the registry's,
/// which names the Fujifilm manual or firmware note behind each entry; the older bodies' manuals are
/// linked in `docs/supported-cameras.md#sources-for-older-bodies`.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#0xd193--0xd194-monochromatic-color`, `docs/03-encodings.md#0xd191-d-range-priority`,
/// `docs/04-custom-slots.md#the-d-range-priority-interlock`, `docs/07-cameras.md#gfx100s`,
/// `docs/07-cameras.md#x-m5`, and `docs/07-cameras.md#effect-controls-in-the-menus`.
final class GuidedTestRecipesTests: XCTestCase {

    private var models: [CameraModel] { CameraModelRegistry.shared.models }

    /// The Kelvin recipe exists to write a colour temperature; a body without Kelvin white balance
    /// — the X-M1 — gets no recipe that would warn about itself.
    func testABodyWithoutKelvinGetsNoKelvinRecipe() throws {
        let xM1 = try XCTUnwrap(CameraModelRegistry.shared.model(withID: "X-M1"))
        XCTAssertNil(GuidedTestRecipes.recipe(id: "kelvin", for: xM1))
        XCTAssertEqual(GuidedTestRecipes.canonical(for: xM1).count, 2)
        let xPro1 = try XCTUnwrap(CameraModelRegistry.shared.model(withID: "X-Pro1"))
        XCTAssertNotNil(GuidedTestRecipes.recipe(id: "kelvin", for: xPro1))
    }

    /// Grain is the one field every registry body had until the X-Trans I and II entries, so the
    /// recipes used to set it unconditionally; on a body without the control the push screen would
    /// have warned about the app's own recipe.
    func testABodyWithoutAGrainControlGetsRecipesWithoutGrain() {
        let body = CameraModel.grainlessFixture()
        let recipes = GuidedTestRecipes.canonical(for: body)
        XCTAssertEqual(recipes.count, 3, "no D-Range Priority on the fixture")
        for recipe in recipes {
            XCTAssertNil(recipe.settings.grain, recipe.name)
            XCTAssertTrue(RecipeCompatibility.analyze(recipe.settings, for: body).isEmpty, recipe.name)
            XCTAssertFalse(GuidedTestRecipes.unauthoredFields(recipe.settings, model: body).contains(.grain),
                           "\(recipe.name): a field the body lacks is not unauthored")
        }
    }

    /// Every model gets the set — colour and monochrome always, Kelvin where the body has Kelvin
    /// white balance, the priority where it has D-Range Priority — and every one of them is
    /// pushable as-is.
    ///
    /// `analyze` is what the push screen shows before a write. An issue here means a tester is
    /// warned about the app's own recipe, which reads as the app not knowing its own camera.
    func testEveryModelGetsACleanRecipeSet() {
        for model in models {
            let recipes = GuidedTestRecipes.canonical(for: model)
            let expected = 2 + (model.supports(.dRangePriority) ? 1 : 0) + (model.supports(whiteBalanceMode: .kelvin) ? 1 : 0)
            XCTAssertEqual(recipes.count, expected, "\(model.id) got \(recipes.count)")

            for recipe in recipes {
                let issues = RecipeCompatibility.analyze(recipe.settings, for: model)
                for issue in issues {
                    switch issue.kind {
                    case .fieldUnsupported, .filmSimulationUnsupported, .filmSimulationUnset,
                         .valueClamped, .magentaGreenClamped, .ignoredForMonochrome,
                         .ignoredForFixedToning, .notWritten, .magentaGreenAxisUnsupported,
                         .whiteBalanceModeUnsupported:
                        XCTFail("\(model.id) / \(recipe.name): \(issue.message)")
                    }
                }
            }
        }
    }

    /// The whole reason the app supplies these. A field left unset is written back from the slot's
    /// own bytes, verified against itself, and reported "written and verified" — a green checkmark
    /// that asserts nothing.
    func testNoCanonicalRecipeLeavesAFieldToTheSlotsOwnBytes() {
        for model in models {
            for recipe in GuidedTestRecipes.canonical(for: model) {
                let unauthored = GuidedTestRecipes.unauthoredFields(recipe.settings, model: model)
                XCTAssertTrue(unauthored.isEmpty,
                              "\(model.id) / \(recipe.name) would pass through: \(unauthored.map(\.displayName))")
            }
        }
    }

    /// The mono recipe carries a magenta–green value exactly where the body has the axis — the
    /// GFX100S read this recipe's −1 back from its own menu in its write pass — and leaves it out
    /// on the X-T3 and X-T30.
    func testTheMonoRecipeCarriesTheMGAxisExactlyWhereTheBodyHasIt() {
        for model in models where model.supports(.monochromaticColor) {
            let mono = GuidedTestRecipes.canonical(for: model).first { $0.settings.monochromaticColorWC != nil }
            XCTAssertNotNil(mono, "\(model.id) has no mono recipe")
            XCTAssertEqual(mono?.settings.monochromaticColorMG != nil, model.hasMagentaGreenAxis, model.id)
        }
        let gfx100S = CameraModelRegistry.shared.model(withID: "GFX100S")!
        XCTAssertEqual(GuidedTestRecipes.canonical(for: gfx100S)
                           .first { $0.settings.monochromaticColorWC != nil }?.settings.monochromaticColorMG, -1)
    }

    func testTheNamesSurviveTheCameraUnchanged() {
        for model in models where model.supportsSlotNaming {
            for recipe in GuidedTestRecipes.canonical(for: model) {
                XCTAssertLessThanOrEqual(recipe.name.count, CameraSlotName.maxLength)
                XCTAssertEqual(recipe.slotName(for: model), recipe.name,
                               "\(model.id) would store \(recipe.name) as something else")
            }
        }
    }

    /// Each recipe exists to exercise something specific; a body that can't do that thing still gets
    /// a valid recipe, just a smaller one.
    func testEachRecipeCarriesTheValuesItExistsToTest() {
        let xt5 = CameraModelRegistry.shared.model(withID: "X-T5")!
        let recipes = GuidedTestRecipes.canonical(for: xt5)

        let colour = recipes.first { $0.id == "colour" }!.settings
        XCTAssertEqual(colour.filmSimulation, .classicChrome)
        XCTAssertEqual(colour.grain, GrainEffect(strength: .weak, size: .small))
        XCTAssertEqual(colour.colorChromeEffect, .strong)
        XCTAssertEqual(colour.whiteBalance?.shiftRed, 2)
        XCTAssertEqual(colour.dynamicRange, .dr200)
        XCTAssertNotNil(colour.clarity)

        let mono = recipes.first { $0.id == "mono" }!.settings
        XCTAssertEqual(mono.filmSimulation?.isMonochrome, true)
        XCTAssertEqual(mono.monochromaticColorWC, 2)
        XCTAssertEqual(mono.monochromaticColorMG, -1)
        // Colour is omitted rather than set to zero: the camera refuses a Color write while a
        // monochrome simulation is active (zgrimz/fujifilm-ptp-reference
        // `docs/03-encodings.md#0xd19d--0xd19e--0xd19f--0xd1a0--0xd1a2-tones-color-sharpness-clarity`),
        // and setting it would make the push report a refusal the recipe caused rather than a
        // finding about the body.
        XCTAssertNil(mono.color)

        let kelvin = recipes.first { $0.id == "kelvin" }!.settings
        XCTAssertEqual(kelvin.whiteBalance?.mode, .kelvin)
        XCTAssertEqual(kelvin.whiteBalance?.kelvin, 5600)
        XCTAssertEqual(kelvin.dynamicRange, .auto, "the D190 sentinel, not a percentage")
        XCTAssertEqual(kelvin.grain, .off, "the value the camera accepts as 1 and reports as 6 or 7")

        let priority = recipes.first { $0.id == "priority" }!.settings
        XCTAssertEqual(priority.dRangePriority, .auto, "0x8000, the wire value with the high bit")
        XCTAssertEqual(priority.filmSimulation, .realaAce)
        // The camera drives these three under a priority and refuses writes to them; the recipe
        // leaves them out rather than carrying values the push would report as not written.
        XCTAssertNil(priority.dynamicRange)
        XCTAssertNil(priority.highlightTone)
        XCTAssertNil(priority.shadowTone)
        XCTAssertEqual(priority.whiteBalance?.mode, .shade, "a mode none of the other three use")
    }

    /// The two X-Trans IV bodies on X-Processor 5 get the recipe that writes REALA ACE, which the
    /// registry lists for both and nothing else in the write pass writes. The X-M5's owner's pass
    /// wrote it and read it back (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#x-m5`); the
    /// record has no X-T30 III observation, and processor families don't predict capability as a
    /// rule (`docs/07-cameras.md#processor-generations`).
    func testTheXTransIVBodiesOnXProcessor5GetTheRecipeThatWritesRealaAce() {
        for id in ["X-T30 III", "X-M5"] {
            let model = CameraModelRegistry.shared.model(withID: id)!
            XCTAssertEqual(GuidedTestRecipes.canonical(for: model).count, 4, id)
            let priority = GuidedTestRecipes.recipe(id: "priority", for: model)
            XCTAssertEqual(priority?.settings.filmSimulation, .realaAce, id)
            XCTAssertEqual(priority?.settings.dRangePriority, .auto, id)
            XCTAssertEqual(priority?.slotName(for: model), "CT Priority", id)
        }
    }

    /// A gen-III body has no Clarity, no Colour Chrome and no Monochromatic Color. The recipes must
    /// simply not carry them — not carry them and get warned about them.
    func testAnOlderBodyGetsASmallerRecipeRatherThanAWarning() {
        let xt20 = CameraModelRegistry.shared.model(withID: "X-T20")!
        for recipe in GuidedTestRecipes.canonical(for: xt20) {
            XCTAssertNil(recipe.settings.clarity)
            XCTAssertNil(recipe.settings.colorChromeEffect)
            XCTAssertNil(recipe.settings.monochromaticColorWC)
        }
        XCTAssertNil(GuidedTestRecipes.recipe(id: "priority", for: xt20),
                     "no D-Range Priority on a gen-III body, so no recipe that exists to write it")
        // And the tone values land on that body's whole-number steps rather than its half-steps.
        let colour = GuidedTestRecipes.recipe(id: "colour", for: xt20)!.settings
        XCTAssertEqual(colour.highlightTone, (colour.highlightTone ?? 0).rounded())
    }

    // MARK: The authoring check, on a tester's own recipe

    func testAnEmptyRecipeIsReportedAsWritingAlmostNothing() {
        let model = CameraModelRegistry.shared.model(withID: "X-T5")!
        let fields = GuidedTestRecipes.unauthoredFields(RecipeSettings(), model: model)
        XCTAssertTrue(fields.contains(.filmSimulation))
        XCTAssertTrue(fields.contains(.dynamicRange))
        XCTAssertTrue(fields.contains(.grain))
        XCTAssertTrue(fields.contains(.highISONR))
    }

    /// Explicit neutral toning is authored and written; nil still keeps the bank's own axis.
    func testAMonoRecipeWithExplicitNeutralToningIsAuthored() {
        let model = CameraModelRegistry.shared.model(withID: "X-T5")!
        var s = RecipeSettings(filmSimulation: .acrosR, grain: .off,
                               whiteBalance: .auto, dynamicRange: .dr200, highISONR: 0)
        s.monochromaticColorWC = 0
        s.monochromaticColorMG = 0
        XCTAssertFalse(GuidedTestRecipes.unauthoredFields(s, model: model).contains(.monochromaticColor))

        s.monochromaticColorWC = nil
        s.monochromaticColorMG = nil
        XCTAssertTrue(GuidedTestRecipes.unauthoredFields(s, model: model).contains(.monochromaticColor))

        s.monochromaticColorWC = 3
        XCTAssertFalse(GuidedTestRecipes.unauthoredFields(s, model: model).contains(.monochromaticColor))

        // On a colour simulation it is not written either way, and flagging it would be noise.
        var colour = s
        colour.filmSimulation = .provia
        colour.monochromaticColorWC = 0
        XCTAssertFalse(GuidedTestRecipes.unauthoredFields(colour, model: model).contains(.monochromaticColor))
    }

    /// Kelvin mode without a temperature writes the mode and leaves the camera's own temperature —
    /// which is the value the picture is actually made at.
    func testKelvinWithNoTemperatureIsAGap() {
        let model = CameraModelRegistry.shared.model(withID: "X-T5")!
        let s = RecipeSettings(filmSimulation: .provia, grain: .off,
                               whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 0, shiftBlue: 0,
                                                          kelvin: nil),
                               dynamicRange: .dr200, highISONR: 0)
        XCTAssertTrue(GuidedTestRecipes.unauthoredFields(s, model: model).contains(.whiteBalance))
    }

    /// Under a priority the codec skips Dynamic Range rather than passing the slot's own through —
    /// the camera drives it — so a priority recipe with no dynamic range is not leaving a gap.
    func testDynamicRangeIsNotAGapUnderAPriority() {
        let model = CameraModelRegistry.shared.model(withID: "X-T5")!
        var s = RecipeSettings(filmSimulation: .realaAce, grain: .off, whiteBalance: .auto,
                               dynamicRange: nil, highISONR: 0)
        s.dRangePriority = .strong
        XCTAssertFalse(GuidedTestRecipes.unauthoredFields(s, model: model).contains(.dynamicRange))
        s.dRangePriority = .off
        XCTAssertTrue(GuidedTestRecipes.unauthoredFields(s, model: model).contains(.dynamicRange))
    }

    /// A field the encoder writes a *default* into is a weaker test, not a passthrough — it is still
    /// a real write with a real read-back, so it can still fail. Listing it would cry wolf.
    func testADefaultedFieldIsNotReportedAsAGap() {
        let model = CameraModelRegistry.shared.model(withID: "X-T5")!
        let s = RecipeSettings(filmSimulation: .provia, grain: .off, whiteBalance: .auto,
                               dynamicRange: .dr200, highISONR: 0)
        let fields = GuidedTestRecipes.unauthoredFields(s, model: model)
        XCTAssertFalse(fields.contains(.clarity))
        XCTAssertFalse(fields.contains(.sharpness))
        XCTAssertFalse(fields.contains(.colorChromeEffect))
        XCTAssertTrue(fields.isEmpty, "got: \(fields.map(\.displayName))")
    }
}
