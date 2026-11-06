import XCTest
@testable import FujiCookbook

/// The recovery copy a push reads before its first write is in the report, and on disk, before
/// that write — so a push the cable or the app cuts off still records what the slot held, which is
/// the push Undo Last Push exists for.
@MainActor
final class InterruptedPushRecordTests: XCTestCase {

    /// `CameraReportStore` is a real file in the App Group, and a report adopts the push history of
    /// the last one describing the same body — so without this, one test's pushes show up in the
    /// next test's report.
    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    private func connect() async -> (CameraServices, MockCameraTransport) {
        var faults = MockCameraFaults()
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        return (manager, transport)
    }

    func testTheRecoveryCopyIsRecordedBeforeTheFirstWriteAndOutlivesTheSession() async throws {
        let (manager, transport) = await connect()
        let slotBefore = manager.slotReader.slots.first { $0.index == 2 }
        let held = expectation(description: "the first content write is in flight")
        await transport.holdNextWrite(to: FujiPTP.PresetProp.filmSimulation.rawValue) { held.fulfill() }
        let push = Task {
            await manager.slotWriter.push(settings: RecipeSettings(filmSimulation: .velvia), name: "Interrupted", toSlot: 2)
        }
        await fulfillment(of: [held], timeout: 10)

        let provisional = try XCTUnwrap(manager.reports.report?.pushes?.last, "the entry exists before the first write")
        XCTAssertEqual(manager.reports.report?.pushes?.count, 1)
        XCTAssertEqual(provisional.slot, 2)
        XCTAssertEqual(provisional.outcome, .unknown)
        XCTAssertEqual(provisional.errorMessage, CameraCompatibilityReport.interruptedPushMessage)
        XCTAssertFalse(provisional.slotBefore?.isEmpty ?? true, "with the slot's bytes")
        if let name = slotBefore?.name { XCTAssertEqual(provisional.nameBefore, name, "and its name") }
        XCTAssertNotNil(SlotHistory(report: manager.reports.report).lastPushPriorBytes(forSlot: 2),
                        "so Undo Last Push has something to put back")

        // The session ends under the push, which is what a pulled cable does.
        await manager.connector.disconnect()
        await transport.releaseHeldWrite()
        let result = await push.value
        XCTAssertEqual(result.outcome, .unknown)
        XCTAssertEqual(manager.reports.report?.pushes?.count, 1,
                       "the interrupted push's entry stands, and nothing is added to a session that is over")
        XCTAssertEqual(manager.reports.report?.pushes?.last?.outcome, .unknown)
        XCTAssertNotNil(SlotHistory(report: manager.reports.report).lastPushPriorBytes(forSlot: 2))
    }

    func testTheProvisionalEntryIsOnDiskBeforeTheFirstWrite() async throws {
        try XCTSkipIf(CameraReportStore.latestURL == nil, "no App Group container in this test host")
        let (manager, transport) = await connect()
        let held = expectation(description: "the first content write is in flight")
        await transport.holdNextWrite(to: FujiPTP.PresetProp.filmSimulation.rawValue) { held.fulfill() }
        let push = Task {
            await manager.slotWriter.push(settings: RecipeSettings(filmSimulation: .velvia), name: "On disk", toSlot: 2)
        }
        await fulfillment(of: [held], timeout: 10)

        let stored = try XCTUnwrap(CameraReportStore.loadLatest()?.pushes?.last, "written before the first write, not at the end")
        XCTAssertEqual(stored.slot, 2)
        XCTAssertFalse(stored.slotBefore?.isEmpty ?? true)

        await transport.releaseHeldWrite()
        _ = await push.value
    }

    func testAFinishedPushReplacesItsProvisionalEntry() async {
        let (manager, _) = await connect()
        let result = await manager.slotWriter.push(settings: RecipeSettings(filmSimulation: .velvia), name: "Done", toSlot: 2)
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertEqual(manager.reports.report?.pushes?.count, 1, "one entry per push: the provisional one, finished in place")
        XCTAssertEqual(manager.reports.report?.pushes?.last?.outcome, .applied)
        XCTAssertFalse(manager.reports.report?.pushes?.last?.slotBefore?.isEmpty ?? true)
        XCTAssertNotEqual(manager.reports.report?.pushes?.last?.errorMessage, CameraCompatibilityReport.interruptedPushMessage)
    }
}
