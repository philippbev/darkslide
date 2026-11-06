import Foundation

/// What the connected body answered at connect, kept apart from what it is (`ModelIdentification`),
/// what the registry publishes about it (`CameraModel`) and what the app will do with it
/// (`WriteAccess`), as the record asks of a client (zgrimz/fujifilm-ptp-reference
/// `docs/11-client-implementation.md#keep-session-and-device-identity-explicit`).
struct ObservedCapabilities: Equatable {
    /// The connect's slot read; nil until it has run.
    var slotRead: WalkResult?
    /// How the staged first write ended, once a first push has run on a body no push had been read
    /// back on (`StagedWrite`). Nil before that, and on a body whose permission started verified.
    var firstWrite: FirstWriteOutcome?

    /// Whether the selector (`0xD18C`) answered a bank number: the one read that shows the bank
    /// block is there (`SelectorRead`).
    var hasBankBlock: Bool {
        if case .value = slotRead?.selector { return true }
        return false
    }
}
