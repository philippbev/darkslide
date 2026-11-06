import Foundation

/// Logging for the camera connection layer: a façade over ``AppLog`` writing to
/// `AppLog.Category.camera`, through which every connect/discover/open/keepalive/reconnect/close
/// event should go. New code outside `Camera/` should call `AppLog` directly; this stays because
/// the camera layer's call sites read better without the category argument repeated at every one
/// of them, and because `ConnectionLogView` is a camera-only screen.
@MainActor
enum CameraLog {
    static func info(_ message: String) {
        AppLog.info(.camera, message)
    }

    /// A non-fatal-but-worth-flagging event (e.g. a keepalive ping failed, a reconnect attempt
    /// failed). Distinct from throwing `CameraError` — this just marks the log entry so it stands
    /// out when scanning the Connection Log.
    static func error(_ message: String) {
        AppLog.error(.camera, message)
    }
}
