import XCTest
@testable import FujiCookbook

/// Monochromatic Color's range and axes are per body. −18…+18 belongs to the bodies with range
/// evidence of their own or a group membership behind them (the registry comment on
/// `rangesToningEighteen` says which); every other body with the control stays at −9…+9, which is
/// manual-backed on the single-axis X-T3 and X-T30 and an operational cap on the rest
/// (zgrimz/fujifilm-ptp-reference `docs/03-encodings.md`).
///
/// One X-T50 recipe at WC +12 is followed through every path that reads the range — the editor, a
/// bank read, a file import, the pre-push check, the push and the develop — and an X-E4, an
/// X-Trans IV body still at the cap, through the same paths, to show it stops at 9.
@MainActor
final class MonochromaticColorRangeTests: XCTestCase {
    override func setUp() { super.setUp(); CameraReportStore.deleteLatest() }

    private let registry = CameraModelRegistry.shared
    private var xT50: CameraModel { registry.model(withID: "X-T50")! }
    private var xE4: CameraModel { registry.model(withID: "X-E4")! }
    private let wc = FujiPTP.PresetProp.monochromaticWC.rawValue
    private let mg = FujiPTP.PresetProp.monochromaticMG.rawValue
    private let eighteen = NumericRange(min: -18, max: 18, step: 1)
    private let nine = NumericRange(min: -9, max: 9, step: 1)

