import Foundation

/// Finds the camera a hardware connect opens, and reports when an attached camera goes away or
/// the system pauses device I/O. `CameraDeviceBrowser` in the app; tests supply their own, so a
/// hardware connect can run against `MockCameraTransport`.
@MainActor
protocol CameraDiscovery: AnyObject {
    /// The first attached camera, waiting up to `timeout` for one to appear when none is attached
    /// yet. Throws `CameraError.noDeviceConnected` when none appears, or the authorization error
    /// that kept the camera from being seen. The wait for a camera to appear ends with
    /// `CancellationError` as soon as the calling task is cancelled.
    func firstCamera(timeout: TimeInterval) async throws -> any DiscoveredCamera

    /// The two ImageCaptureCore grants, as words, for a connection-failure report.
    var authorizationSummary: (control: String, contents: String) { get }

    /// Called for every attached camera that goes away, not only the connected one: discovery has
    /// no notion of which camera is connected, so the connector checks identity before reacting.
    var onDeviceRemoved: (@MainActor (any DiscoveredCamera) -> Void)? { get set }
    /// Called when the system pauses device I/O for app backgrounding.
    var onSuspend: (@MainActor () -> Void)? { get set }
    /// Called when the system resumes device I/O after `onSuspend`.
    var onResume: (@MainActor () -> Void)? { get set }
}

extension CameraDiscovery {
    /// The first attached camera, waiting up to ten seconds for one to appear.
    func firstCamera() async throws -> any DiscoveredCamera {
        try await firstCamera(timeout: 10)
    }
}

/// A camera discovery found: the identity recovery compares to tell the same body from a different
/// one, and the transport that talks to it.
@MainActor
protocol DiscoveredCamera: AnyObject {
    var name: String? { get }
    var usbVendorID: Int32 { get }
    var usbProductID: Int32 { get }

    func makeTransport() -> CameraTransport
}
