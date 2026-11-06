import XCTest
@testable import FujiCookbook

/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#0xd193--0xd194-monochromatic-color`, `docs/03-encodings.md#menu-range-per-body`, and
/// `docs/07-cameras.md#effect-controls-in-the-menus`.
@MainActor
final class NeutralToningTests: XCTestCase {
    override func setUp() { super.setUp(); CameraReportStore.deleteLatest() }

    private let wc = FujiPTP.PresetProp.monochromaticWC.rawValue
    private let mg = FujiPTP.PresetProp.monochromaticMG.rawValue

    private func connected(_ faults: MockCameraFaults = MockCameraFaults()) async -> (CameraServices, MockCameraTransport) {
        var faults = faults; faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        return (manager, transport)
    }

    private func mono(wc: Int?, mg: Int?) -> RecipeSettings {
        var settings = RecipeSettings.neutral
        settings.filmSimulation = .acros
        // Exposure bias is authored by `.neutral` but is not a writable preset field on DEMO.
        // Keep this fixture fully applicable so a partial result can only come from the test fault.
        settings.exposureBias = nil
        settings.monochromaticColorWC = wc
        settings.monochromaticColorMG = mg
        return settings
    }

    func testExplicitZerosClearPreviouslyWrittenToningAndAreVerified() async {
        let (camera, transport) = await connected()
        let tinted = await camera.slotWriter.push(settings: mono(wc: 3, mg: -2), name: "Tint", toSlot: 1)
        XCTAssertEqual(tinted.outcome, .applied)
        let tintedWC = await transport.storedProperty(wc, slot: 1)
        let tintedMG = await transport.storedProperty(mg, slot: 1)
        XCTAssertEqual(tintedWC, FujiEncoding.packI16(30))
        XCTAssertEqual(tintedMG, FujiEncoding.packI16(-20))
        let result = await camera.slotWriter.push(settings: mono(wc: 0, mg: 0), name: "Neutral", toSlot: 1)
        let storedWC = await transport.storedProperty(wc, slot: 1)
        let storedMG = await transport.storedProperty(mg, slot: 1)
        XCTAssertEqual(storedWC, FujiEncoding.packI16(0))
        XCTAssertEqual(storedMG, FujiEncoding.packI16(0))
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertEqual(result.fields.first { $0.code == wc }?.outcome, .written)
        XCTAssertEqual(result.fields.first { $0.code == mg }?.outcome, .written)
    }

    func testZeroIsPerAxisAndNilStillPreservesTheOtherAxis() async {
        let (camera, transport) = await connected()
        _ = await camera.slotWriter.push(settings: mono(wc: 3, mg: -2), name: "Tint", toSlot: 1)
        _ = await camera.slotWriter.push(settings: mono(wc: 0, mg: nil), name: "WC neutral", toSlot: 1)
        var storedWC = await transport.storedProperty(wc, slot: 1)
        var storedMG = await transport.storedProperty(mg, slot: 1)
        XCTAssertEqual(storedWC, FujiEncoding.packI16(0))
        XCTAssertEqual(storedMG, FujiEncoding.packI16(-20))
        _ = await camera.slotWriter.push(settings: mono(wc: nil, mg: 0), name: "MG neutral", toSlot: 1)
        storedWC = await transport.storedProperty(wc, slot: 1)
        storedMG = await transport.storedProperty(mg, slot: 1)
        XCTAssertEqual(storedWC, FujiEncoding.packI16(0))
        XCTAssertEqual(storedMG, FujiEncoding.packI16(0))
    }

    func testRefusedZeroIsReportedAsPartial() async {
        var faults = MockCameraFaults(); faults.invalidValueWriteCodes = [wc]
        let (camera, _) = await connected(faults)
        let result = await camera.slotWriter.push(settings: mono(wc: 0, mg: nil), name: "Neutral", toSlot: 1)
        XCTAssertEqual(result.outcome, .partiallyApplied)
        XCTAssertEqual(result.fields.first { $0.code == wc }?.outcome, .rejected(code: FujiPTP.responseInvalidDevicePropValue))
    }

    func testIgnoredZeroCannotPassVerification() async {
        let (camera, transport) = await connected()
        _ = await camera.slotWriter.push(settings: mono(wc: 3, mg: -2), name: "Tint", toSlot: 1)
        await transport.ignoreNextWrite(to: wc)
        let result = await camera.slotWriter.push(settings: mono(wc: 0, mg: 0), name: "Neutral", toSlot: 1)
        XCTAssertEqual(result.outcome, .partiallyApplied)
        XCTAssertTrue(result.mismatches.contains { $0.code == wc })
        let retained = await transport.storedProperty(wc, slot: 1)
        XCTAssertEqual(retained, FujiEncoding.packI16(30))
    }

    /// A zero on an axis the body has is written, since it clears a previous tint; a zero on an
    /// axis it lacks is not, and a non-zero one is still attempted. The X100V has both axes
    /// (Fujifilm's manual), so it gets the zero; the X-T3 has the warm–cool axis alone and is
    /// read-only, so its half is pinned through `encode`.
    func testSingleAxisAndFixedToningPoliciesRemainIntact() throws {
        let twoAxis = try XCTUnwrap(CameraModelRegistry.shared.model(withID: "X100V"))
        let zero = FujiPresetCodec.encode(mono(wc: 0, mg: 0), model: twoAxis, slot: .empty)
        XCTAssertEqual(zero.first { $0.code == wc }?.bytes, FujiEncoding.packI16(0))
        XCTAssertEqual(zero.first { $0.code == mg }?.bytes, FujiEncoding.packI16(0),
                       "the X100V has the axis, so the zero is written")

        let singleAxis = try XCTUnwrap(CameraModelRegistry.shared.model(withID: "X-T3"))
        let zeroSingle = FujiPresetCodec.encode(mono(wc: 0, mg: 0), model: singleAxis, slot: .empty)
        XCTAssertEqual(zeroSingle.first { $0.code == wc }?.bytes, FujiEncoding.packI16(0))
        XCTAssertFalse(zeroSingle.contains { $0.code == mg })
        let unsupported = FujiPresetCodec.encode(mono(wc: 0, mg: 3), model: singleAxis, slot: .empty)
        XCTAssertEqual(unsupported.first { $0.code == mg }?.bytes, FujiEncoding.packI16(30),
                       "a non-zero MG is still attempted on a single-axis body, with the advisory")
        for sim in [FilmSimulation.sepia, .classicChrome] {
            var recipe = mono(wc: 0, mg: 0); recipe.filmSimulation = sim
            let writes = FujiPresetCodec.encode(recipe, model: CameraModelRegistry.shared.demoModel, slot: .empty)
            XCTAssertFalse(writes.contains { $0.code == wc || $0.code == mg })
        }
    }

    /// End to end on an X-Processor 4 body with both axes: the zeros are written and verified.
    func testATwoAxisXProcessor4BodyTakesTheZeros() async {
        let (camera, transport) = await connected(MockCameraFaults(productName: "FUJIFILM X-T4"))
        XCTAssertEqual(camera.session.connected?.model?.id, "X-T4")
        let result = await camera.slotWriter.push(settings: mono(wc: 0, mg: 0), name: "Neutral", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied)
        let storedMG = await transport.storedProperty(mg, slot: 1)
        XCTAssertEqual(storedMG, FujiEncoding.packI16(0))
    }
}
