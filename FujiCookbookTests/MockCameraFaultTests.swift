import XCTest
@testable import FujiCookbook

/// Tests for the fault injection itself.
///
/// These come first because everything downstream depends on them: the harness is about to be used
/// to characterize the write path's behavior on bodies I don't own, and a harness that lies about
/// what it did would produce a confident, wrong audit. So each fault is asserted to do exactly one
/// thing, and the no-fault case is asserted to do nothing at all.
final class MockCameraFaultTests: XCTestCase {

    /// Plain int16 passthrough properties — no encoding asymmetry, no conditional emission — so a
    /// test about *fault* behavior isn't also a test about the codec.
    private let plainProps: [FujiPTP.PresetProp] = [.highlightTone, .shadowTone, .color, .sharpness, .clarity]

    /// Opens on **C3**, which the mock leaves unprogrammed. Slots 1 and 2 are seeded with demo
    /// recipes, so a property that was never written still reads back a value there — which would
    /// make "the rejected write didn't land" indistinguishable from "it did".
    private func open(_ faults: MockCameraFaults) async throws -> MockCameraTransport {
        var faults = faults
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        try await transport.open()
        try await transport.writeProperty(FujiPTP.Prop.slotSelector, FujiEncoding.packU16(3))
        return transport
    }

    private func expect(_ expected: CameraError, _ body: () async throws -> Void,
                        _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected) but the call succeeded. \(message)", file: file, line: line)
        } catch let error as CameraError {
            XCTAssertEqual(error, expected, message, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error). \(message)", file: file, line: line)
        }
    }

    // MARK: The control

    /// A default-constructed `MockCameraFaults` must be indistinguishable from the mock before
    /// fault injection existed. If this fails, every other test in the suite is measuring the
    /// harness rather than the code.
    func testNoFaultsWritesAndReadsBackCleanly() async throws {
        let transport = try await open(MockCameraFaults())
        for (i, prop) in plainProps.enumerated() {
            try await transport.writeProperty(prop.rawValue, FujiEncoding.packI16(i * 10))
        }
        for (i, prop) in plainProps.enumerated() {
            let read = try await transport.readProperty(prop.rawValue)
            XCTAssertEqual(read.flatMap(FujiEncoding.decodeInt16), i * 10, "\(prop) didn't read back")
        }
    }

    // MARK: Rejected write partway through the property loop

    func testRejectWriteAtIndexFailsOnlyThatProperty() async throws {
        let transport = try await open(MockCameraFaults(rejectWriteAtIndex: 3))

        try await transport.writeProperty(plainProps[0].rawValue, FujiEncoding.packI16(11))
        try await transport.writeProperty(plainProps[1].rawValue, FujiEncoding.packI16(22))
        await expect(.ptpError(code: FujiPTP.responseInvalidDevicePropValue)) {
            try await transport.writeProperty(self.plainProps[2].rawValue, FujiEncoding.packI16(33))
        }
        // The loop keeps going after a non-fatal rejection, exactly as `push` step 4 does.
        try await transport.writeProperty(plainProps[3].rawValue, FujiEncoding.packI16(44))

        let landed = try await transport.readProperty(plainProps[1].rawValue)
        XCTAssertEqual(landed.flatMap(FujiEncoding.decodeInt16), 22, "writes before the rejection must stand")
        let rejected = try await transport.readProperty(plainProps[2].rawValue)
        XCTAssertNil(rejected, "a rejected write must not land — that's what makes it 'rejected' rather than 'written'")
        let after = try await transport.readProperty(plainProps[3].rawValue)
        XCTAssertEqual(after.flatMap(FujiEncoding.decodeInt16), 44, "writes after the rejection must still land")
    }

    // MARK: A property the body doesn't implement

    func testUnsupportedReadCodeAnswers200A() async throws {
        let transport = try await open(MockCameraFaults(unsupportedReadCodes: [FujiPTP.PresetProp.clarity.rawValue]))
        await expect(.ptpError(code: FujiPTP.responseDevicePropNotSupported)) {
            _ = try await transport.readProperty(FujiPTP.PresetProp.clarity.rawValue)
        }
        // Everything else still answers, which is the whole point: one missing property is not a
        // broken camera, and neither the walk nor a push treats it as one.
        try await transport.writeProperty(FujiPTP.PresetProp.sharpness.rawValue, FujiEncoding.packI16(20))
        let ok = try await transport.readProperty(FujiPTP.PresetProp.sharpness.rawValue)
        XCTAssertEqual(ok.flatMap(FujiEncoding.decodeInt16), 20)
    }

    // MARK: The cable comes out mid-push

    /// The precondition for the worst case in the write path: writes land, then the session drops,
    /// so the read-back throws. `push` reports the outcome as unknown, because the camera holds the
    /// writes it could not verify (PushAuditTests case G).
    func testDropSessionAfterWritesLeavesWritesLandedAndFailsTheReadBack() async throws {
        let transport = try await open(MockCameraFaults(dropSessionAfterWrites: 2))

        try await transport.writeProperty(plainProps[0].rawValue, FujiEncoding.packI16(11))
        try await transport.writeProperty(plainProps[1].rawValue, FujiEncoding.packI16(22))

        // The read-back is what a push does next, and it is now impossible.
        await expect(.disconnectedDuringOperation) {
            _ = try await transport.readProperty(self.plainProps[0].rawValue)
        }
        await expect(.disconnectedDuringOperation) {
            try await transport.writeProperty(self.plainProps[2].rawValue, FujiEncoding.packI16(33))
        }

        // Reopening proves the writes were real and are still on the camera — the app just can't
        // see them at the moment it has to report.
        try await transport.open()
        let survived = try await transport.readProperty(plainProps[1].rawValue)
        XCTAssertEqual(survived.flatMap(FujiEncoding.decodeInt16), 22,
                       "the bytes written before the drop are on the camera; only the app's ability to prove it was lost")
    }

    // MARK: A body with fewer slots than the assumed seven

    func testMaxSelectableSlotRejectsSlotsAboveTheLimit() async throws {
        let transport = try await open(MockCameraFaults(maxSelectableSlot: 5))
        for slot in 1...5 {   // C3 was already selected by `open`; re-selecting is harmless
            try await transport.writeProperty(FujiPTP.Prop.slotSelector, FujiEncoding.packU16(slot))
        }
        for slot in 6...7 {
            await expect(.ptpError(code: FujiPTP.responseDevicePropNotSupported), {
                try await transport.writeProperty(FujiPTP.Prop.slotSelector, FujiEncoding.packU16(slot))
            }, "C\(slot) doesn't exist on a five-slot body")
        }
    }

    // MARK: Identity

    /// The transport itself knows no firmware, like hardware; the faults' firmware reaches the app
    /// through `GetDeviceInfo`.
    @MainActor
    func testProductNameAndFirmwareComeFromFaults() async throws {
        var faults = MockCameraFaults.xT30III
        faults.firmwareVersion = "1.10"
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        XCTAssertEqual(transport.productName, "FUJIFILM X-T30 III")
        XCTAssertNil(transport.firmwareVersion)

        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        XCTAssertEqual(manager.session.connected?.productName, "FUJIFILM X-T30 III")
        XCTAssertEqual(manager.session.connected?.firmwareVersion, "1.10")
    }

    /// The seam for a body whose *encodings* differ from ours. Everything the mock stores came out
    /// of `FujiPresetCodec.encode`, so without this it can only ever answer values our decoder
    /// already understands — which makes the decoder's divergence handling unfalsifiable.
    func testRawReadValueOverridesWhatTheSlotHolds() async throws {
        var faults = MockCameraFaults.divergentWhiteBalance
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        try await transport.open()

        let value = try await transport.readProperty(FujiPTP.PresetProp.whiteBalance.rawValue)
        XCTAssertEqual(value.flatMap(FujiEncoding.decodeUInt16), 0x8099)
    }

    /// The file's house rule: default-constructed is a camera with no faults.
    func testDefaultFaultsOverrideNothing() async throws {
        let transport = MockCameraTransport(faults: MockCameraFaults(isInstant: true))
        try await transport.open()

        let value = try await transport.readProperty(FujiPTP.PresetProp.whiteBalance.rawValue)
        XCTAssertNotEqual(value.flatMap(FujiEncoding.decodeUInt16), 0x8099)
        XCTAssertNotNil(value, "the slot's own bytes still answer")
    }
}
