import XCTest
@testable import FujiCookbook

/// A connect to a camera on the cable, driven through `HeldCameraDiscovery` so the test decides
/// when the camera appears.
@MainActor
final class HardwareConnectTests: XCTestCase {

    /// A connection failure goes into the stored report, and the next test's connect would
    /// otherwise start from this one's.
    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    override func tearDown() {
        CameraReportStore.deleteLatest()
        super.tearDown()
    }

    private func instantDemo() -> MockCameraTransport {
        var faults = MockCameraFaults()
        faults.isInstant = true
        return MockCameraTransport(faults: faults)
    }

    /// Starts a hardware connect and returns once discovery is waiting for a camera.
    private func connectWhileDiscoveryWaits(_ manager: CameraServices,
                                            _ discovery: HeldCameraDiscovery) async -> Task<Void, Never> {
        let waiting = expectation(description: "discovery is waiting for a camera")
        discovery.onWait = { waiting.fulfill() }
        let connect = Task { await manager.connector.connectHardware() }
        await fulfillment(of: [waiting], timeout: 10)
        discovery.onWait = nil
        return connect
    }

    func testAConnectOpensTheCameraDiscoveryFinds() async {
        let discovery = HeldCameraDiscovery()
        let manager = CameraServices(discovery: { discovery })
        let connect = await connectWhileDiscoveryWaits(manager, discovery)
        XCTAssertEqual(manager.session.status, .connecting)

        let camera = FakeDiscoveredCamera()
        discovery.attach(camera)
        await connect.value

        XCTAssertEqual(manager.session.status, .connected)
        XCTAssertEqual(manager.session.connected?.isDemo, false)
        XCTAssertEqual(manager.reports.report?.camera.transport, "usb")
        XCTAssertEqual(camera.transportsMade, 1)
        XCTAssertFalse(manager.slotReader.slots.isEmpty, "and the connect read the slots")
    }

    func testACameraAlreadyAttachedConnectsWithoutWaiting() async {
        let discovery = HeldCameraDiscovery()
        discovery.attached = FakeDiscoveredCamera()
        let manager = CameraServices(discovery: { discovery })

        await manager.connector.connectHardware()

        XCTAssertEqual(manager.session.status, .connected)
        XCTAssertEqual(discovery.requestCount, 1)
    }

    /// The most common failure: nothing on the cable, or a camera in the wrong USB mode.
    func testACameraThatNeverAppearsIsRecordedAsADiscoveryFailure() async {
        let discovery = HeldCameraDiscovery()
        let manager = CameraServices(discovery: { discovery })
        let connect = await connectWhileDiscoveryWaits(manager, discovery)

        discovery.failWaits(with: CameraError.noDeviceConnected)
        await connect.value

        XCTAssertEqual(manager.session.status, .failed(CameraError.noDeviceConnected.message))
        XCTAssertFalse(manager.session.isConnected)
        XCTAssertEqual(manager.reports.report?.connectionFailures?.last?.stage, "discovery")
    }

    // MARK: - One connect at a time

    /// A second tap on Connect while the first is still looking for the camera.
    func testASecondConnectWaitsForTheOneUnderWay() async {
        let discovery = HeldCameraDiscovery()
        let manager = CameraServices(discovery: { discovery })
        let first = await connectWhileDiscoveryWaits(manager, discovery)
        XCTAssertTrue(manager.connector.isConnecting)

        let second = Task { await manager.connector.connectHardware() }
        await Task.yield()   // the second request reaches the connector before the camera appears
        let camera = FakeDiscoveredCamera()
        discovery.attach(camera)
        await first.value
        await second.value

        XCTAssertEqual(discovery.requestCount, 1, "the second request joined the first")
        XCTAssertEqual(camera.transportsMade, 1, "and one session was opened")
        XCTAssertEqual(manager.session.status, .connected)
        XCTAssertFalse(manager.connector.isConnecting)
    }

    // MARK: - Cancel

    /// Cancel tapped while nothing has appeared, and then the camera turns up anyway.
    func testACancelledConnectDoesNotOpenTheCameraThatAppearsAfterIt() async {
        let discovery = HeldCameraDiscovery()
        let manager = CameraServices(discovery: { discovery })
        let connect = await connectWhileDiscoveryWaits(manager, discovery)

        await manager.connector.cancelConnect()
        XCTAssertEqual(manager.session.status, .disconnected, "disconnected as soon as Cancel is tapped")
        let camera = FakeDiscoveredCamera()
        discovery.attach(camera)
        await connect.value

        XCTAssertEqual(manager.session.status, .disconnected)
        XCTAssertFalse(manager.session.isConnected)
        XCTAssertEqual(camera.transportsMade, 0, "the camera that appeared was never opened")
        XCTAssertNil(manager.connector.connectProgress)
    }

