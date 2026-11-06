import XCTest
@testable import FujiCookbook

/// The wait behind every connect that starts before the camera is plugged in.
@MainActor
final class DeviceArrivalWaitersTests: XCTestCase {

    /// Lets the waiting tasks run until `count` of them have registered.
    private func untilWaiting(_ count: Int, on arrivals: DeviceArrivalWaiters) async {
        while arrivals.count < count { await Task.yield() }
    }

    /// A stale reconnect racing a manual Connect: both are waiting, and both get the camera.
    func testAnArrivalResolvesEveryWaiter() async throws {
        let arrivals = DeviceArrivalWaiters()
        let first = Task { try await arrivals.wait(timeout: 10) }
        let second = Task { try await arrivals.wait(timeout: 10) }
        await untilWaiting(2, on: arrivals)

        let camera = FakeDiscoveredCamera()
        arrivals.succeedAllWaiters(with: camera)

        let firstFound = try await first.value
        let secondFound = try await second.value
        XCTAssertTrue(firstFound === camera)
        XCTAssertTrue(secondFound === camera)
        XCTAssertEqual(arrivals.count, 0)
    }

    func testAWaitWithNoArrivalEndsWithNoCameraDetected() async {
        let arrivals = DeviceArrivalWaiters()
        do {
            _ = try await arrivals.wait(timeout: 0.05)
            XCTFail("nothing arrived, so the wait must not return a camera")
        } catch {
            XCTAssertEqual(error as? CameraError, .noDeviceConnected)
        }
        XCTAssertEqual(arrivals.count, 0)
    }

    // MARK: - Cancellation

    /// Cancel tapped while nothing is plugged in: the wait ends now, not when its ten seconds run
    /// out.
    func testCancellingTheWaitingTaskEndsTheWait() async {
        let arrivals = DeviceArrivalWaiters()
        let waiting = Task { try await arrivals.wait(timeout: 10) }
        await untilWaiting(1, on: arrivals)

        waiting.cancel()

        do {
            _ = try await waiting.value
            XCTFail("a cancelled wait must not return a camera")
        } catch {
            XCTAssertTrue(error is CancellationError, "ended by the cancel, not the timeout: \(error)")
        }
        XCTAssertEqual(arrivals.count, 0)
    }

    /// The cancel lands before the task has started waiting.
    func testATaskCancelledBeforeItWaitsDoesNotWait() async {
        let arrivals = DeviceArrivalWaiters()
        let waiting = Task { try await arrivals.wait(timeout: 10) }
        waiting.cancel()

        do {
            _ = try await waiting.value
            XCTFail("a cancelled wait must not return a camera")
        } catch {
            XCTAssertTrue(error is CancellationError, "ended by the cancel, not the timeout: \(error)")
        }
        XCTAssertEqual(arrivals.count, 0)
    }

    /// Cancelling one waiter leaves the others waiting for the camera.
    func testCancellingOneWaiterLeavesTheOthers() async throws {
        let arrivals = DeviceArrivalWaiters()
        let cancelled = Task { try await arrivals.wait(timeout: 10) }
        let kept = Task { try await arrivals.wait(timeout: 10) }
        await untilWaiting(2, on: arrivals)

        cancelled.cancel()
        while arrivals.count > 1 { await Task.yield() }
        let camera = FakeDiscoveredCamera()
        arrivals.succeedAllWaiters(with: camera)

        let found = try await kept.value
        XCTAssertTrue(found === camera)
        let cancelledResult = await cancelled.result
        XCTAssertThrowsError(try cancelledResult.get())
    }
}
