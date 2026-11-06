/// How the recipe store came up at launch. The sync preference is read once, when the store is
/// created, so this holds for the whole run, whatever the preference says later.
enum CloudStoreState: Equatable {
    /// Sync was off at launch.
    case local
    /// The store syncs through iCloud (CloudKit).
    case cloudKit
    /// Sync was on, but the CloudKit store couldn't be created, so the store is local.
    case fellBack(CloudStoreFailure)

    var isCloudKit: Bool { self == .cloudKit }
}
