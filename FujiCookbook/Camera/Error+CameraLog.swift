import Foundation

extension Error {

    /// `0x200A DeviceProp Not Supported` for a PTP refusal, the user-facing description otherwise:
    /// the one line the camera layer's log entries and report notes use for a failure.
    ///
    /// `bounded`, not `localizedDescription`, for anything that isn't ours: a `CocoaError` or
    /// `NSURLError` description names the path, URL or account it failed on, and this string goes
    /// into a log the user shares. `LogRedactionTests` pins that; the keepalive and resume probes
    /// are hardware-only and not unit-reachable, so the helper is the honest place to assert it.
    var cameraLogDescription: String {
        if let camera = self as? CameraError, case .ptpError(let code) = camera {
            return "\(PTPHex.code(code)) \(FujiPTP.responseName(code) ?? "")".trimmingCharacters(in: .whitespaces)
        }
        return (self as? CameraError)?.errorDescription ?? AppLog.bounded(self)
    }
}
