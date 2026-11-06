import Foundation
import Security

/// Minimal Keychain wrapper for storing secrets — one API key per AI provider, keyed by
/// `AIProvider.keychainAccount`, and the device secret `SerialHash` keys camera serials with.
///
/// Secrets must not live in `UserDefaults` (plain-text, backed up, readable). The Keychain keeps them
/// encrypted, and every item here is stored `ThisDeviceOnly`: never synced, and never restored to
/// another device from a backup.
///
/// **Do not add `kSecAttrService` to these queries.** Generic-password identity is
/// (service, account, access group); every key this app has ever written was stored with no service,
/// so a service-qualified query would match none of them and every existing user's key would
/// silently disappear. Distinct account strings already keep each provider's key apart.
enum KeychainStore {
    /// Shared Keychain group, declared in both targets' entitlements so the Share Extension can read
    /// the key the app stores.
    ///
    /// The entitlements spell it `$(AppIdentifierPrefix)$(APP_IDENTIFIER_BASE)`, which Xcode
    /// expands at build time into `TEAMID.<base>` — and `kSecAttrAccessGroup` is matched
    /// *literally* against that expanded string. Nothing prepends the team prefix on our behalf, so
    /// passing the bare group name names a group the app is not entitled to and every write comes
    /// back `errSecMissingEntitlement`: the key looks saved, because the typed value lives in
    /// `AISettings` for the rest of the session, and is gone by the next launch.
    private static let groupName = AppIdentifiers.base

    private static let accessGroups = AccessGroupResolver(groupName: groupName, teamPrefix: teamPrefix)

    /// The group every item is written to, or nil while the team prefix can't be read.
    private static var accessGroup: String? { accessGroups.group() }

    /// The team-prefixed access group, found by a probe and kept once the probe succeeds.
    ///
    /// A failed probe is not kept, so the next call probes again. There is no fallback group: the
    /// Keychain refuses a write to any group the build isn't entitled to, the Simulator's included
    /// (iOS 27.2 Simulator, 2026-11-05: the bare group name, a wrong team prefix and an unrelated
    /// group each returned `errSecMissingEntitlement`).
    final class AccessGroupResolver {
        private let groupName: String
        private let teamPrefix: () -> String?
        private let lock = NSLock()
        private var resolved: String?

        init(groupName: String, teamPrefix: @escaping () -> String?) {
            self.groupName = groupName
            self.teamPrefix = teamPrefix
        }

        /// `TEAMID.<groupName>`, or nil while the probe fails.
        func group() -> String? {
            lock.withLock {
                if let resolved { return resolved }
                guard let prefix = teamPrefix() else { return nil }
                resolved = "\(prefix).\(groupName)"
                return resolved
            }
        }
    }

    /// Ask the Keychain which group it files our items in by default, and take the leading component.
    ///
    /// Read at runtime rather than hardcoded: the team prefix is one more string that, if it ever
    /// changed, would cost every user their key with no visible failure. The probe works from either
    /// target — the extension's default group differs from the app's, but the prefix is the same.
    private static func teamPrefix() -> String? {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "keychain.teamPrefixProbe",
        ]

