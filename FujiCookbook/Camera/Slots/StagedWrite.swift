import Foundation

/// How the staged first write to a body ended: the one bank property a first push writes and reads
/// back before anything else changes (`SlotWriter`).
enum FirstWriteOutcome: Equatable {
    /// How the property was put back after a stop. Read first, written only on a difference: the
    /// record warns that a write of the value a bank already holds can itself be refused
    /// (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md#why-a-write-is-refused`).
    enum Restore: Equatable {
        /// The read after the stop matched the recovery copy, so nothing was written back.
        case unchanged
        /// The recovery copy's bytes were written back and read back.
        case restored
        /// The write back was refused with this response.
        case restoreRefused(code: UInt16)
        /// Written back, and the read-back still differed.
        case restoreMismatch
        /// The read after the stop, or the write back, got no answer.
        case restoreUnknown

        var sentence: String {
            switch self {
            case .unchanged: return "The slot is as it was."
            case .restored: return "The original value was written back and confirmed."
            case .restoreRefused(let code): return "Putting the original value back was refused (\(PTPHex.code(code)))."
            case .restoreMismatch: return "The original value was written back but didn't read back as expected."
            case .restoreUnknown: return "Whether the original value is back couldn't be confirmed."
            }
        }
    }

    /// Written and read back as written; the push went on.
    case written(property: UInt16)
    /// Refused with `0x201C`: the value, not the protocol
    /// (zgrimz/fujifilm-ptp-reference `docs/01-transport.md#response-codes`). The push went on, as it
    /// does past any such refusal.
    case invalidValue(property: UInt16, code: UInt16)
    /// Refused with another response; the push stopped there.
    case refused(property: UInt16, code: UInt16, restore: Restore)
    /// Accepted and read back as something else; the push stopped there.
    case mismatched(property: UInt16, read: Data?, restore: Restore)
    /// No response to the write; the push stopped there, and what the bank holds is unknown.
    case unknown(property: UInt16, restore: Restore)

    /// The sentence a stop shows the user; nil when the push went on.
    func stopMessage(slot: Int) -> String? {
        switch self {
        case .written, .invalidValue:
            return nil
        case .refused(let property, let code, let restore):
            return "The camera refused the first setting written to C\(slot), \(SlotWriteVerification.propertyName(for: property)) (\(PTPHex.code(code))), so nothing else was written. \(restore.sentence)"
        case .mismatched(let property, _, let restore):
            return "The camera accepted the first setting written to C\(slot), \(SlotWriteVerification.propertyName(for: property)), but read it back differently, so nothing else was written. \(restore.sentence)"
        case .unknown(let property, let restore):
            return "The camera didn't answer the first setting written to C\(slot), \(SlotWriteVerification.propertyName(for: property)), so nothing else was written and what the slot holds is uncertain. \(restore.sentence)"
        }
    }
}

/// The staged first write: app policy for the first push to a body no push has been read back on.
///
/// The record's method for a new body probes grain on a backed-up bank before a full write
/// (zgrimz/fujifilm-ptp-reference `docs/08-methods.md#minimum-evidence-for-a-new-body`). This app
/// stages film simulation or sharpness instead: `SlotWriteVerification.readBackMatches` compares
/// both byte for byte, where grain Off is written as one value and read as another, and the
/// record's refusal table records no gate for either (`docs/04-custom-slots.md#why-a-write-is-refused`),
/// though it doesn't say they are ungated. Nothing here is a protocol fact.
enum StagedWrite {
    /// In preference order.
    static let candidates: [FujiPTP.PresetProp] = [.filmSimulation, .sharpness]

    /// The first candidate the push writes whose bytes differ from what the bank holds. Nil when
    /// neither does, and the push then runs unstaged: a write of the value a bank already holds
    /// proves nothing and can itself be refused.
    static func pick(encoded: [(code: UInt16, bytes: Data)], base: [UInt16: Data]) -> (code: UInt16, bytes: Data)? {
        for candidate in candidates {
            guard let write = encoded.first(where: { $0.code == candidate.rawValue }) else { continue }
            if base[write.code] != write.bytes { return write }
        }
        return nil
    }

    /// Whether a push proved the bank path on this body: at least one write landed, every write the
    /// camera accepted was held, and the name was written, refused or never attempted. A refusal
    /// says nothing against the path (a field the body lacks, a value its state won't take); a
    /// mismatch or an outcome that isn't known does.
    static func provesBankPath(_ result: SlotWriteResult) -> Bool {
        // Pre-flight entries carry no property code and never reached the camera.
        let fields = result.fields.filter { $0.code != 0 }
        guard fields.contains(where: { $0.outcome == .written }) else { return false }
        for field in fields {
            switch field.outcome {
            case .written, .rejected, .notAttempted: continue
            case .mismatched, .unverified, .outcomeUnknown: return false
            }
        }
        switch result.nameOutcome {
        case nil, .written, .rejected, .notAttempted: return true
        case .mismatched, .unverified, .outcomeUnknown: return false
        }
    }

    /// The headline outcome after a stop: `.notWritten` when the bank is as it was, because the
    /// first write was refused or has been put back and confirmed; `.unknown` when the write got no
    /// response; otherwise the bank changed and the push is partially applied.
    static func outcomeAfterStop(_ outcome: FirstWriteOutcome) -> SlotOutcome {
        switch outcome {
        case .written, .invalidValue: return .applied
        case .unknown: return .unknown
        case .refused: return .notWritten
        case .mismatched(_, _, let restore):
            switch restore {
            case .unchanged, .restored: return .notWritten
            case .restoreRefused, .restoreMismatch, .restoreUnknown: return .partiallyApplied
            }
        }
    }
}
