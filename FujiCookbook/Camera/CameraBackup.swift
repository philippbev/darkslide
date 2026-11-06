import Foundation

/// A copy of every custom slot on one camera, in the camera's own bytes.
///
/// ## Why it exists
///
/// A backup is worth having only with a restore attached to it — without one, recovery is a tester
/// mailing a file of hex and retyping settings by hand — and `SlotWriter.restore` is
/// that restore. The bytes also sit in the compatibility report, but that is a diagnostic the next
/// connect overwrites (`docs/camera-compatibility-report.md` §"Why there is no separate backup file"
/// has the history of the decision).
///
/// ## Why a file the user holds, rather than a store the app keeps
///
/// A store in the app would cost a retention policy, a Clear Diagnostics branch, a second
/// attachment, and its own paragraph in the privacy policy — four more places to be wrong about the
/// user's own creative work. An exported file has none of those. It
/// lives where the user put it, for as long as they want it, and the privacy surface is "a file you
/// exported", which the policy already covers.
///
/// It also outlives the two things the in-app copies don't: `slots.reads` is overwritten on the next
/// connect, and `pushes[].slotBefore` — the free per-slot undo — is discarded by Clear Diagnostics,
/// which is the button a careful person presses right after sharing a report.
///
/// ## What it is not
///
/// It is not a recipe file. `.fujirecipe` round-trips through `RecipeSettings`, which is a superset
/// of *recipe* fields and carries none of the housekeeping run; a backup that narrowed a slot to the
/// fields the app happens to model would not be a backup. This holds raw property bytes, and the
/// decoded summary alongside them is for a human reading the file, never for the restore.
struct CameraBackup: Codable, Equatable, Identifiable {
    static let schemaName = "fuji-camera-backup"
    static let currentVersion = 1

    var schema: String = CameraBackup.schemaName
    var version: Int = CameraBackup.currentVersion
    var capturedAt: Date
    var camera: Camera
    var slots: [Slot]

    /// Stable enough for a single presented sheet; a backup is identified by when it was taken.
    var id: Date { capturedAt }

    struct Camera: Codable, Equatable {
        var productName: String
        var modelID: String?
        var firmwareVersion: String?
        /// The same keyed hash the compatibility report records (`SerialHash`), so a recovery copy
        /// can be matched to the body it came from. Restoring onto a *different* body is the mistake
        /// this catches. Only on the phone that took it: another phone hashes the same body
        /// differently.
        var serialHash: String?
        /// `hmac-sha256` (`SerialHash.keyedScheme`) beside a keyed hash, as in the report. Absent
        /// beside a hash recorded by an earlier build, which is unkeyed and reversible: a recovery
        /// copy is never rewritten, so it keeps that hash on the device to find its camera by, and
        /// `forSharing` leaves it out of every export. Optional, so a file from an earlier build
        /// still decodes.
        var serialHashScheme: String?

        /// Whether this recovery copy came from the connected body. Registry ids decide when both
        /// sides have one; otherwise the product names, which both always carry. A copy taken while
        /// a body was unlisted has no id, and the same body gains one when a later build lists it,
        /// so ids alone would refuse every copy from before the update as a different camera.
        func isFromBody(productName: String, registryModelID: String?) -> Bool {
            if let modelID, let registryModelID { return modelID == registryModelID }
            return self.productName == productName
        }
    }

    struct Slot: Codable, Equatable {
        var index: Int
        var name: String?
        var occupied: Bool
        /// Property code (`"0xD192"`) to raw bytes (`"0400"`). The restore's only input.
        var properties: [String: String]
        /// For a person reading the file. Never read back — a restore works from `properties`.
        var summary: String?
    }

    // MARK: Capture

    /// Take a backup from slots the app has already read. Pure: no camera traffic, because
    /// `SlotReader.refresh()` has already done all of it.
    static func capture(slots: [CameraSlot], productName: String, modelID: String?,
                        firmwareVersion: String?, serialHash: String?,
                        serialHashScheme: String?) -> CameraBackup {
        CameraBackup(
            // Truncated to the whole second, for the same reason the compatibility report truncates
            // its timestamps: ISO 8601 encoding drops the fraction, so an untruncated date makes the
            // file decode to something that isn't equal to what was written.
            capturedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
            camera: Camera(productName: productName, modelID: modelID,
                           firmwareVersion: firmwareVersion, serialHash: serialHash,
                           serialHashScheme: serialHashScheme),
            slots: slots.map { slot in
                Slot(index: slot.index,
                     name: slot.resolvedName,
                     occupied: slot.isOccupied,
                     properties: Dictionary(uniqueKeysWithValues: slot.rawProperties.map {
                         (PTPHex.code($0.key), PTPHex.bytes($0.value))
                     }),
                     summary: slot.isOccupied ? slot.displayName : nil)
            })
    }

    /// Why a slot that was empty can never be made empty again, in one sentence.
    ///
    /// Lives here because this is where the rule is enforced, but it is needed wherever a write to
    /// an empty slot is offered or an undo of one is refused — the write pass's slot picker and its
    /// restore step both say it.
    static let slotCannotBeEmptied =
        "A slot can't be emptied again over USB — there's no operation for it, and writing a default "
        + "into one would be inventing an entry rather than removing it."

