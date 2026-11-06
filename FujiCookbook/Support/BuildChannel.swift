import Foundation

/// How this copy of the app reached the device.
///
/// Separates a developer's own reports from a real user's when reading a shared problem or camera
/// report, and covers the two cases a Debug check can't: a Release build archived straight onto a
/// developer's device, and a TestFlight build.
///
/// Printed in the launch log line, the problem report's header, and the camera compatibility
/// report's `app` field.
enum BuildChannel: String {
    /// Built and run from Xcode with the Debug configuration.
    case debug
    /// A Release build installed directly — archived to a developer's device, not distributed.
    case local
    /// Distributed through TestFlight. Carries a sandbox receipt.
    case testFlight = "testflight"
    /// A real install from the App Store.
    case appStore = "app_store"

    static var current: BuildChannel {
        #if DEBUG
        return .debug
        #else
        // TestFlight installs get a `sandboxReceipt`; App Store installs get `receipt`. A
        // Release build side-loaded from Xcode has the URL but no file on disk at all, which is
        // the only way to tell it apart from a genuine App Store install.
        guard let receipt = Bundle.main.appStoreReceiptURL else { return .appStore }
        if receipt.lastPathComponent == "sandboxReceipt" { return .testFlight }
        return FileManager.default.fileExists(atPath: receipt.path) ? .appStore : .local
        #endif
    }
}