        var add = probe
        add[kSecValueData as String] = Data()
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecReturnAttributes as String] = true

        var item: CFTypeRef?
        var status = SecItemAdd(add as CFDictionary, &item)
        if status == errSecDuplicateItem {
            // Left behind by a launch that was killed between the add and the delete below.
            var lookup = probe
            lookup[kSecReturnAttributes as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            status = SecItemCopyMatching(lookup as CFDictionary, &item)
        }
        SecItemDelete(probe as CFDictionary)

        guard status == errSecSuccess,
              let attributes = item as? [String: Any],
              let group = attributes[kSecAttrAccessGroup as String] as? String,
              let prefix = group.split(separator: ".").first else { return nil }
        return String(prefix)
    }

    /// Store (or clear, when `value` is empty) a string under `key`.
    static func set(_ value: String, for key: String) {
        guard !value.isEmpty else {
            delete(key)
            return
        }
        guard let group = accessGroup else {
            AppLog.error(.app, "Keychain couldn't read the team prefix; not storing the key for \(key)")
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(for: key, in: group) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(for: key, in: group)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            log(SecItemAdd(add as CFDictionary, nil), "store the key for \(key)")
        } else {
            log(status, "update the key for \(key)")
        }
    }

    /// Read the string stored under `key`, or nil if absent.
    ///
    /// Falls back to a query that names no group, which searches every group the process is entitled
    /// to. That is what keeps a key readable at all if the entitlement is ever missing from a build.
    static func get(_ key: String) -> String? {
        accessGroup.flatMap { read(query(for: key, in: $0)) } ?? read(unscopedQuery(for: key))
    }

    /// The random secret stored under `key`, generated and stored the first time it is asked for.
    ///
    /// `byteCount` bytes from the system's secure generator, stored `ThisDeviceOnly`: never synced,
    /// never carried to another phone by a backup restore. Nil whenever the Keychain cannot answer
    /// for certain — only `errSecItemNotFound` means "make one". A device that is locked, a missing
    /// entitlement, an unreadable team prefix, or a stored value of the wrong size all return nil
    /// rather than a fresh secret, because a secret that changed between launches would silently
    /// change everything derived from it, and one that failed to store would change on the very
    /// next call. A `byteCount` below 1 is refused with nil.
    static func secret(for key: String, byteCount: Int) -> Data? {
        guard byteCount > 0 else {
            AppLog.error(.app, "Keychain was asked for a secret of \(byteCount) bytes for \(key); not making one")
            return nil
        }
        let group = accessGroup
        var (status, data) = group.map { copyData(query(for: key, in: $0)) } ?? (errSecItemNotFound, nil)
        if status == errSecItemNotFound { (status, data) = copyData(unscopedQuery(for: key)) }
        if status == errSecSuccess {
            guard let data, data.count == byteCount else {
                AppLog.error(.app, "Keychain holds a secret for \(key) of the wrong size; not using it")
                return nil
            }
            return data
        }
        guard status == errSecItemNotFound else {
            log(status, "read the secret for \(key)")
            return nil
        }
        guard let group else {
            AppLog.error(.app, "Keychain couldn't read the team prefix; not creating the secret for \(key)")
            return nil
        }

        var bytes = Data(count: byteCount)
        let generated = bytes.withUnsafeMutableBytes { buffer in
            // Never nil: `bytes` is `byteCount` long, and `byteCount` is positive.
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        guard generated == errSecSuccess else {
            log(generated, "generate the secret for \(key)")
            return nil
        }
        var add = query(for: key, in: group)
        add[kSecValueData as String] = bytes
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        if added == errSecSuccess { return bytes }
        if added == errSecDuplicateItem {
            // Another caller stored one between the read and the add. Theirs is the secret.
            let (again, stored) = copyData(unscopedQuery(for: key))
            return again == errSecSuccess && stored?.count == byteCount ? stored : nil
        }
        log(added, "store the secret for \(key)")
        return nil
    }

    // MARK: Private

    private static func query(for key: String, in group: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: group,
        ]
    }

    /// The same item, named without a group. For reads and deletes this spans every entitled group,
    /// so it is a superset of `query(for:in:)` — never use it to *write*, or the item lands in whichever
    /// group the Keychain picks by default rather than the one the extension reads.
    private static func unscopedQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
    }

    private static func read(_ base: [String: Any]) -> String? {
        let (status, data) = copyData(base)
        guard status == errSecSuccess, let data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func copyData(_ base: [String: Any]) -> (OSStatus, Data?) {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    private static func delete(_ key: String) {
        // Unscoped, so a key written by a build whose access group was wrong is cleared too — the
        // read falls back to that shape, and leaving one behind would make "clear this key" look
        // like it silently failed.
        log(SecItemDelete(unscopedQuery(for: key) as CFDictionary), "clear the key for \(key)")
    }

    /// A discarded `OSStatus` is exactly how a missing or misspelled `keychain-access-groups`
    /// entitlement would present: writes returning `errSecMissingEntitlement`, nothing logged, and
    /// a key that appears to save and is gone by the next launch. `errSecItemNotFound` on a delete
    /// is ordinary — there was nothing to remove.
    private static func log(_ status: OSStatus, _ action: String) {
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        AppLog.error(.app, "Keychain couldn't \(action) — \(detail) (\(status))")
    }
}
