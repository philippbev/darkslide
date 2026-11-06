import XCTest
@testable import FujiCookbook

/// Where Monochromatic Color is clamped, and what the app says when it is.
///
/// `RecipeCompatibility.clamped(_:to:)` clamps both toning axes before a push, so the pre-push
/// check has to warn about both. The bodies that make the magenta–green warning reachable have the
/// axis and a −9…+9 cap — the X-T30 III, the X-M5 and the GFX100RF among them. Save does not clamp
/// toning: the range is a cap rather than a measurement on most bodies, and a value read from a
/// bank has to survive an edit, so the push and the develop clamp at write time and say so. Each
/// axis warns only where the push writes it, and the develop, which has a profile cell for each
/// axis, lists the same clamps the push does.
@MainActor
final class MonochromaticColorClampTests: XCTestCase {
    override func setUp() { super.setUp(); CameraReportStore.deleteLatest() }

    private let registry = CameraModelRegistry.shared
    private var xM5: CameraModel { registry.model(withID: "X-M5")! }
    private var xT30III: CameraModel { registry.model(withID: "X-T30 III")! }
    private var xE4: CameraModel { registry.model(withID: "X-E4")! }
    private var xT3: CameraModel { registry.model(withID: "X-T3")! }
    private var xT50: CameraModel { registry.model(withID: "X-T50")! }
    private let wc = FujiPTP.PresetProp.monochromaticWC.rawValue
    private let mg = FujiPTP.PresetProp.monochromaticMG.rawValue
    private let nine = NumericRange(min: -9, max: 9, step: 1)

