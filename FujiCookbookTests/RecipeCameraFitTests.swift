import XCTest
@testable import FujiCookbook

/// The Works With verdicts: what a body does with a recipe's settings, read off the push's
/// analysis and the applicability rules. These pin the mapping, the neutral and
/// irrelevant-setting rules the push does not need, and the shape of the all-bodies list.
final class RecipeCameraFitTests: XCTestCase {

    private let registry = CameraModelRegistry.shared

    private func body(_ id: String) throws -> CameraModel {
        try XCTUnwrap(registry.model(withID: id), "\(id) is not in the registry")
    }

    private func fit(_ settings: RecipeSettings, on id: String) throws -> RecipeCameraFit {
        RecipeCameraFit(settings, on: try body(id))
    }

    /// A late gen-IV recipe: Classic Neg., sized grain, Color Chrome, a half-step tone, Clarity.
    private let lateGenIV = RecipeSettings(filmSimulation: .classicNeg,
                                           grain: GrainEffect(strength: .weak, size: .large),
                                           colorChromeEffect: .strong, highlightTone: 1.5, clarity: 2)

    // MARK: - Verdicts

    func testAFilmSimulationTheBodyLacksIsNotAvailable() throws {
        let fit = try fit(lateGenIV, on: "X-T3")
        XCTAssertEqual(fit.verdict, .notAvailable)
        XCTAssertTrue(fit.changes.contains(.filmSimulationMissing(.classicNeg)))
    }

    func testABodyWithEveryControlWorksAsWritten() throws {
        for id in ["X-T50", "X-T4"] {
            let fit = try fit(lateGenIV, on: id)
            XCTAssertEqual(fit.verdict, .worksAsWritten, id)
            XCTAssertTrue(fit.changes.isEmpty, id)
        }
    }

    /// GFX 50S: whole-step tones, no Clarity, grain strength only — in `analyze`'s field order,
    /// then the grain-size rule.
    func testAProcessorProBodyWorksWithChangesAndSaysWhich() throws {
        var s = lateGenIV
        s.filmSimulation = .classicChrome
        let fit = try fit(s, on: "GFX50S")
        XCTAssertEqual(fit.verdict, .worksWithChanges)
        XCTAssertEqual(fit.changes, [.clamped(subject: "Highlight Tone", from: "+1.5", to: "+2"),
                                     .fieldMissing(.clarity), .grainSizeFixed])
    }

    /// The X-T3 is X-Processor 4 and still whole-step, Clarity-less and strength-only.
    func testTheXT3ReportsWholeStepsAndFixedGrainSize() throws {
        var s = lateGenIV
        s.filmSimulation = .classicChrome
        let fit = try fit(s, on: "X-T3")
        XCTAssertEqual(fit.verdict, .worksWithChanges)
        XCTAssertEqual(fit.changes, [.clamped(subject: "Highlight Tone", from: "+1.5", to: "+2"),
                                     .fieldMissing(.clarity), .grainSizeFixed])
    }

    /// Whole-step tones on the X100V and X-Pro3: the only change a late gen-IV recipe needs there.
    func testTheX100VAndXPro3ClampAHalfStepTone() throws {
        for id in ["X100V", "X-Pro3"] {
            let fit = try fit(lateGenIV, on: id)
            XCTAssertEqual(fit.verdict, .worksWithChanges, id)
            XCTAssertEqual(fit.changes, [.clamped(subject: "Highlight Tone", from: "+1.5", to: "+2")], id)
        }
    }

    // MARK: - Grain

    /// Only a grain that is on *and* sized asks a strength-only body for something it lacks.
    func testOnlyASizedGrainIsAChangeOnAStrengthOnlyBody() throws {
        let cases: [(GrainEffect?, Bool)] = [
            (nil, false),
            (GrainEffect(strength: .off, size: .large), false),
            (GrainEffect(strength: .weak, size: nil), false),
            (GrainEffect(strength: .weak, size: .small), true),
            (GrainEffect(strength: .strong, size: .large), true)
        ]
        for (grain, expectsChange) in cases {
            let fit = try fit(RecipeSettings(filmSimulation: .provia, grain: grain), on: "X-T20")
            XCTAssertEqual(fit.changes.contains(.grainSizeFixed), expectsChange, "\(String(describing: grain))")
        }
    }