    /// The bytes for one slot, back in the shape `restore` wants.
    ///
    /// Returns nil for a slot with nothing in it. **A slot that was empty cannot be restored to
    /// empty**: the protocol as implemented has no clear-slot operation, and seeding it would write
    /// PROVIA into a slot the user had deliberately left alone — inventing an entry in the name of
    /// putting one back. The caller says it skipped, and skips.
    func properties(forSlot index: Int) -> [UInt16: Data]? {
        guard let slot = slots.first(where: { $0.index == index }), slot.occupied,
              !slot.properties.isEmpty else { return nil }
        guard let out = try? CameraBackupValidation.properties(slot.properties), !out.isEmpty else { return nil }
        return out
    }

    // MARK: Serialization

    /// This backup as it may leave the device: without a serial hash that carries no scheme.
    ///
    /// Such a hash was recorded by a build that hashed serials unkeyed, and anyone can reverse it.
    /// It stays in the recovery copy on the phone, where `GuidedRecoveryRecord.matches` still finds
    /// its camera by it; it goes no further. A file without it restores all the same, because an
    /// imported backup is matched to the connected body by model, not by hash.
    var forSharing: CameraBackup {
        guard camera.serialHash != nil, camera.serialHashScheme == nil else { return self }
        var copy = self
        copy.camera.serialHash = nil
        return copy
    }

    var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Validated before anything is offered for restore. A wrong-schema or too-new file fails here
    /// rather than halfway through writing to someone's camera.
    static func decode(_ data: Data) throws -> CameraBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // The envelope first, on its own. Decoding the whole type up front means the overwhelmingly
        // likely mistake — picking a `.fujirecipe` file, which is also JSON and also lives in Files
        // — fails on a missing `capturedAt` key and surfaces a raw `keyNotFound` to the user. The
        // useful sentence is "that's a recipe, not a backup", and it needs the schema to say it.
        struct Envelope: Decodable { var schema: String?; var version: Int? }
        let envelope = (try? decoder.decode(Envelope.self, from: data)) ?? Envelope()
        guard envelope.schema == schemaName else {
            throw CameraBackupError.wrongSchema(found: envelope.schema ?? "an unrecognised file")
        }
        guard (envelope.version ?? 0) <= currentVersion else {
            throw CameraBackupError.tooNew(version: envelope.version ?? 0)
        }
        guard envelope.version == currentVersion else {
            throw CameraBackupError.invalidContents("The backup format version is missing or unsupported.")
        }
        let backup = try decoder.decode(CameraBackup.self, from: data)
        var indices: Set<Int> = []
        for slot in backup.slots {
            try CameraBackupValidation.slot(slot.index)
            guard indices.insert(slot.index).inserted else {
                throw CameraBackupError.invalidContents("Slot C\(slot.index) appears more than once.")
            }
            let properties = try CameraBackupValidation.properties(slot.properties)
            guard !slot.occupied || !properties.isEmpty else {
                throw CameraBackupError.invalidContents("Occupied slot C\(slot.index) has no saved settings.")
            }
        }
        return backup
    }

    var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let body = (camera.modelID ?? camera.productName)
            .replacingOccurrences(of: " ", with: "-")
        return "fuji-cookbook-slots-\(body)-\(formatter.string(from: capturedAt)).json"
    }
}

/// The observed final state of a restore, kept separately from its command outcomes. A refused
/// no-op remains evidence even when a fresh reading proves that every original setting is back.
struct RestoreVerification: Codable, Equatable {
    /// Whether the slot holds the original again, from a fresh reading after the restore.
    /// Persisted by its raw value.
    enum Outcome: String, Codable {
        case applied
        case partiallyApplied
        case couldNotVerify
        case notWritten
    }

    struct Field: Codable, Equatable {
        let code: String
        let original: String
        let current: String?
        let matches: Bool
    }

    let at: Date
    let readAt: Date?
    let outcome: Outcome
    let commandOutcome: SlotOutcome
    let freshReadSucceeded: Bool
    let originalName: String?
    let expectedName: String?
    let currentName: String?
    let nameMatches: Bool?
    let originalNameRestorable: Bool
    let fields: [Field]
    let reasons: [String]
}

enum CameraBackupError: LocalizedError, Equatable {
    case wrongSchema(found: String)
    case tooNew(version: Int)
    case invalidContents(String)
    case slotEmptyInBackup(slot: Int)
    case differentBody(backup: String, connected: String)

    var errorDescription: String? {
        switch self {
        case .wrongSchema(let found):
            return "That isn't a Fuji Cookbook camera backup (it says “\(found)”). A recipe file won't work here — a backup holds the camera's own settings for every slot."
        case .tooNew(let version):
            return "That backup was written by a newer version of Fuji Cookbook (format \(version)). Update the app to restore from it."
        case .invalidContents(let detail):
            return "That backup cannot be restored. " + detail + " Nothing was written."
        case .slotEmptyInBackup(let slot):
            return "C\(slot) was empty when this backup was taken, so there's nothing to put back. " + CameraBackup.slotCannotBeEmptied
        case .differentBody(let backup, let connected):
            return "That backup came from a \(backup) and this is a \(connected). Restoring it would write one camera's settings onto another."
        }
    }
}
