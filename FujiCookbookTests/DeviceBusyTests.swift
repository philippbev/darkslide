import XCTest
@testable import FujiCookbook

/// `0x2019 Device Busy` comes with the record's remedy wherever the user meets it: a body left busy
/// by a conversion that never completed can answer it to every later command until it is switched
/// off and on (zgrimz/fujifilm-ptp-reference `docs/05-raw-conversion.md#when-a-conversion-doesnt-complete`). Without the remedy the message names a
/// protocol error and leaves the tester nothing to do but retry against a camera that stays busy.
@MainActor
final class DeviceBusyTests: XCTestCase {

    private let remedy = "turn it off and on again, then reconnect"

    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    private func connect(_ faults: MockCameraFaults) async -> CameraServices {
        var faults = faults
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    func testDeviceBusySaysToTurnTheCameraOffAndOn() {
        let message = CameraError.ptpError(code: FujiPTP.responseDeviceBusy).message
        XCTAssertTrue(message.hasPrefix("The camera reported a protocol error (0x2019) — Device Busy. "), message)
        XCTAssertTrue(message.contains(remedy), message)
    }

    /// The remedy is for a busy body only. A refusal with another answer, or with none, has a
    /// different cause, and power-cycling the camera would not fix it.
    func testOtherAnswersGetNoRemedy() {
        XCTAssertEqual(CameraError.ptpError(code: 0x2002).message,
                       "The camera reported a protocol error (0x2002) — General Error.")
        XCTAssertFalse(CameraError.slotSelectFailed(slot: 6, code: 0x201C).message.contains(remedy))
        XCTAssertFalse(CameraError.slotSelectFailed(slot: 1, code: nil).message.contains(remedy))
    }

    func testABusyConnectSaysToTurnTheCameraOffAndOn() async {
        let m = await connect(.busyXM5)

        guard case .failed(let message) = m.session.status else {
            return XCTFail("a busy C1 select ends the connect's slot walk; got \(m.session.status)")
        }
        XCTAssertTrue(message.contains("Device Busy (0x2019)"), message)
        XCTAssertTrue(message.contains(remedy), message)
    }

    func testABusyDevelopSaysToTurnTheCameraOffAndOn() async throws {
        let m = await connect(.busyXM5)

        let result = await m.conversion.cook(raf: RAFFixture.raf(),
                                             filename: "DSCF0001.RAF", settings: .neutral)

        XCTAssertFalse(result.success)
        let message = try XCTUnwrap(result.errorMessage)
        XCTAssertTrue(message.contains("0x2019"), message)
        XCTAssertTrue(message.contains(remedy), message)
    }
}
