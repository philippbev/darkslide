import Foundation

/// The identifiers every target derives from `APP_IDENTIFIER_BASE` in `Config/Base.xcconfig`,
/// read back from the running bundle's Info.plist so that changing the base in one place changes
/// it everywhere.
///
/// Each one names on-device state: the App Group holds the SwiftData store, the on-disk log, saved
/// camera reports and the settings suite, and the Keychain group holds the serial-hash secret. A
/// build that lost them would open an empty library and forget the secret, so a missing or unexpanded value
/// stops the app at launch instead of falling back to something that would do that silently.
enum AppIdentifiers {
    /// The shared identifier stem: the app's bundle id, and the Keychain access group before the
    /// team prefix (see `KeychainStore`).
    static let base = value(for: "FCAppIdentifierBase")

    /// The App Group that holds the library (see `SharedContainer`).
    static let appGroup = value(for: "FCAppGroupIdentifier")

    private static func value(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$(") else {
            preconditionFailure("\(key) is missing from Info.plist; see Config/Base.xcconfig")
        }
        return value
    }
}
