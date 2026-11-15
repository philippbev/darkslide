import Foundation
import CryptoKit

/// How a camera's serial number is recorded anywhere the app stores or shares it: as a keyed hash,
/// never as the serial.
///
/// HMAC-SHA256 under a random 256-bit key generated on this phone the first time a camera connects,
/// truncated to the first 8 bytes and written as 16 lowercase hex characters. The key is in the
/// Keychain, device-only, and never appears in a report, a log or an export, so a report can be
/// posted publicly: a Fujifilm serial is about eight characters, and without the key there is
/// nothing to check a guess against. The price is that one body hashes differently on two phones.
/// On one phone it is stable, which is all the app's own comparisons need: recognizing the camera
/// a stored report, Camera Test or recovery copy was about.
///
/// Earlier builds recorded an unkeyed hash: SHA-256 over a salt compiled into every copy of the
/// app, which anyone can reverse by enumerating serials. Those values are still on testers'
/// phones, so `legacy` exists for one purpose: recognizing them as the camera connected now.
enum SerialHash {
    /// `camera.serialHashScheme` beside a keyed hash. A hash with no scheme is unkeyed, and never
    /// leaves the device.
    static let keyedScheme = "hmac-sha256"

    /// Its own account, apart from the retired AI key accounts `RetiredAIData` deletes at launch:
    /// erasing this key would make every camera the app has met look like a stranger.
    static let keychainAccount = "camera.serialHashKey"

    /// The hash to record for the camera connected now, under this phone's key (`deviceKey`).
    /// Remembers that body's legacy hash for `same` until the app quits.
    ///
    /// When the Keychain cannot produce the key there is no `key` to pass, and the caller records
    /// no hash at all rather than the unkeyed one: the body is then matched by name and USB
    /// identity alone, as a body that refuses `GetDeviceInfo` is.
    static func recordConnected(serial: String, key: SymmetricKey) -> String {
        let hash = keyed(serial, key: key)
        lock.withLock { legacyByKeyed[hash] = legacy(serial) }
        return hash
    }

    static func keyed(_ serial: String, key: SymmetricKey) -> String {
        hex(Data(HMAC<SHA256>.authenticationCode(for: Data(serial.utf8), using: key)))
    }

    /// The unkeyed hash earlier builds recorded. Computed only to compare with a stored value, and
    /// never written.
    static func legacy(_ serial: String) -> String {
        hex(Data(SHA256.hash(data: Data(("fuji-cookbook-serial:" + serial).utf8))))
    }

    /// Whether two recorded hashes name the same body, with `==`'s answer when either is nil.
    ///
    /// Equal hashes do. So does a legacy hash beside the keyed hash of the same serial — but that
    /// pairing is known only for a body connected since launch, because computing the legacy hash
    /// takes the serial. That is exactly when a stored record has to be recognized: the camera it
    /// is about has just been plugged in, and the caller then writes the keyed hash over it.
    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return a == b }
        if a == b { return true }
        return lock.withLock { legacyByKeyed[a] == b || legacyByKeyed[b] == a }
    }

    /// This phone's key, from the Keychain, created the first time. Cached once it loads; a failure
    /// is not cached, so the next connect asks again.
    static var deviceKey: SymmetricKey? {
        lock.withLock {
            if let cachedKey { return cachedKey }
            guard let secret = KeychainStore.secret(for: keychainAccount, byteCount: 32) else { return nil }
            cachedKey = SymmetricKey(data: secret)
            return cachedKey
        }
    }

    // MARK: Private

    private static let lock = NSLock()
    private static var cachedKey: SymmetricKey?
    /// Keyed hash to legacy hash, for each body connected since launch. Memory only.
    private static var legacyByKeyed: [String: String] = [:]

    private static func hex(_ digest: Data) -> String {
        digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
