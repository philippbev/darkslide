import Foundation

/// Why the iCloud (CloudKit) store couldn't be created when the user asked for sync, in the two
/// forms the app shows it.
struct CloudStoreFailure: Equatable {
    /// The error's own description. The app doesn't control that text and it isn't vetted for
    /// personal data, so only Settings ▸ Sync Details shows it, on this device.
    let deviceOnlyDescription: String

    /// Domain and code, from `AppLog.bounded`: the only form the log and a shared report carry.
    let boundedDescription: String

    init(_ error: any Error) {
        deviceOnlyDescription = String(describing: error)
        boundedDescription = AppLog.bounded(error)
    }
}
