import XCTest
@testable import FujiCookbook

/// Some recipes list High ISO NR as "Noise Reduction". The app once kept that value in a field of
/// its own, one no camera has: the push skipped it and the editor dropped it. A Noise Reduction
/// without a High ISO NR now reads as one, wherever the settings come from.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#0xd1a1-high-iso-noise-reduction`.
@MainActor
final class LegacyNoiseReductionTests: XCTestCase {

    /// A push writes a camera report, and a report adopts the history of the last one describing
    /// the same body — the same isolation `PushAuditTests` needs.
    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    func testANoiseReductionAloneBecomesHighISONR() {
        let settings = RecipeSettings(noiseReduction: -2)
        XCTAssertEqual(settings.highISONR, -2)
        XCTAssertNil(settings.noiseReduction)
    }

    /// A recipe that listed both names keeps both values: High ISO NR is what the camera gets, and
    /// the other is kept rather than guessed between.
    func testAHighISONRKeepsTheNoiseReductionBesideIt() {
        let settings = RecipeSettings(highISONR: -1, noiseReduction: -3)
        XCTAssertEqual(settings.highISONR, -1)
        XCTAssertEqual(settings.noiseReduction, -3)
    }

    /// The path a stored recipe, a shared file, a backup and an iCloud record all take.
    func testAStoredNoiseReductionDecodesAsHighISONR() throws {
        let settings = try JSONDecoder().decode(RecipeSettings.self,
                                                from: Data(#"{"noiseReduction": -4}"#.utf8))
        XCTAssertEqual(settings.highISONR, -4)
        XCTAssertNil(settings.noiseReduction)
    }

    /// The scanner's payload keeps a `noiseReduction` property for a model that answers under the
    /// older name whether or not the schema offers it.
    func testAScannedNoiseReductionBecomesHighISONR() throws {
        let payload = try JSONDecoder().decode(AIRecipePayload.self,
                                               from: Data(#"{"noiseReduction": -2}"#.utf8))
        let settings = payload.toPortable(fallbackName: "Scanned").settings
        XCTAssertEqual(settings.highISONR, -2)
        XCTAssertNil(settings.noiseReduction)
    }

    /// What the fold is for: the value reaches the camera as `0xD1A1`, where before the push skipped
    /// it as a setting no body has.
    func testAPushWritesTheValueAsHighISONR() async throws {
        let stored = try JSONDecoder().decode(
            RecipeSettings.self,
            from: Data(#"{"filmSimulation": "CLASSIC_NEG", "noiseReduction": -2}"#.utf8))
        var faults = MockCameraFaults()
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        let services = CameraServices()
        await services.connector.connectDemo(using: transport)

        let result = await services.slotWriter.push(settings: stored, name: "Old NR", toSlot: 1)

        XCTAssertEqual(result.outcome, .applied)
        try await transport.writeProperty(FujiPTP.Prop.slotSelector, FujiEncoding.packU16(1))
        let raw = try await transport.readProperty(FujiPTP.PresetProp.highISONR.rawValue)
            .flatMap(FujiEncoding.decodeUInt16)
        XCTAssertEqual(raw.flatMap { FujiEncoding.nrDecode[$0] }, -2)
    }
}
