import XCTest
@testable import FujiCookbook

/// A slot walk that fails leaves the slot count unknown, and the app says so rather than falling
/// back to the registry's assumption: no slot range on the Camera card, and no push, which would
/// offer a four-bank X-M5 seven slots to choose from. Push comes back with the next walk that
/// finishes.
@MainActor
final class FailedSlotWalkTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    private func connect(_ faults: MockCameraFaults, to existing: CameraServices? = nil) async -> CameraServices {
        let manager = existing ?? CameraServices()
        var faults = faults
        faults.isInstant = true
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    func testAFailedWalkClaimsNoSlotCount() async {
        let m = await connect(.busyXM5)

        XCTAssertEqual(m.slotReader.walk, .failed)
        XCTAssertEqual(m.slotReader.effectiveSlotCount, 0, "not the registry's seven")
        XCTAssertNil(m.slotReader.probedSlotCount)
    }

    func testAFailedWalkBlocksPushAndSaysWhy() async throws {
        let m = await connect(.busyXM5)

        XCTAssertTrue(m.session.canPush, "precondition: the X-M5 is a body the app writes to")
        XCTAssertFalse(m.slotWriter.canPush)
        let reason = try XCTUnwrap(m.slotWriter.pushBlockReason)
        XCTAssertTrue(reason.contains("slots couldn't be read"), reason)
    }

    func testAFinishedWalkOffersWhatItFound() async {
        let m = await connect(.xM5)

        XCTAssertEqual(m.slotReader.walk, .finished(slotCount: 4))
        XCTAssertEqual(m.slotReader.effectiveSlotCount, 4)
        XCTAssertTrue(m.slotWriter.canPush)
        XCTAssertNil(m.slotWriter.pushBlockReason)
    }

    /// The block belongs to the walk that failed, not to the body: the next connect walks again,
    /// and a walk that finishes lifts it.
    func testTheNextFinishedWalkLiftsTheBlock() async {
        let m = await connect(.busyXM5)
        XCTAssertFalse(m.slotWriter.canPush, "precondition")

        await m.connector.disconnect()
        _ = await connect(.xM5, to: m)

        XCTAssertEqual(m.slotReader.walk, .finished(slotCount: 4))
        XCTAssertTrue(m.slotWriter.canPush)
    }

    /// A body the registry blocks keeps its own reason, whatever the walk did.
    func testABodyThatTakesNoWritesKeepsItsOwnReason() async {
        let m = await connect(.noSlotProtocolBody)

        XCTAssertFalse(m.slotWriter.canPush)
        XCTAssertEqual(m.slotWriter.pushBlockReason, m.session.pushBlockReason)
    }
}
