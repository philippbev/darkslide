import XCTest
@testable import FujiCookbook

/// Whether a control applies — asked once, answered the same way everywhere.
///
/// These rules live in one place so four callers cannot disagree. The tests that matter most here are
/// not the individual predicates but the agreement ones: they drive the editor, the read-only table
/// and the pre-push warning over the same fixtures and assert they say the same thing, which is the
/// only claim the consolidation actually makes.
///
/// Two tests deliberately pin behaviour that may be wrong — Sepia's Color, which the record leaves
/// open, and the read-only table showing Color on a monochrome recipe. Both are recorded so that
/// changing them is a decision with a failing test attached, rather than a silent drift inside some
/// later refactor.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#0xd195-grain-effect`.
@MainActor
final class RecipeApplicabilityTests: XCTestCase {

    private let registry = CameraModelRegistry.shared

    /// X-Processor Pro: no grain *size* control, and no Monochromatic Color or Clarity field at all.
    /// D-Range Priority varies within the group (the X-H1 has it: zgrimz/fujifilm-ptp-reference
    /// `docs/07-cameras.md#effect-controls-in-the-menus`).
    private var processorProBody: CameraModel {
        get throws { try XCTUnwrap(registry.models.first { $0.processor == .xProcessorPro }) }
    }

    /// A body with Monochromatic Color but not its magenta–green axis — the X-T3 and X-T30, whose
    /// manuals print a single warm–cool table. The whole reason `showMG` exists. Both are
    /// read-only, so claims about what a push sends them go through `encode`.
    private var singleAxisMonoBody: CameraModel {
        get throws {
            try XCTUnwrap(registry.models.first {
                $0.supports(.monochromaticColor) && !$0.hasMagentaGreenAxis
            })
        }
    }

    /// An X-Processor 4 body with both axes and a slot the app writes to: the processor is not
    /// what decides the axis, and the X-T4 is the body that shows it.
    private var twoAxisXProcessor4Body: CameraModel { registry.model(withID: "X-T4")! }

    private var modernBody: CameraModel { registry.demoModel }

    // MARK: - The claim the consolidation makes