    /// ACROS, so both axes apply. ±12 is past ±9 and inside ±18.
    private let toned = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 12, monochromaticColorMG: -12)

    private func kinds(_ settings: RecipeSettings, on model: CameraModel) -> [FieldCompatibilityIssue.Kind] {
        RecipeCompatibility.analyze(settings, for: model).map(\.kind)
    }

    // MARK: The pre-push check

    /// The two-axis bodies still at the ±9 cap, pinned: a body leaves this set by taking
    /// `rangesToningEighteen`, and would join it by gaining the axis.
    func testEveryBodyWithTheMGAxisAtNineWarnsAboutBothAxes() {
        let reachable = registry.models.filter {
            $0.supports(.monochromaticColor) && RecipeApplicability.hasMagentaGreenAxis(on: $0)
                && $0.range(for: .monochromaticColor) == nine
        }
        XCTAssertEqual(Set(reachable.map(\.id)),
                       ["X-E4", "X-T30 II", "X-T30 III", "X-M5",
                        "GFX50S II", "GFX100 II", "GFX100S II", "GFX100RF"])
        for model in reachable {
            XCTAssertEqual(kinds(toned, on: model),
                           [.valueClamped(from: "+12", to: "+9"), .magentaGreenClamped(from: "−12", to: "−9")],
                           model.id)
        }
    }

    func testEachClampNamesItsAxis() {
        let issues = RecipeCompatibility.analyze(toned, for: xM5)
        XCTAssertEqual(issues.map(\.message), [
            "Monochromatic Color (WC) +12 is outside \(xM5.displayName)'s range; it will be clamped to +9.",
            "Monochromatic Color (MG) −12 is outside \(xM5.displayName)'s range; it will be clamped to −9.",
        ])
        XCTAssertEqual(issues.map(\.subject), ["Monochromatic Color (WC)", "Monochromatic Color (MG)"])
        XCTAssertEqual(issues.map(\.field), [.monochromaticColor, .monochromaticColor])
    }

    /// The case the warm–cool check could never see: WC inside the range, MG outside it.
    func testAnMGClampOnItsOwnIsRaised() {
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 3, monochromaticColorMG: 15)
        XCTAssertEqual(kinds(s, on: xT30III), [.magentaGreenClamped(from: "+15", to: "+9")])
        XCTAssertEqual(RecipeCompatibility.clamped(s, to: xT30III).monochromaticColorMG, 9,
                       "the clamp the warning describes")
    }

    func testAnXT50ClampsMGOnlyPastEighteen() {
        XCTAssertEqual(kinds(toned, on: xT50), [])
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 0, monochromaticColorMG: 20)
        XCTAssertEqual(kinds(s, on: xT50), [.magentaGreenClamped(from: "+20", to: "+18")])
    }

    /// A body with the warm–cool axis alone — the X-T3 — gets `.magentaGreenAxisUnsupported`, which
    /// already describes the value, clamp included. A clamp issue beside it would say the same
    /// thing twice.
    func testABodyWithoutTheMGAxisGetsTheAxisWarningAndNoMGClamp() {
        XCTAssertEqual(kinds(toned, on: xT3),
                       [.valueClamped(from: "+12", to: "+9"), .magentaGreenAxisUnsupported])
    }

    /// An X-Processor 4 body with both axes gets both clamps, like any other two-axis body at the cap.
    func testATwoAxisXProcessor4BodyGetsBothClamps() {
        XCTAssertEqual(kinds(toned, on: xE4),
                       [.valueClamped(from: "+12", to: "+9"), .magentaGreenClamped(from: "−12", to: "−9")])
    }

    /// The push writes no toning on a colour simulation or on Sepia, so there is no MG write to clamp.
    func testNoMGClampWhereThePushWritesNoToning() {
        for sim in [FilmSimulation.provia, .sepia] {
            let s = RecipeSettings(filmSimulation: sim, monochromaticColorWC: 0, monochromaticColorMG: -12)
            XCTAssertFalse(kinds(s, on: xM5).contains {
                if case .magentaGreenClamped = $0 { return true }
                return false
            }, sim.rawValue)
        }
    }

    /// The warm–cool clamp is gated the same way. `clamped(_:to:)` still clamps the value, and
    /// nothing writes it, so the camera never sees the difference.
    func testNoWCClampWhereThePushWritesNoToning() {
        let colour = RecipeSettings(filmSimulation: .provia, monochromaticColorWC: 12)
        var sepia = colour
        sepia.filmSimulation = .sepia
        XCTAssertEqual(kinds(colour, on: xM5), [])
        XCTAssertEqual(kinds(sepia, on: xM5), [.ignoredForFixedToning], "Sepia's own warning, and no clamp beside it")
        XCTAssertEqual(kinds(colour, on: xE4), [])
        for s in [colour, sepia] {
            let toning = FujiPresetCodec.toningValuesToWrite(s, model: xM5)
            XCTAssertNil(toning.warmCool, s.filmSimulation!.rawValue)
            XCTAssertNil(toning.magentaGreen, s.filmSimulation!.rawValue)
            XCTAssertEqual(RecipeCompatibility.clamped(s, to: xM5).monochromaticColorWC, 9, s.filmSimulation!.rawValue)
        }
    }

    // MARK: The magenta–green axis on a body without it

    private func axisWarning(_ settings: RecipeSettings, on model: CameraModel) -> String? {
        RecipeCompatibility.analyze(settings, for: model).first { $0.kind == .magentaGreenAxisUnsupported }?.message
    }

    /// The push would send a single-axis body the MG value clamped to its range, so the warning
    /// names the value sent and the recipe's own beside it. The X-T3 is read-only, so the message
    /// is pinned through `analyze`; a two-axis X-Processor 4 body at the cap gets the clamp
    /// warnings instead, and its push lists both axes with no axis advisory.
    func testTheAxisWarningNamesTheClampedValueThePushSends() async {
        XCTAssertEqual(axisWarning(toned, on: xT3), "\(xT3.displayName) has Monochromatic Color's warm–cool axis only; Fujifilm's manual lists no magenta–green axis for it. The push still sends Monochromatic Color (MG) −9, clamped from −12, so this body may refuse it and report the push as partly applied.")

        let (camera, transport) = await connected(as: "FUJIFILM X-E4")
        XCTAssertEqual(camera.session.connected?.model?.id, "X-E4")
        let result = await camera.slotWriter.push(settings: toned, name: "Toned", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertEqual(result.clampedFields, ["Monochromatic Color (WC)", "Monochromatic Color (MG)"])
        XCTAssertFalse(result.advisories.contains { $0.contains("magenta–green") },
                       "a body with the axis gets no axis warning: \(result.advisories)")
        let storedMG = await transport.storedProperty(mg, slot: 1)
        XCTAssertEqual(storedMG, FujiEncoding.packI16(-90), "the clamped value")
    }

    func testTheAxisWarningNamesAnUnclampedValueAlone() {
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 3)
        XCTAssertEqual(axisWarning(s, on: xT3), "\(xT3.displayName) has Monochromatic Color's warm–cool axis only; Fujifilm's manual lists no magenta–green axis for it. The push still sends Monochromatic Color (MG) +3, so this body may refuse it and report the push as partly applied.")
    }

    // MARK: The push and the develop

    private func connected(as productName: String) async -> (CameraServices, MockCameraTransport) {
        let transport = MockCameraTransport(faults: MockCameraFaults(productName: productName, isInstant: true))
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        return (manager, transport)
    }

    func testAPushListsBothClampedAxesAndWritesNine() async {
        let (camera, transport) = await connected(as: "FUJIFILM X-M5")
        XCTAssertEqual(camera.session.connected?.model?.id, "X-M5")
        let result = await camera.slotWriter.push(settings: toned, name: "Toned", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied, "the clamped values are what is written and verified")
        XCTAssertEqual(result.clampedFields, ["Monochromatic Color (WC)", "Monochromatic Color (MG)"])
        let storedWC = await transport.storedProperty(wc, slot: 1)
        let storedMG = await transport.storedProperty(mg, slot: 1)
        XCTAssertEqual(storedWC, FujiEncoding.packI16(90))
        XCTAssertEqual(storedMG, FujiEncoding.packI16(-90))
    }

    /// The conversion profile has a cell for each axis, so a develop clamps and lists both, as the
    /// push does.
    func testADevelopListsBothClampedAxes() async {
        let (camera, _) = await connected(as: "FUJIFILM X-M5")
        let result = await camera.conversion.cook(raf: RAFFixture.raf(),
                                       filename: "DSCF0001.RAF", settings: toned)
        XCTAssertTrue(result.success, result.errorMessage ?? "")
        XCTAssertEqual(result.clampedFields, ["Monochromatic Color (WC)", "Monochromatic Color (MG)"])
        XCTAssertFalse(result.notes.contains { $0.hasPrefix("Monochromatic Color") }, "\(result.notes)")
    }

    /// A colour recipe's toning is not written, so the push lists no clamp for it and writes no
    /// clamped value.
    func testAPushOfAColourRecipeListsNoToningClamp() async {
        let (camera, transport) = await connected(as: "FUJIFILM X-M5")
        let before = await transport.storedProperty(wc, slot: 1)
        let result = await camera.slotWriter.push(settings: RecipeSettings(filmSimulation: .provia, monochromaticColorWC: 12),
                                       name: "Colour", toSlot: 1)
        XCTAssertEqual(result.clampedFields, [])
        let storedWC = await transport.storedProperty(wc, slot: 1)
        XCTAssertEqual(storedWC, before, "no warm–cool value is written")
    }

    // MARK: The develop's magenta–green value

    private func developed(_ settings: RecipeSettings, as productName: String) async -> ConversionResult {
        let (camera, _) = await connected(as: productName)
        let result = await camera.conversion.cook(raf: RAFFixture.raf(),
                                       filename: "DSCF0001.RAF", settings: settings)
        XCTAssertTrue(result.success, "\(productName): \(result.errorMessage ?? "")")
        return result
    }

    /// Bodies that pair the Kitchen with the MG axis, on both processors. An MG inside the range is
    /// applied like any other value: nothing to list, nothing to note, nothing to report.
    func testADevelopAppliesAnMGValueWithoutComment() async {
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 3, monochromaticColorMG: 5)
        for body in ["FUJIFILM X-T30 III", "FUJIFILM X-M5", "FUJIFILM X-T4", "FUJIFILM GFX100S"] {
            let result = await developed(s, as: body)
            XCTAssertEqual(result.notes, [], body)
            XCTAssertEqual(result.clampedFields, [], body)
            XCTAssertFalse(result.isReportableAnomaly, body)
        }
    }

    // MARK: The editor

    private func saved(_ settings: RecipeSettings, on modelID: String?) -> RecipeSettings {
        RecipeDraft(from: Recipe(name: "Toned", authoredForModelID: modelID, settings: settings)).assembleSettings()
    }

    /// Save keeps a value past the body's cap; the pre-push check is where it is described.
    func testSaveKeepsToningPastTheBodysRangeAndThePushWarns() {
        let s = saved(toned, on: "X-M5")
        XCTAssertEqual(s.monochromaticColorWC, 12)
        XCTAssertEqual(s.monochromaticColorMG, -12)
        XCTAssertEqual(kinds(s, on: xM5),
                       [.valueClamped(from: "+12", to: "+9"), .magentaGreenClamped(from: "−12", to: "−9")],
                       "the saved value meets the range at the push, with a warning")
    }

    func testSaveKeepsToningInsideTheRange() {
        let s = saved(toned, on: "X-T50")
        XCTAssertEqual(s.monochromaticColorWC, 12)
        XCTAssertEqual(s.monochromaticColorMG, -12)
    }

    /// Generic has no body, so the stepper's track is `DefaultRanges` (±18). A recipe file carries
    /// any 32-bit value, and Save keeps it as the file had it.
    func testSaveOnGenericKeepsAValuePastTheDefaultRange() {
        let s = saved(RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 40, monochromaticColorMG: -40), on: nil)
        XCTAssertEqual(s.monochromaticColorWC, 40)
        XCTAssertEqual(s.monochromaticColorMG, -40)
    }

    func testSaveLeavesUnsetToningUnset() {
        let s = saved(RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 12), on: "X-M5")
        XCTAssertEqual(s.monochromaticColorWC, 12)
        XCTAssertNil(s.monochromaticColorMG, "nil keeps the bank's own axis, and Save must not invent a value")
    }

    /// The MG row is hidden on a body with the warm–cool axis alone, and the value behind it is
    /// kept: a bank read or a file can carry one, and Save is not where it is judged.
    func testSaveKeepsAHiddenMGValue() {
        let s = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 2, monochromaticColorMG: 3)
        let draft = RecipeDraft(from: Recipe(name: "Toned", authoredForModelID: "X-T3", settings: s))
        XCTAssertFalse(draft.showMG)
        XCTAssertEqual(draft.assembleSettings().monochromaticColorMG, 3)
    }
}
