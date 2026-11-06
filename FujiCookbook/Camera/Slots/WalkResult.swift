import Foundation

/// How a slot read ended, as `SlotReader.refresh` hands it back to its caller.
///
/// Kept apart from `SlotReader.walk`, which is the UI's state for the same read: this is the
/// evidence the connect sequence files about what the body answered, and it says more than the UI
/// needs — where a select was ignored, whether every selected bank read in full.
enum WalkEvidence: Equatable {
    /// No read ran, or a read-only sweep did not complete.
    case notWalked
    /// The body took the read-only sweep, which writes nothing, and the sweep completed.
    case sweptReadOnly
    /// `banks` selects were accepted and read back. `allRead` is false when a selected bank
    /// answered a property read with anything but `0x200A`, which only says the property is
    /// absent.
    case finished(banks: Int, allRead: Bool)
    /// The select of this bank answered OK and the selector read back as another bank, so the walk
    /// stopped there rather than file one bank's values under another.
    case stopped(selectIgnoredAt: Int)
    /// The walk threw: a refused C1 select, a timeout or a disconnect.
    case failed(String)

    /// For the compatibility report.
    var reportLabel: String {
        switch self {
        case .notWalked: return "not walked"
        case .sweptReadOnly: return "swept read-only"
        case .finished(let banks, let allRead):
            return "finished: \(banks) bank\(banks == 1 ? "" : "s"), " + (allRead ? "all read" : "a bank did not answer every property")
        case .stopped(let bank): return "stopped: select of C\(bank) answered OK and did not take"
        case .failed(let detail): return "failed: \(detail)"
        }
    }
}

/// One slot read's result: what the selector answered before it, how the walk ended, and whether
/// the selector went back where it was.
struct WalkResult: Equatable {
    var selector: SelectorRead = .notRead
    var walk: WalkEvidence = .notWalked
    /// `SlotSelector.restore`'s answer; nil when there was nothing to restore.
    var selectorRestored: Bool?
}
