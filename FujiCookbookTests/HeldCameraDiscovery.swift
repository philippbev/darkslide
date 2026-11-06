import Foundation
@testable import FujiCookbook

/// Camera discovery the test answers by hand. With no camera attached, each wait is held until the
/// test attaches one or fails the wait, the way the browser holds one until `didAdd` or its
/// timeout. The timeout itself is ignored: the test decides when a wait ends.
///
/// Cancellation is ignored too, unlike the browser's wait, so a test can answer after a connect
/// was cancelled: the camera that appears just as Cancel is tapped.
@MainActor
final class HeldCameraDiscovery: CameraDiscovery {
    /// Returned at once, as the browser returns a camera it already knows.
    var attached: (any DiscoveredCamera)?
    /// How many times a connect has asked for a camera.
    private(set) var requestCount = 0
    /// Called when a wait begins, so a test can act while discovery is still waiting.
    var onWait: (() -> Void)?
    private var waiting: [CheckedContinuation<any DiscoveredCamera, Error>] = []

    var authorizationSummary: (control: String, contents: String) { ("authorized", "authorized") }
    var onDeviceRemoved: (@MainActor (any DiscoveredCamera) -> Void)?
    var onSuspend: (@MainActor () -> Void)?
    var onResume: (@MainActor () -> Void)?

    func firstCamera(timeout: TimeInterval) async throws -> any DiscoveredCamera {
        requestCount += 1
        if let attached { return attached }
        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            onWait?()
        }
    }

    /// A camera is plugged in: every held wait gets it.
    func attach(_ camera: any DiscoveredCamera) {
        attached = camera
        let held = waiting
        waiting.removeAll()
        for continuation in held { continuation.resume(returning: camera) }
    }

    /// Every held wait ends with `error`, as a wait that times out ends with `noDeviceConnected`.
    func failWaits(with error: Error) {
        let held = waiting
        waiting.removeAll()
        for continuation in held { continuation.resume(throwing: error) }
    }
}

/// A camera on the cable, played by `MockCameraTransport`.
@MainActor
final class FakeDiscoveredCamera: DiscoveredCamera {
    let transport: MockCameraTransport
    /// How many transports a connect has asked this camera for.
    private(set) var transportsMade = 0

    var name: String? { transport.productName }
    let usbVendorID: Int32 = 0x1234
    let usbProductID: Int32 = 0x5678

    /// A recognized body the app reads and does not write to, so a connect walks its slots without
    /// remembering it for the Chapter screen.
    init(faults: MockCameraFaults = .readOnlyWithSlots) {
        var faults = faults
        faults.isInstant = true
        faults.presentsAsHardware = true
        transport = MockCameraTransport(faults: faults)
    }

    func makeTransport() -> CameraTransport {
        transportsMade += 1
        return transport
    }
}
