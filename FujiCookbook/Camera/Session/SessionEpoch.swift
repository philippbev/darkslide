import Foundation

/// Monotonic id for the live camera session. Every callback that can outlive its session — a
/// keepalive ping already in flight, a `connect` still opening, a recovery attempt, the transport's
/// removal callback — captures the epoch it started under and is a no-op once the epoch has moved on.
///
/// `keepAlive?.cancel()` cancels the polling *loop*, not a `readProperty` call already in flight
/// (a `withCheckedThrowingContinuation`, not cancellation-aware) — that call runs to its own
/// timeout (`ImageCaptureTransport.baseTimeout`) regardless, and a `transport != nil` guard alone would let its failure land on a
/// brand-new transport just as well as the dead one. Without the epoch, a user who disconnected
/// and reconnected inside that window would have the old session's ping kill the new one.
@MainActor
struct SessionEpoch {
    private(set) var current: UInt64 = 0

    @discardableResult
    mutating func advance() -> UInt64 {
        current &+= 1
        return current
    }

    /// `true` iff `epoch` is still the live session. Logs the suppression when not — an entry here
    /// is direct evidence the race above fired for real, not just in theory.
    func isCurrent(_ epoch: UInt64, _ what: @autoclosure () -> String) -> Bool {
        if epoch == current { return true }
        CameraLog.error("Ignored \(what()) from a superseded session (epoch \(epoch), current \(current))")
        return false
    }
}