    /// A body with no grain control at all drops the grain; it has no size to hold fixed.
    func testABodyWithoutGrainReportsNoGrainNotAFixedSize() {
        let s = RecipeSettings(filmSimulation: .provia, grain: GrainEffect(strength: .weak, size: .large))
        let fit = RecipeCameraFit(s, on: CameraModel.grainlessFixture())
        XCTAssertEqual(fit.changes, [.fieldMissing(.grain)])
    }

    func testAStrengthOnlyRecipeWorksAsWrittenOnItsOwnBody() throws {
        let s = RecipeSettings(filmSimulation: .acros, grain: GrainEffect(strength: .strong, size: nil))
        XCTAssertEqual(try fit(s, on: "X-T20").verdict, .worksAsWritten)
        XCTAssertEqual(try fit(s, on: "X-T50").verdict, .worksAsWritten, "a sized body takes a strength-only grain too")
    }

    // MARK: - Neutral and irrelevant settings

    /// A 0 is a write to the push, but it changes nothing: a body without the control is not a
    /// change for the recipe.
    func testNeutralValuesOnABodyWithoutTheControlAreNotChanges() throws {
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 0, monochromaticColorMG: 0,
                               colorChromeFXBlue: .off, dRangePriority: .off, clarity: 0)
        let fit = try fit(s, on: "X-T20")
        XCTAssertEqual(fit.verdict, .worksAsWritten, "\(fit.changes)")
    }

    /// Sepia's toning does nothing on any body, so a body that lacks the control and one that
    /// ignores the value must agree.
    func testSepiaToningReadsTheSameWithAndWithoutTheControl() throws {
        let s = RecipeSettings(filmSimulation: .sepia, monochromaticColorWC: 3)
        XCTAssertEqual(try fit(s, on: "X-T20").verdict, .worksAsWritten)
        XCTAssertEqual(try fit(s, on: "X-T50").verdict, .worksAsWritten)
    }

    func testColorOnAMonochromeRecipeIsNotAChangeAnywhere() throws {
        let s = RecipeSettings(filmSimulation: .acros, color: 3)
        for id in ["X-T20", "X-T3", "X-T50"] {
            XCTAssertEqual(try fit(s, on: id).verdict, .worksAsWritten, id)
        }
    }

    /// Under D-Range Priority the body drives the tones, so a tone that would clamp changes
    /// nothing — on a body that has the priority. One that lacks it writes the tone as chosen, and
    /// loses the priority.
    func testTonesUnderPriorityClampOnlyWhereThePriorityIsDropped() throws {
        let s = RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400, dRangePriority: .strong,
                               highlightTone: 1.5)
        XCTAssertEqual(try fit(s, on: "X-T3").verdict, .worksAsWritten, "the X-T3 has the priority")
        let pro = try fit(s, on: "X-T20")
        XCTAssertEqual(pro.verdict, .worksWithChanges)
        XCTAssertEqual(pro.changes, [.fieldMissing(.dRangePriority),
                                     .clamped(subject: "Highlight Tone", from: "+1.5", to: "+2")])
    }

    /// Exposure compensation and the legacy noise-reduction toggle are in no body's field set, so
    /// they cannot make one body differ from another.
    func testShootingSuggestionsNeverChangeTheVerdict() throws {
        let s = RecipeSettings(filmSimulation: .provia, exposureBias: 0.33, noiseReduction: 1)
        for model in registry.models {
            XCTAssertEqual(RecipeCameraFit(s, on: model).verdict, .worksAsWritten, model.id)
        }
    }

    func testAWarmCoolOnlyBodyIsWithChangesForAMagentaGreenValue() throws {
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorMG: 3)
        let fit = try fit(s, on: "X-T3")
        XCTAssertEqual(fit.verdict, .worksWithChanges)
        XCTAssertEqual(fit.changes, [.magentaGreenAxisMissing])
    }

    /// Issues about the recipe itself — no film simulation, the priority interlock, ignored colour
    /// or toning — are the same on every body and move no verdict.
    func testRecipeInternalIssuesDoNotMoveTheVerdict() throws {
        let fixtures = [
            RecipeSettings(),
            RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400, dRangePriority: .auto, highlightTone: 2),
            RecipeSettings(filmSimulation: .acros, color: 3),
            RecipeSettings(filmSimulation: .sepia, monochromaticColorWC: 4, monochromaticColorMG: -2)
        ]
        for s in fixtures {
            let fit = RecipeCameraFit(s, on: registry.demoModel)
            XCTAssertEqual(fit.verdict, .worksAsWritten, "\(s)")
            XCTAssertTrue(fit.changes.isEmpty, "\(s)")
        }
    }

    // MARK: - The X-Trans I and II bodies

    func testAClassicChromeRecipeIsNotAvailableOnAnXPro1() throws {
        let s = RecipeSettings(filmSimulation: .classicChrome)
        XCTAssertEqual(try fit(s, on: "X-Pro1").verdict, .notAvailable)
        XCTAssertEqual(try fit(s, on: "X100S").verdict, .notAvailable, "the X100S never got Classic Chrome")
        XCTAssertEqual(try fit(s, on: "X-T1").verdict, .worksAsWritten, "the X-T1 has it from firmware 3.00")
    }

    /// No grain, Color Chrome, Clarity or Classic Neg.; and no range, so no clamp — the half-step
    /// tone passes unjudged rather than being called a change.
    func testALegacyBodyDropsGrainAndChromeWithoutClamping() throws {
        let fit = try fit(lateGenIV, on: "X-E1")
        XCTAssertEqual(fit.verdict, .notAvailable)
        XCTAssertEqual(fit.changes, [.filmSimulationMissing(.classicNeg), .fieldMissing(.grain),
                                     .fieldMissing(.colorChromeEffect), .fieldMissing(.clarity)])
    }

    /// A body with no range for a set field makes no clamp claim; the fit says so instead of
    /// calling the recipe fine without qualification.
    func testALegacyBodyReportsTheRangesItCannotCheck() throws {
        let s = RecipeSettings(filmSimulation: .provia, highlightTone: 1.5, color: 2)
        let legacy = try fit(s, on: "X-Pro1")
        XCTAssertEqual(legacy.verdict, .worksAsWritten)
        XCTAssertEqual(legacy.unverifiedRanges, [.highlightTone, .color])
        let ranged = try fit(s, on: "X-T20")
        XCTAssertEqual(ranged.unverifiedRanges, [])
        XCTAssertEqual(ranged.changes, [.clamped(subject: "Highlight Tone", from: "+1.5", to: "+2")])
    }

    func testNoBodyWithRangesLeavesAValueUnverified() {
        for model in registry.models where model.processor != .exrProcessor {
            XCTAssertTrue(RecipeCameraFit(lateGenIV, on: model).unverifiedRanges.isEmpty, model.id)
        }
    }

    func testANeutralOrAbsentValueIsNotReportedUnverified() throws {
        let s = RecipeSettings(filmSimulation: .provia, highlightTone: 0, clarity: 2)
        XCTAssertEqual(try fit(s, on: "X-Pro1").unverifiedRanges, [],
                       "a 0 needs no range, and Clarity is not on the body to range-check")
    }

    // MARK: - Caveats

    func testCaveatsNameTheMissingSimAndPreservedFields() {
        XCTAssertEqual(RecipeCameraFit.caveats(for: RecipeSettings(), hasPreservedFields: true),
                       [.noFilmSimulation, .preservedFields])
        XCTAssertEqual(RecipeCameraFit.caveats(for: RecipeSettings(filmSimulation: .provia), hasPreservedFields: false),
                       [])
    }

    // MARK: - The all-bodies list

    func testFitsSkipTheDemoCameraAndCoverEveryOtherBodyOnce() {
        let fits = RecipeCameraFit.fits(lateGenIV, across: registry.models)
        XCTAssertEqual(fits.count, registry.models.count - 1)
        XCTAssertFalse(fits.contains { $0.id == CameraModelRegistry.demoModelID })
        XCTAssertEqual(Set(fits.map(\.id)).count, fits.count, "each body once")
    }

    func testGroupsComeInVerdictOrderAndSumToTheWhole() {
        let fits = RecipeCameraFit.fits(lateGenIV, across: registry.models)
        let groups = fits.groupedByVerdict()
        XCTAssertEqual(groups.map(\.verdict), groups.map(\.verdict).sorted())
        XCTAssertEqual(groups.map(\.fits.count).reduce(0, +), fits.count)
        XCTAssertFalse(groups.contains { $0.fits.isEmpty })
        for group in groups {
            XCTAssertTrue(group.fits.allSatisfy { $0.verdict == group.verdict })
        }
    }

    func testVerdictOrderingIsWorstLast() {
        XCTAssertLessThan(RecipeCameraFit.Verdict.worksAsWritten, .worksWithChanges)
        XCTAssertLessThan(RecipeCameraFit.Verdict.worksWithChanges, .notAvailable)
    }
}
