import XCTest
@testable import FujiCookbook

/// Which bodies get the slot walk, decided by what the selector (`0xD18C`) answers at connect rather
/// than by the registry alone. A trusted writable entry walks on the registry's word; a body the
/// registry blocks is swept; every other body is walked when the selector answers a bank number and
/// swept otherwise. Asserted on the traffic the mock recorded, not on log text.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/01-transport.md#response-codes`, `docs/07-cameras.md#x-t20`, `docs/07-cameras.md#summary`.
@MainActor
final class WalkGatingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    private func connect(_ faults: MockCameraFaults) async -> (CameraServices, MockCameraTransport) {
        var faults = faults
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        return (manager, transport)
    }

    /// Slot selects (`SetDevicePropValue 0xD18C`) in the connect's trace.
    private func selects(_ m: CameraServices) -> Int {
        (m.reports.report?.transactions ?? []).filter { $0.operation == "0x1016" && $0.parameters.first == "0xD18C" }.count
    }

    /// An X-H1: `.untested`, with the registry expecting no bank block. The mock answers the
    /// selector, so the walk runs and finds seven banks.
    func testAnUntestedBodyWhoseSelectorAnswersIsWalked() async throws {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-H1", firmwareVersion: "2.01"))
        XCTAssertEqual(m.session.model?.writeSupport, .untested, "precondition")
        XCTAssertFalse(m.session.model?.supportsSlotProtocol ?? true, "precondition: the registry expected none")
        let observed = try XCTUnwrap(m.session.connected?.observed.slotRead)
        XCTAssertEqual(observed.selector, .value(1))
        XCTAssertEqual(observed.walk, .finished(banks: 7, allRead: true))
        XCTAssertEqual(observed.selectorRestored, true)
        XCTAssertEqual(m.slotReader.slots.count, 7)
        XCTAssertEqual(selects(m), 7 + 1, "one select per bank, plus the restore")
        XCTAssertTrue(m.session.maySelectSlots)
        XCTAssertTrue(m.session.connected?.isWritable ?? false, "granted on what it answered")
    }

    /// The same body answering `0x200A` to the selector, as the X-T20 did: the sweep, and no select.
    func testAnUntestedBodyWhoseSelectorIsUnsupportedIsSwept() async throws {
        let (m, t) = await connect(MockCameraFaults(productName: "FUJIFILM X-H1", firmwareVersion: "2.01",
                                                    unsupportedReadCodes: [FujiPTP.Prop.slotSelector, FujiPTP.Prop.presetName]))
        let observed = try XCTUnwrap(m.session.connected?.observed.slotRead)
        XCTAssertEqual(observed.selector, .unsupported)
        XCTAssertEqual(observed.walk, .sweptReadOnly)
        XCTAssertEqual(m.slotReader.walk, .sweptReadOnly)
        XCTAssertEqual(selects(m), 0)
        let writes = await t.totalWriteCount
        XCTAssertEqual(writes, 0, "nothing is written to a body whose block isn't there")
        XCTAssertFalse(m.session.maySelectSlots)
    }

    /// An `.untested` body with the block expected (a GFX100 II) whose selector read fails for
    /// another reason: that says nothing about the block, so it is swept rather than selected.
    func testAnUntestedBodyWhoseSelectorReadFailsIsSwept() async throws {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM GFX100 II", firmwareVersion: nil,
                                                    readResponseCodes: [FujiPTP.Prop.slotSelector: 0x2002]))
        let observed = try XCTUnwrap(m.session.connected?.observed.slotRead)
        guard case .failed = observed.selector else { return XCTFail("expected a failed read, got \(observed.selector)") }
        XCTAssertEqual(observed.walk, .sweptReadOnly)
        XCTAssertEqual(selects(m), 0, "no select is sent on a body whose selector didn't answer")
    }

    /// A select answered OK and not taken stops the walk where the read-back first disagrees, and
    /// the evidence says so. The body is parked on C1, so the ignored select of C1 reads back as C1
    /// and passes by coincidence; C2 is where the selector shows it never moved.
    func testAnIgnoredSelectStopsAnUntestedBodyWhereTheReadBackDisagrees() async throws {
        var faults = MockCameraFaults.readOnlyWithSlots
        faults.silentlyIgnoredWriteCodes = [FujiPTP.Prop.slotSelector]
        let (m, _) = await connect(faults)
        let observed = try XCTUnwrap(m.session.connected?.observed.slotRead)
        XCTAssertEqual(observed.walk, .stopped(selectIgnoredAt: 2))
        XCTAssertEqual(m.slotReader.walk, .finished(slotCount: 1))
        XCTAssertEqual(selects(m), 2, "C1 by coincidence, C2 caught, then nothing")
    }

    /// The GFX100S guard: a trusted writable entry walks on the registry's word. A selector that
    /// won't read does not stop the walk from trying C1, as it did before.
    func testATrustedWritableBodyWalksWhateverTheSelectorAnswers() async throws {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-T50", firmwareVersion: "1.32",
                                                    readResponseCodes: [FujiPTP.Prop.slotSelector: 0x2002]))
        let observed = try XCTUnwrap(m.session.connected?.observed.slotRead)
        guard case .failed = observed.selector else { return XCTFail("expected a failed read, got \(observed.selector)") }
        XCTAssertEqual(selects(m), 1, "C1 was selected; its read-back could not confirm it, so the walk stopped there")
        XCTAssertEqual(observed.walk, .stopped(selectIgnoredAt: 1))
        XCTAssertTrue(m.session.maySelectSlots, "the registry's word stands for a trusted writable body")
    }

    /// A `.blocked` entry is swept before any selector read through the walk: traffic as before.
    func testABlockedBodyIsSweptWithoutASelect() async throws {
        let (m, t) = await connect(.noSlotProtocolBody)
        let observed = try XCTUnwrap(m.session.connected?.observed.slotRead)
        XCTAssertEqual(observed.walk, .sweptReadOnly)
        XCTAssertEqual(observed.selector, .notRead, "the sweep reads 0xD18C in its own loop, not through the walk")
        XCTAssertEqual(selects(m), 0)
        let writes = await t.totalWriteCount
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(m.session.maySelectSlots)
    }

    /// A heuristic match walks when the selector answers, as it did on the matched entry's word.
    func testAHeuristicMatchIsWalkedWhenTheSelectorAnswers() async throws {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-T50 TETHER", firmwareVersion: nil))
        XCTAssertEqual(m.session.connected?.identification.confidence, "heuristic", "precondition")
        let observed = try XCTUnwrap(m.session.connected?.observed.slotRead)
        XCTAssertEqual(observed.selector, .value(1))
        XCTAssertEqual(observed.walk, .finished(banks: 7, allRead: true))
        XCTAssertEqual(m.slotReader.slots.count, 7)
        XCTAssertTrue(m.session.maySelectSlots)
    }
}