    /// The editor's field filtering, the read-only table and the pre-push warning read one set of
    /// rules. Driven over the same fixtures, they agree about the D-Range Priority interlock —
    /// which is the predicate that used to have three different gates.
    func testTheEditorTheTableAndThePushWarningAgreeOnThePriorityInterlock() throws {
        let model = modernBody
        for priority in DRangePriority.allCases {
            let s = RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400,
                                   dRangePriority: priority, highlightTone: 2, shadowTone: -1)

            let withheld = Set(RecipeCompatibility.analyze(s, for: model)
                .filter { if case .notWritten = $0.kind { return true } else { return false } }
                .map(\.field))
            let noted = Set(RecipeSettingsFormatter.rows(for: s, model: model)
                .filter { $0.value.hasSuffix(RecipeSettingsFormatter.priorityNote) }
                .map(\.field))
            let inapplicable = Set(RecipeField.allCases.filter {
                RecipeApplicability.underPriority($0, in: s, on: model).reason == .underPriority
            })

            XCTAssertEqual(noted, withheld, "the table and the push disagree under \(priority.displayName)")
            XCTAssertEqual(noted, inapplicable, "the table and the rule disagree under \(priority.displayName)")
            if priority == .off {
                XCTAssertTrue(inapplicable.isEmpty, "an Off priority overrides nothing")
            } else {
                XCTAssertEqual(inapplicable, RecipeApplicability.fieldsUnderPriority,
                               "\(priority.displayName) drives exactly the three fields")
            }
        }
    }

    /// The editor hides Color on a monochrome recipe and `assembleSettings` refuses to store one.
    /// Both now read the same rule, so they cannot drift apart.
    func testTheEditorsMonochromeFilteringAndItsRepackAgree() throws {
        for sim in FilmSimulation.allCases {
            var draft = RecipeDraft(from: Recipe(name: "Draft", settings: RecipeSettings(filmSimulation: sim)))
            draft.color = 3
            draft.monoWC = 2
            draft.monoMG = 1
            let assembled = draft.assembleSettings()

            // Two rules, not one. Reading the toning row off `!colorApplies` is exactly the
            // conflation Sepia exposed: it is monochrome, so Color is out, and still has no toning.
            let probe = RecipeSettings(filmSimulation: sim)
            let colorApplies = RecipeApplicability.color(probe, on: nil).applies
            let toningApplies = RecipeApplicability.monochromaticColorWC(probe, on: nil).applies
            XCTAssertEqual(draft.isMono, !colorApplies, "isMono disagrees with the Color rule for \(sim.displayName)")
            XCTAssertEqual(assembled.color != nil, colorApplies,
                           "Color was stored against the rule for \(sim.displayName)")
            XCTAssertEqual(assembled.monochromaticColorWC != nil, toningApplies,
                           "Monochromatic Color was stored against the rule for \(sim.displayName)")
        }
    }

    /// The body gate runs first. A field the body lacks reports `bodyLacksField` even where a
    /// settings rule would also have excluded it — otherwise a screen says "not on a monochrome
    /// simulation" about a control that was never on the camera.
    func testTheBodyGateRunsBeforeTheSettingsGates() throws {
        let body = try processorProBody
        // Monochrome, so the settings rule would also exclude Color; the body has Color though,
        // so the settings rule is what answers.
        let mono = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2)
        XCTAssertEqual(RecipeApplicability.color(mono, on: body).reason, .monochrome,
                       "the body has Color, so monochrome is the reason")
        // This body has no Monochromatic Color field at all, and the recipe *is* monochrome — the
        // body's absence still wins.
        XCTAssertEqual(RecipeApplicability.monochromaticColorWC(mono, on: body).reason, .bodyLacksField)
        XCTAssertEqual(RecipeApplicability.monochromaticColorMG(mono, on: body).reason, .bodyLacksField)
    }

    // MARK: The push says so too

    /// The mirror of the Color-on-monochrome warning. A Sepia bank refuses every toning write
    /// (zgrimz/fujifilm-ptp-reference `docs/03-encodings.md#polarity-and-use`) and the push leaves
    /// it out, so a stored toning value gets a warning on the pre-push screen.
    func testThePushWarnsThatSepiaIgnoresAStoredToningValue() {
        let s = RecipeSettings(filmSimulation: .sepia, monochromaticColorWC: 3)
        let kinds = RecipeCompatibility.analyze(s, for: modernBody).map(\.kind)
        XCTAssertTrue(kinds.contains(.ignoredForFixedToning),
                      "a toning value on Sepia is not written, so the push has to say so")
    }

    /// A zero changes nothing either way, so there is nothing to warn about — the same reading the
    /// Color-on-monochrome warning already takes.
    func testAZeroToningValueOnSepiaRaisesNothing() {
        let s = RecipeSettings(filmSimulation: .sepia, monochromaticColorWC: 0)
        let kinds = RecipeCompatibility.analyze(s, for: modernBody).map(\.kind)
        XCTAssertFalse(kinds.contains(.ignoredForFixedToning))
    }

    func testAToningValueOnAcrosRaisesNothing() {
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 3)
        let kinds = RecipeCompatibility.analyze(s, for: modernBody).map(\.kind)
        XCTAssertFalse(kinds.contains(.ignoredForFixedToning), "ACROS toning is real and is written")
    }

    // MARK: - Monochrome

    func testAMonochromeSimulationHidesColorAndShowsMonochromaticColor() {
        let s = RecipeSettings(filmSimulation: .acros)
        XCTAssertEqual(RecipeApplicability.color(s, on: nil).reason, .monochrome)
        XCTAssertTrue(RecipeApplicability.monochromaticColorWC(s, on: nil).applies)
        XCTAssertTrue(RecipeApplicability.monochromaticColorMG(s, on: nil).applies)
    }

    func testAColourSimulationShowsColorAndHidesMonochromaticColor() {
        let s = RecipeSettings(filmSimulation: .classicChrome)
        XCTAssertTrue(RecipeApplicability.color(s, on: nil).applies)
        XCTAssertEqual(RecipeApplicability.monochromaticColorWC(s, on: nil).reason, .notMonochrome)
        XCTAssertEqual(RecipeApplicability.monochromaticColorMG(s, on: nil).reason, .notMonochrome)
    }

    /// A recipe with no film simulation is not monochrome, so Color applies and Monochromatic
    /// Color does not. The AI scanner produces these, so it is a common shape rather than an edge.
    func testARecipeWithNoFilmSimulationIsTreatedAsColour() {
        let s = RecipeSettings()
        XCTAssertTrue(RecipeApplicability.color(s, on: nil).applies)
        XCTAssertEqual(RecipeApplicability.monochromaticColorWC(s, on: nil).reason, .notMonochrome)
    }

    /// Sepia hides **both**, and the two noes are different.
    ///
    /// On an X-T50 a Sepia bank greys out Monochromatic Color and refuses every toning write
    /// (zgrimz/fujifilm-ptp-reference `docs/03-encodings.md#polarity-and-use`). Whether Sepia locks
    /// Color as the monochrome simulations do is open in the record
    /// (`docs/open-questions.md#bank-protocol`); the app treats Sepia as monochrome, so Color does
    /// not apply. Sepia is monochrome *and* already toned, which is why those are two predicates
    /// rather than one.
    func testSepiaHidesBothColorAndMonochromaticColor() {
        let s = RecipeSettings(filmSimulation: .sepia)
        XCTAssertEqual(RecipeApplicability.color(s, on: nil).reason, .monochrome,
                       "Sepia is monochrome, so Color does not apply")
        XCTAssertEqual(RecipeApplicability.monochromaticColorWC(s, on: nil).reason, .fixedToning,
                       "Sepia is already toned, so the warm–cool axis does not apply either")
        XCTAssertEqual(RecipeApplicability.monochromaticColorMG(s, on: nil).reason, .fixedToning,
                       "…nor the magenta–green one")
    }

    /// The contrast case that makes the rule Sepia-specific rather than a claim about monochrome.
    ///
    /// On an X-T50 under ACROS both toning axes take writes (zgrimz/fujifilm-ptp-reference
    /// `docs/03-encodings.md#0xd193--0xd194-monochromatic-color`), where Sepia refuses them. Without
    /// this the Sepia rule would rest on the assumption that the control exists at all.
    func testAcrosAndMonochromeStillHaveTheirToning() {
        for sim in FilmSimulation.allCases where sim.isMonochrome && sim != .sepia {
            let s = RecipeSettings(filmSimulation: sim)
            XCTAssertTrue(RecipeApplicability.monochromaticColorWC(s, on: nil).applies, sim.displayName)
            XCTAssertTrue(RecipeApplicability.monochromaticColorMG(s, on: nil).applies,
                          "\(sim.displayName): the X-T50 shows both axes on a monochrome simulation")
        }
    }

    // MARK: - The magenta–green axis

    /// In the registry, which has no firmware dimension: the GFX100 also lacked the axis before
    /// firmware 4.00 (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#processor-generations`) and
    /// is carried with it.
    func testOnlyTheXT3AndXT30LackTheMagentaGreenAxis() throws {
        let mono = RecipeSettings(filmSimulation: .acros)
        let singleAxis = try singleAxisMonoBody

        XCTAssertTrue(RecipeApplicability.monochromaticColorWC(mono, on: singleAxis).applies,
                      "\(singleAxis.displayName) has the warm–cool axis")
        XCTAssertEqual(RecipeApplicability.monochromaticColorMG(mono, on: singleAxis).reason,
                       .noMagentaGreenAxis,
                       "\(singleAxis.displayName) has the warm–cool axis alone")
        XCTAssertTrue(RecipeApplicability.monochromaticColorMG(mono, on: twoAxisXProcessor4Body).applies,
                      "the X-T4 is X-Processor 4 and has both axes")
        XCTAssertTrue(RecipeApplicability.monochromaticColorMG(mono, on: modernBody).applies)
        XCTAssertEqual(Set(registry.models.filter { !RecipeApplicability.hasMagentaGreenAxis(on: $0) }.map(\.id)),
                       ["X-T3", "X-T30"], "the rule reads the registry's per-body flag")
    }

    /// Generic — no body — shows the whole superset, including the axis.
    func testGenericShowsTheMagentaGreenAxis() {
        XCTAssertTrue(RecipeApplicability.hasMagentaGreenAxis(on: nil))
        XCTAssertTrue(RecipeApplicability.monochromaticColorMG(RecipeSettings(filmSimulation: .acros), on: nil).applies)
    }

    /// **What the push would do with an MG value the body has no axis for: send it.**
    ///
    /// The value is not dropped anywhere. `FujiPresetCodec.encode` gates a non-zero `D194` on
    /// `model.supports(.monochromaticColor)`, which is keyed on the field rather than the axis;
    /// `unwritableProperties` withholds nothing here; and `RecipeCompatibility.clamped` passes the
    /// value through. So `D194` would go out to a body that never advertised it, and what happens
    /// next is the camera's business — this is the fact the warning's wording rests on, which is
    /// why it is pinned rather than assumed. Neither single-axis body is writable today, so this
    /// is the rule's shape rather than a live path.
    func testAPushToASingleAxisBodyWouldSendTheMagentaGreenValueAnyway() throws {
        let body = try singleAxisMonoBody
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 3)
        let codes = Set(FujiPresetCodec.encode(RecipeCompatibility.clamped(s, to: body),
                                               model: body, slot: .empty).map(\.code))

        XCTAssertTrue(codes.contains(FujiPTP.PresetProp.monochromaticWC.rawValue),
                      "Monochromatic WC is written on \(body.displayName)")
        XCTAssertTrue(codes.contains(FujiPTP.PresetProp.monochromaticMG.rawValue),
                      "Monochromatic MG is sent to \(body.displayName) although it has no magenta–green axis")
    }

    /// The gap this file's own status note recorded: `showMG` had no counterpart in
    /// `RecipeCompatibility`, so the one field the editor filters by axis was the one field the
    /// pre-push warning could not talk about. Every other control the body lacks says so.
    func testASingleAxisBodyIsWarnedAboutTheMagentaGreenValueBeforeThePush() throws {
        let body = try singleAxisMonoBody
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 3)
        let issues = RecipeCompatibility.analyze(s, for: body)

        let mg = try XCTUnwrap(issues.first { $0.kind == .magentaGreenAxisUnsupported },
                               "Monochromatic Color's magenta–green axis raised no issue on \(body.displayName); got \(issues.map(\.kind))")
        XCTAssertEqual(mg.field, .monochromaticColor, "the issue is filed against Monochromatic Color")
        XCTAssertTrue(mg.message.contains("magenta–green"),
                      "the message names the axis rather than the whole field: \(mg.message)")
        XCTAssertTrue(mg.message.contains(body.displayName), "the message names the body: \(mg.message)")
        XCTAssertFalse(mg.message.contains("X-Processor"),
                       "the message names the manual, not a processor rule: \(mg.message)")
        XCTAssertFalse(issues.contains { $0.kind == .fieldUnsupported && $0.field == .monochromaticColor },
                       "Monochromatic Color is supported on \(body.displayName) — only the second axis isn't")

        XCTAssertTrue(RecipeCompatibility.analyze(s, for: twoAxisXProcessor4Body)
            .allSatisfy { $0.kind != .magentaGreenAxisUnsupported },
                      "the X-T4 has both axes, so the magenta–green axis raises nothing")
        XCTAssertTrue(RecipeCompatibility.analyze(s, for: modernBody)
            .allSatisfy { $0.kind != .magentaGreenAxisUnsupported },
                      "\(modernBody.displayName) has both axes, so the magenta–green axis raises nothing")
    }

    /// A body with no Monochromatic Color at all keeps the message it already had. The composed
    /// rule answers `.bodyLacksField` there, and two issues about one field would be one too many.
    func testABodyWithoutMonochromaticColorStillSaysTheWholeFieldIsUnsupported() throws {
        let body = try processorProBody
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 3)
        let issues = RecipeCompatibility.analyze(s, for: body)

        XCTAssertTrue(issues.contains { $0.kind == .fieldUnsupported && $0.field == .monochromaticColor },
                      "Monochromatic Color isn't on \(body.displayName) at all")
        XCTAssertFalse(issues.contains { $0.kind == .magentaGreenAxisUnsupported },
                       "an absent field is not an absent axis, on \(body.displayName)")
    }

    /// A neutral MG is the one value `FujiPresetCodec.encode` doesn't send to a single-axis body,
    /// so there is no write to warn about — the same rule that keeps a Color of 0 from raising
    /// `ignoredForMonochrome`. A body with the axis gets the zero, which clears a previous tint.
    func testANeutralMagentaGreenValueWarnsAboutNothing() throws {
        let body = try singleAxisMonoBody
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 0)

        XCTAssertFalse(FujiPresetCodec.encode(s, model: body, slot: .empty)
            .contains { $0.code == FujiPTP.PresetProp.monochromaticMG.rawValue },
                       "a Monochromatic MG of 0 is not sent to a body without the axis")
        XCTAssertFalse(RecipeCompatibility.analyze(s, for: body)
            .contains { $0.kind == .magentaGreenAxisUnsupported },
                       "a Monochromatic MG of 0 warns about nothing on \(body.displayName)")
        XCTAssertEqual(FujiPresetCodec.encode(s, model: twoAxisXProcessor4Body, slot: .empty)
            .first { $0.code == FujiPTP.PresetProp.monochromaticMG.rawValue }?.bytes, FujiEncoding.packI16(0),
                       "the X-T4 has the axis, so the zero is written")
    }

    /// The agreement this file exists for, now including the axis: the editor's `showMG` and the
    /// pre-push warning read one rule across every body in the registry, and the repack keeps the
    /// axis wherever the body has the field — hidden row or not — so a bank's own value survives
    /// a Save.
    func testTheEditorsMGFilteringAndThePushWarningAgreeOnEveryBody() {
        for model in registry.models {
            var draft = RecipeDraft(from: Recipe(name: "D", authoredForModelID: model.id,
                                                 settings: RecipeSettings(filmSimulation: .acros)))
            draft.monoWC = 2
            draft.monoMG = 3
            let hidden = !draft.showMG

            // Authored on Generic, which stores the axis, then read against this body — the shape
            // that reaches the push carrying a value the editor would never have offered here.
            let authoredGeneric = RecipeSettings(filmSimulation: .acros,
                                                 monochromaticColorWC: 2, monochromaticColorMG: 3)
            let warned = RecipeCompatibility.analyze(authoredGeneric, for: model)
                .contains { $0.kind == .magentaGreenAxisUnsupported }

            XCTAssertEqual(draft.showMG, model.hasMagentaGreenAxis,
                           "showMG reads the registry's flag on \(model.displayName)")
            XCTAssertEqual(draft.assembleSettings().monochromaticColorMG != nil, model.supports(.monochromaticColor),
                           "the repack keeps the axis wherever the body has the field, on \(model.displayName)")
            // The editor hides the row on every body without the axis; the push warns on that same
            // set, minus the bodies that have no Monochromatic Color field to hold an axis at all.
            XCTAssertEqual(warned, hidden && model.supports(.monochromaticColor),
                           "the editor and the pre-push warning disagree about the magenta–green axis on \(model.displayName)")
        }
    }

    // MARK: The two toning warnings do not overlap

    /// Two changes each added a warning about Monochromatic Color and neither could see the other:
    /// Sepia's fixed toning (`.ignoredForFixedToning`) and a body's missing magenta–green axis
    /// (`.magentaGreenAxisUnsupported`). The one recipe that qualifies for both — Sepia, carrying a
    /// magenta–green value, on a body with the warm–cool axis alone — must get exactly one. Sepia's, because the
    /// whole control is ignored there and `monochromaticColorMG` answers `.fixedToning` before it
    /// ever reaches the axis; a second warning about an axis the camera will not read either would
    /// be noise about noise.
    func testASepiaRecipeOnASingleAxisBodyGetsOneToningWarningNotTwo() throws {
        let body = try singleAxisMonoBody
        let s = RecipeSettings(filmSimulation: .sepia, monochromaticColorWC: 2, monochromaticColorMG: 3)
        let kinds = RecipeCompatibility.analyze(s, for: body).map(\.kind)
        XCTAssertTrue(kinds.contains(.ignoredForFixedToning),
                      "Sepia's fixed toning is the warning that applies on \(body.displayName): \(kinds)")
        XCTAssertFalse(kinds.contains(.magentaGreenAxisUnsupported),
                       "…and the axis warning stays quiet rather than doubling it: \(kinds)")
    }

    /// The converse, so the precedence is Sepia's and not a general silencing of the axis warning.
    func testAnAcrosRecipeOnASingleAxisBodyGetsTheAxisWarningAlone() throws {
        let body = try singleAxisMonoBody
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 3)
        let kinds = RecipeCompatibility.analyze(s, for: body).map(\.kind)
        XCTAssertTrue(kinds.contains(.magentaGreenAxisUnsupported),
                      "ACROS on \(body.displayName) is the axis case: \(kinds)")
        XCTAssertFalse(kinds.contains(.ignoredForFixedToning),
                       "ACROS has toning, so nothing about it is fixed: \(kinds)")
    }

    // MARK: - Grain size

    func testGrainSizeIsNotApplicableWhenTheStrengthIsOff() {
        let off = RecipeSettings(grain: GrainEffect(strength: .off, size: .large))
        XCTAssertEqual(RecipeApplicability.grainSize(off, on: nil).reason, .grainOff,
                       "a remembered size means nothing with the strength Off")
        let unset = RecipeSettings()
        XCTAssertEqual(RecipeApplicability.grainSize(unset, on: nil).reason, .grainOff,
                       "an unset grain has no size either")
    }

    func testGrainSizeIsNotApplicableOnAnXProcessorProBody() throws {
        let on = RecipeSettings(grain: GrainEffect(strength: .weak, size: .small))
        XCTAssertEqual(RecipeApplicability.grainSize(on, on: try processorProBody).reason,
                       .noGrainSizeControl)
        XCTAssertTrue(RecipeApplicability.grainSize(on, on: modernBody).applies)
        XCTAssertTrue(RecipeApplicability.grainSize(on, on: nil).applies, "Generic has the control")
    }

    /// The X-T3 and X-T30 are X-Processor 4 bodies whose GRAIN EFFECT menu is Strong / Weak / Off
    /// alone (Fujifilm's manuals), so the rule reads the registry's per-body flag, not the processor.
    func testTheXT3AndXT30HaveGrainStrengthOnly() throws {
        let on = RecipeSettings(grain: GrainEffect(strength: .weak, size: .small))
        for id in ["X-T3", "X-T30"] {
            let body = try XCTUnwrap(registry.model(withID: id))
            XCTAssertFalse(body.hasGrainSizeControl, "\(id) has no grain size control")
            XCTAssertEqual(RecipeApplicability.grainSize(on, on: body).reason, .noGrainSizeControl, id)
        }
    }

    /// Every other X-Processor 4 and 5 body has the size control; every X-Processor Pro body lacks
    /// it, and so do the EXR bodies, which have no grain at all — so a group edit cannot move the
    /// flag onto the wrong body unnoticed.
    func testEveryOtherBodyHasGrainSizeExactlyWhereItsProcessorSays() {
        for body in registry.models where !["X-T3", "X-T30"].contains(body.id) {
            XCTAssertEqual(body.hasGrainSizeControl, [.xProcessor4, .xProcessor5].contains(body.processor),
                           "\(body.id): grain size follows the processor everywhere but the X-T3/X-T30")
        }
    }

    /// The repack is the rule's other reader: a size is only ever stored where it applies.
    func testTheRepackStoresAGrainSizeExactlyWhereTheRuleAllowsOne() throws {
        for (modelID, strength) in [(nil, GrainStrength.weak), (try processorProBody.id, .weak),
                                    (nil, .off), (modernBody.id, .strong)] as [(String?, GrainStrength)] {
            var draft = RecipeDraft(from: Recipe(name: "D", authoredForModelID: modelID,
                                                 settings: RecipeSettings(filmSimulation: .provia)))
            draft.grainStrength = strength
            draft.grainSize = .large
            let assembled = draft.assembleSettings()
            guard assembled.grain != nil else { continue }
            let expected = RecipeApplicability.grainSize(assembled, on: draft.model).applies
            XCTAssertEqual(assembled.grain?.size != nil, expected,
                           "grain size storage disagrees with the rule for \(modelID ?? "Generic")")
        }
    }

    // MARK: - The D-Range Priority interlock

    func testThePriorityMakesExactlyThreeFieldsInapplicable() {
        let s = RecipeSettings(dynamicRange: .dr400, dRangePriority: .strong,
                               highlightTone: 2, shadowTone: -1, color: 1, clarity: 2)
        for field in RecipeField.allCases {
            let expected = RecipeApplicability.fieldsUnderPriority.contains(field)
            XCTAssertEqual(RecipeApplicability.underPriority(field, in: s, on: nil).reason == .underPriority,
                           expected, "\(field.displayName) under a Strong priority")
        }
    }

    /// A body without the field never receives the priority — the push drops it — so there is
    /// nothing to override. No body means no gate, and an on priority is taken at its word.
    func testABodyWithoutThePriorityFieldHasNothingToOverride() throws {
        let s = RecipeSettings(dynamicRange: .dr400, dRangePriority: .strong, highlightTone: 2)
        let body = try XCTUnwrap(registry.models.first { !$0.supports(.dRangePriority) })

        XCTAssertFalse(RecipeApplicability.priorityOverrides(s, on: body),
                       "\(body.displayName) never receives the priority")
        XCTAssertTrue(RecipeApplicability.underPriority(.dynamicRange, in: s, on: body).applies)
        XCTAssertTrue(RecipeApplicability.priorityOverrides(s, on: nil), "no body means no gate")
        XCTAssertTrue(RecipeApplicability.priorityOverrides(s, on: modernBody))
    }

    func testAnOffOrUnsetPriorityOverridesNothing() {
        for s in [RecipeSettings(dynamicRange: .dr400, dRangePriority: .off),
                  RecipeSettings(dynamicRange: .dr400)] {
            XCTAssertFalse(RecipeApplicability.priorityOverrides(s, on: nil))
            XCTAssertTrue(RecipeApplicability.underPriority(.dynamicRange, in: s, on: nil).applies)
        }
    }

    /// The editor greys Dynamic Range, Highlight Tone and Shadow Tone through this predicate, read
    /// against the draft's own model. Asked against no body it answered `drp != .off`, so setting a
    /// recipe's Camera Model to an X-Trans III body greyed all three and showed the footer, while
    /// the push wrote them exactly as chosen — and the D-Range Priority row is hidden on that body,
    /// so there was no control on screen to turn the thing off. `draft.model` is the whole fix.
    func testTheEditorReadsThePriorityAgainstTheBodyItIsAuthoringFor() throws {
        let noField = try XCTUnwrap(registry.models.first { !$0.supports(.dRangePriority) },
                                    "no body without D-Range Priority in the registry")
        let settings = RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400,
                                      dRangePriority: .strong, highlightTone: 2, shadowTone: -1)

        func draft(for model: CameraModel?) -> RecipeDraft {
            RecipeDraft(from: Recipe(name: "Draft", authoredForModelID: model?.id, settings: settings))
        }

        let onNoField = draft(for: noField)
        XCTAssertFalse(RecipeApplicability.priorityOverrides(onNoField.dRangePriority, on: onNoField.model),
                       "Dynamic Range, Highlight Tone and Shadow Tone are the recipe's own on \(noField.displayName)")

        let onModern = draft(for: modernBody)
        XCTAssertTrue(RecipeApplicability.priorityOverrides(onModern.dRangePriority, on: onModern.model),
                      "Dynamic Range, Highlight Tone and Shadow Tone are the camera's on \(modernBody.displayName)")

        let generic = draft(for: nil)
        XCTAssertTrue(RecipeApplicability.priorityOverrides(generic.dRangePriority, on: generic.model),
                      "Generic has every field, so an on D-Range Priority is taken at its word")
    }

    /// The gate belongs to the push, so it is read off the push rather than restated here: the
    /// editor greys those three rows on exactly the bodies where `analyze` withholds them, and the
    /// footers that name the interlock are shown on exactly those bodies too.
    func testTheEditorGreysPreciselyWhatThePushWithholds() {
        let settings = RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400,
                                      dRangePriority: .strong, highlightTone: 2, shadowTone: -1)
        for model in registry.models {
            let draft = RecipeDraft(from: Recipe(name: "Draft", authoredForModelID: model.id, settings: settings))
            let withheld = RecipeCompatibility.analyze(settings, for: model)
                .contains { if case .notWritten = $0.kind { return true } else { return false } }
            XCTAssertEqual(RecipeApplicability.priorityOverrides(draft.dRangePriority, on: draft.model), withheld,
                           "the editor greys Dynamic Range, Highlight Tone and Shadow Tone on \(model.displayName) exactly when the push withholds them")
        }
    }

    /// A body without the priority hides the D-Range Priority row and keeps the Dynamic Range one,
    /// which is what made the old behaviour a dead end rather than merely wrong. Pinned so the fix
    /// cannot be quietly undone by a field-set change instead of a predicate change.
    func testABodyWithoutThePriorityStillOffersTheDynamicRangeRow() throws {
        let noField = try XCTUnwrap(registry.models.first { !$0.supports(.dRangePriority) })
        XCTAssertTrue(noField.supports(.dynamicRange),
                      "\(noField.displayName) still shows a Dynamic Range row")
        XCTAssertTrue(noField.supports(.highlightTone) && noField.supports(.shadowTone),
                      "\(noField.displayName) still shows Highlight Tone and Shadow Tone rows")
        XCTAssertFalse(noField.supports(.dRangePriority),
                       "\(noField.displayName) shows no D-Range Priority row to turn off")
    }

    // MARK: - What the core deliberately does not know

    /// The soft-Off equivalence is a `RecipeMatcher` policy and must never reach here: a recipe
    /// with no Color Chrome Effect is not the same as one set to Off, because the develop writes only
    /// a set field and an unset one keeps the RAF's as-shot value. Applicability answers whether the
    /// *control* applies and has no opinion about the value in it — so an unset field and an Off
    /// field are indistinguishable to every rule.
    func testApplicabilityNeverInspectsAValueOnlyWhetherTheControlExists() {
        let unset = RecipeSettings(filmSimulation: .classicChrome)
        let off = RecipeSettings(filmSimulation: .classicChrome, colorChromeEffect: .off,
                                 colorChromeFXBlue: .off)
        for field in RecipeField.allCases {
            XCTAssertEqual(RecipeApplicability.underPriority(field, in: unset, on: modernBody),
                           RecipeApplicability.underPriority(field, in: off, on: modernBody),
                           "\(field.displayName) changed answer because a value was Off rather than unset")
        }
        XCTAssertEqual(RecipeApplicability.color(unset, on: nil), RecipeApplicability.color(off, on: nil))
    }

    /// **Pinned, not endorsed.** The read-only table has never hidden Color on a monochrome recipe
    /// that stores one — it gates on the body and on value presence, nothing else — while the push
    /// warns the camera will ignore it. Six screens render this table. Consolidating the rules did
    /// not change it; this test exists so that "improving" it later is a deliberate act.
    func testTheReadOnlyTableStillShowsColorOnAMonochromeRecipe() {
        let s = RecipeSettings(filmSimulation: .acros, color: 3)
        let row = RecipeSettingsFormatter.rows(for: s, model: modernBody).first { $0.field == .color }
        XCTAssertEqual(row?.value, "+3", "the table shows a stored Color even on a monochrome recipe")
        XCTAssertEqual(RecipeApplicability.color(s, on: modernBody).reason, .monochrome,
                       "…while the rule says the control does not apply")
    }
}