    /// The wait for a camera ends the way the browser ends it: with the cancel, or with the
    /// timeout that fires as Cancel is tapped. Neither is a failure to find one.
    func testACancelledConnectIsNotRecordedAsAFailure() async {
        for ending in [CancellationError() as Error, CameraError.noDeviceConnected] {
            CameraReportStore.deleteLatest()
            let discovery = HeldCameraDiscovery()
            let manager = CameraServices(discovery: { discovery })
            let connect = await connectWhileDiscoveryWaits(manager, discovery)

            await manager.connector.cancelConnect()
            discovery.failWaits(with: ending)
            await connect.value

            XCTAssertEqual(manager.session.status, .disconnected, "no failure card for \(ending)")
            XCTAssertNil(manager.reports.report?.connectionFailures, "and no failure in the report for \(ending)")
        }
    }

    /// The session open can't be interrupted, so a connect cancelled inside it finishes first,
    /// and a new connect waits until it has.
    func testAConnectCancelledInsideTheOpenIsWaitedOutBeforeTheNextOne() async {
        let discovery = HeldCameraDiscovery()
        let camera = FakeDiscoveredCamera()
        discovery.attached = camera
        let manager = CameraServices(discovery: { discovery })
        let held = expectation(description: "the session open is in progress")
        await camera.transport.holdNextOpen { held.fulfill() }
        let first = Task { await manager.connector.connectHardware() }
        await fulfillment(of: [held], timeout: 10)

        await manager.connector.cancelConnect()
        XCTAssertEqual(manager.connector.connectProgress, .cancelling)
        XCTAssertEqual(manager.session.status, .disconnected)
        XCTAssertTrue(manager.connector.isConnecting, "the Connect rows stay disabled")

        let second = Task { await manager.connector.connectHardware() }
        await Task.yield()   // the second request reaches the connector while the open is held
        XCTAssertEqual(discovery.requestCount, 1, "the second connect waits for the open to return")

        await camera.transport.releaseHeldOpen()
        await first.value
        await second.value

        XCTAssertEqual(discovery.requestCount, 2)
        XCTAssertEqual(manager.session.status, .connected, "and then connects")
        XCTAssertNil(manager.connector.connectProgress)
    }

    /// The Demo Camera's open waits on a timer, which a cancel ends where it stands.
    func testCancellingADemoConnectStopsItDuringTheOpen() async {
        let manager = CameraServices(discovery: { HeldCameraDiscovery() })
        let connect = Task { await manager.connector.connectDemo(using: MockCameraTransport()) }
        while manager.session.status != .connecting { await Task.yield() }

        await manager.connector.cancelConnect()
        await connect.value

        XCTAssertEqual(manager.session.status, .disconnected)
        XCTAssertFalse(manager.session.isConnected)
        XCTAssertNil(manager.connector.connectProgress)
    }

    /// A connect first tears down the session it replaces; a cancel during that teardown stops it
    /// there, rather than letting it start a session of its own once the teardown is done.
    func testACancelDuringTheTeardownOfTheOldSessionStopsTheConnect() async {
        let entries: [(String, (CameraConnector) async -> Void)] = [
            ("hardware", { await $0.connectHardware() }),
            ("demo", { await $0.connectDemo(using: self.instantDemo()) }),
        ]
        for (name, connectAgain) in entries {
            let discovery = HeldCameraDiscovery()
            discovery.attached = FakeDiscoveredCamera()
            let manager = CameraServices(discovery: { discovery })
            await manager.connector.connectDemo(using: self.instantDemo())
            XCTAssertTrue(manager.session.isConnected, "precondition: a session to tear down")
            let epoch = manager.session.epoch.current
            let connect = Task { await connectAgain(manager.connector) }
            while manager.session.epoch.current == epoch { await Task.yield() }   // the teardown has begun

            await manager.connector.cancelConnect()
            await connect.value

            XCTAssertEqual(manager.session.status, .disconnected, "\(name)")
            XCTAssertFalse(manager.session.isConnected, "\(name)")
            XCTAssertEqual(discovery.requestCount, 0, "\(name): stopped before looking for a camera")
        }
    }

    /// Cancel is for a connect under way; a connected camera stays connected.
    func testCancelWithNoConnectUnderWayChangesNothing() async {
        let discovery = HeldCameraDiscovery()
        discovery.attached = FakeDiscoveredCamera()
        let manager = CameraServices(discovery: { discovery })
        await manager.connector.connectHardware()

        await manager.connector.cancelConnect()

        XCTAssertEqual(manager.session.status, .connected)
        XCTAssertTrue(manager.session.isConnected)
    }

    /// Waiting is only for a connect still running: one that has finished leaves nothing to join.
    func testAConnectAfterTheLastOneFinishedStartsAfresh() async {
        let discovery = HeldCameraDiscovery()
        discovery.attached = FakeDiscoveredCamera()
        let manager = CameraServices(discovery: { discovery })

        await manager.connector.connectHardware()
        await manager.connector.disconnect()
        await manager.connector.connectHardware()

        XCTAssertEqual(discovery.requestCount, 2)
        XCTAssertEqual(manager.session.status, .connected)
    }
}