    /// ACROS, so both axes apply. +12 is past ±9 and inside ±18.
    private let toned = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 12, monochromaticColorMG: -12)
    /// The warm–cool axis alone.
    private let warmCoolOnly = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 12)

    // MARK: Which bodies run to 18

    /// A body joins this set on range evidence of its own or as a member of the X-Trans V group,
    /// and the registry comment on `rangesToningEighteen` says which.
    func testExactlyTheBodiesWithRangeEvidenceRunToEighteen() {
        let ids = registry.models.filter { $0.range(for: .monochromaticColor) == eighteen }.map(\.id)
        XCTAssertEqual(Set(ids), ["X-T5", "X-T50", "X-H2", "X-H2S", "X100VI", "X-S20", "X-E5",
                                  "X-T4", "X100V", "X-S10", "X-Pro3", "GFX100", "GFX100S",
                                  CameraModelRegistry.demoModelID])
    }

    func testEveryOtherBodyWithTheControlStaysAtNine() {
        let rest = registry.models.filter { $0.supports(.monochromaticColor) && $0.range(for: .monochromaticColor) != eighteen }
        XCTAssertTrue(rest.contains { $0.id == "X-E4" }, "the capped X-Trans IV bodies are among them")
        for model in rest {
            XCTAssertEqual(model.range(for: .monochromaticColor), nine, model.id)
        }
    }

    // MARK: Which bodies have the magenta–green axis

    /// A per-body fact from Fujifilm's manuals, carried by the registry rather than derived from
    /// the processor: only the X-T3 and X-T30 have the warm–cool axis alone.
    func testOnlyTheXT3AndXT30AreWarmCoolOnly() {
        let single = registry.models.filter { $0.supports(.monochromaticColor) && !$0.hasMagentaGreenAxis }
        XCTAssertEqual(Set(single.map(\.id)), ["X-T3", "X-T30"])
    }

    // MARK: Editing

    func testTheEditorOffersAndKeepsWCPlusTwelveOnAnXT50() {
        let draft = RecipeDraft(from: Recipe(name: "Toned", authoredForModelID: "X-T50", settings: toned))
        XCTAssertEqual(draft.range(.monochromaticColor), eighteen, "the stepper's track")
        let saved = draft.assembleSettings()
        XCTAssertEqual(saved.monochromaticColorWC, 12)
        XCTAssertEqual(saved.monochromaticColorMG, -12)
    }

    func testTheEditorStopsAnXTransIVBodyAtNine() {
        let draft = RecipeDraft(from: Recipe(name: "Toned", authoredForModelID: "X-E4", settings: warmCoolOnly))
        XCTAssertEqual(draft.range(.monochromaticColor), nine)
    }

    // MARK: Import — a bank read

    /// A complete ACROS bank for `model`, with the toning axes set to raw wire values.
    private func bank(warmCool: Int, magentaGreen: Int?, for model: CameraModel) -> FujiPresetCodec.Props {
        var props: FujiPresetCodec.Props = [:]
        for (code, bytes) in FujiPresetCodec.encode(RecipeSettings(filmSimulation: .acros), model: model, slot: .empty) {
            props[code] = bytes
        }
        props[wc] = FujiEncoding.packI16(warmCool)
        if let magentaGreen { props[mg] = FujiEncoding.packI16(magentaGreen) }
        return props
    }

    func testAnXT50BankHoldingWCPlusTwelveReadsCleanly() {
        let profile = FujiPresetCodec.decode(bank(warmCool: 120, magentaGreen: -120, for: xT50), name: nil, model: xT50)
        XCTAssertEqual(profile.settings.monochromaticColorWC, 12)
        XCTAssertEqual(profile.settings.monochromaticColorMG, -12)
        XCTAssertEqual(profile.divergences, [], "inside the X-T50's range, so there is nothing to flag")
    }

    func testAnXTransIVBankHoldingWCPlusTwelveIsFlaggedOutOfRange() {
        let profile = FujiPresetCodec.decode(bank(warmCool: 120, magentaGreen: nil, for: xE4), name: nil, model: xE4)
        XCTAssertEqual(profile.settings.monochromaticColorWC, 12, "kept, like every out-of-range number")
        XCTAssertEqual(profile.divergences.map(\.code), [wc])
        guard case .outOfRange(let min, let max) = profile.divergences.first?.kind else {
            return XCTFail("expected an out-of-range divergence, got \(String(describing: profile.divergences.first?.kind))")
        }
        XCTAssertEqual(min, -9)
        XCTAssertEqual(max, 9)
    }

    /// A bank read keeps both axes, and so does the editor: an X-T4 bank's MG reaches a saved
    /// recipe unchanged. The processor rule used to hide the row there and drop the value on the
    /// first open-and-save.
    func testAnXT4BanksMGSurvivesTheEditor() {
        let xT4 = registry.model(withID: "X-T4")!
        let profile = FujiPresetCodec.decode(bank(warmCool: 20, magentaGreen: -10, for: xT4), name: nil, model: xT4)
        XCTAssertEqual(profile.settings.monochromaticColorMG, -1)
        let draft = RecipeDraft(from: Recipe(name: "Read", authoredForModelID: "X-T4", settings: profile.settings))
        XCTAssertTrue(draft.showMG, "the X-T4 shows the row")
        XCTAssertEqual(draft.assembleSettings().monochromaticColorMG, -1)
    }

    // MARK: Import — a recipe file

    func testARecipeFileCarriesWCPlusTwelve() throws {
        let data = try RecipePortability.encodeSingle(Recipe(name: "Toned", authoredForModelID: "X-T50", settings: toned))
        let portable = try XCTUnwrap(RecipePortability.decodeFile(data).allRecipes.first)
        let imported = RecipePortability.makeRecipe(from: portable)
        XCTAssertEqual(imported.settings.monochromaticColorWC, 12)
        XCTAssertEqual(imported.settings.monochromaticColorMG, -12)
        XCTAssertEqual(imported.authoredForModelID, "X-T50")
    }

    // MARK: The push

    private func written(_ settings: RecipeSettings, to model: CameraModel) -> [UInt16: Data] {
        Dictionary(FujiPresetCodec.encode(settings, model: model, slot: .empty).map { ($0.code, $0.bytes) },
                   uniquingKeysWith: { $1 })
    }

    func testAnXT50PushNeitherWarnsNorClampsWCPlusTwelve() {
        let issues = RecipeCompatibility.analyze(toned, for: xT50)
        XCTAssertTrue(issues.isEmpty, "\(issues.map(\.message))")
        let clamped = RecipeCompatibility.clamped(toned, to: xT50, droppingUnsupportedFilmSimulation: false)
        XCTAssertEqual(clamped.monochromaticColorWC, 12)
        XCTAssertEqual(clamped.monochromaticColorMG, -12)
        let bytes = written(clamped, to: xT50)
        XCTAssertEqual(bytes[wc], FujiEncoding.packI16(120))
        XCTAssertEqual(bytes[mg], FujiEncoding.packI16(-120))
    }

    func testAnXTransIVPushClampsWCPlusTwelveToNineAndSaysSo() {
        XCTAssertEqual(RecipeCompatibility.analyze(warmCoolOnly, for: xE4).map(\.kind),
                       [.valueClamped(from: "+12", to: "+9")])
        let clamped = RecipeCompatibility.clamped(warmCoolOnly, to: xE4, droppingUnsupportedFilmSimulation: false)
        XCTAssertEqual(clamped.monochromaticColorWC, 9)
        XCTAssertEqual(written(clamped, to: xE4)[wc], FujiEncoding.packI16(90))
    }

    private func connected(as productName: String) async -> (CameraServices, MockCameraTransport) {
        let transport = MockCameraTransport(faults: MockCameraFaults(productName: productName, isInstant: true))
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        return (manager, transport)
    }

    /// End to end through the mock, which stores what it is sent: the bytes that reach the bank,
    /// and the read-back that verifies them.
    func testAPushToAnXT50WritesAndVerifiesWCPlusTwelve() async {
        let (camera, transport) = await connected(as: "FUJIFILM X-T50")
        XCTAssertEqual(camera.session.connected?.model?.id, "X-T50")
        let result = await camera.slotWriter.push(settings: toned, name: "Toned", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied)
        let storedWC = await transport.storedProperty(wc, slot: 1)
        let storedMG = await transport.storedProperty(mg, slot: 1)
        XCTAssertEqual(storedWC, FujiEncoding.packI16(120))
        XCTAssertEqual(storedMG, FujiEncoding.packI16(-120))
    }

    func testAPushToAnXTransIVBodyWritesNine() async {
        let (camera, transport) = await connected(as: "FUJIFILM X-E4")
        XCTAssertEqual(camera.session.connected?.model?.id, "X-E4")
        let result = await camera.slotWriter.push(settings: warmCoolOnly, name: "Toned", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied, "the clamped value is what is written and verified")
        let storedWC = await transport.storedProperty(wc, slot: 1)
        XCTAssertEqual(storedWC, FujiEncoding.packI16(90))
    }

    // MARK: The develop

    /// The Kitchen clamps with the same call before it patches the conversion profile.
    func testADevelopWritesTwelveForAnXT50AndNineForAnXTransIVBody() throws {
        let base = FujiRawConvProfile.demoGFXBaseProfile()
        let layout = try XCTUnwrap(FujiRawConvProfile.resolveLayout(base))
        func developed(on model: CameraModel) -> (wc: Int?, mg: Int?) {
            let profile = FujiRawConvProfile.patch(base: base, with: RecipeCompatibility.clamped(toned, to: model),
                                                   model: model, layout: layout)
            let decoded = FujiRawConvProfile.decode(profile, layout: layout)
            return (decoded.monochromaticColorWC, decoded.monochromaticColorMG)
        }
        XCTAssertEqual(developed(on: xT50).wc, 12)
        XCTAssertEqual(developed(on: xT50).mg, -12)
        XCTAssertEqual(developed(on: xE4).wc, 9)
        XCTAssertEqual(developed(on: xE4).mg, -9)
    }
}
