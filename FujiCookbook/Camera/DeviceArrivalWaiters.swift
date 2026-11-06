import Foundation

/// The callers waiting for a camera to be attached, each until one arrives or its own timeout
/// passes. Multiple concurrent waiters are supported (not expected in normal use, but a stale
/// reconnect attempt racing a fresh manual Connect shouldn't deadlock or drop one of them) — an
/// arrival resolves all of them.
@MainActor
final class DeviceArrivalWaiters {
    private struct Waiter { let id: UUID; let continuation: CheckedContinuation<any DiscoveredCamera, Error> }
    private var waiters: [Waiter] = []
    private var waiterTimeouts: [UUID: Task<Void, Never>] = [:]

    /// How many callers are waiting.
    var count: Int { waiters.count }

    /// The next camera to arrive. Throws `CameraError.noDeviceConnected` when none arrives within
    /// `timeout`, and `CancellationError` as soon as the waiting task is cancelled, so a cancelled
    /// connect or recovery does not sit out the rest of the timeout.
    func wait(timeout: TimeInterval) async throws -> any DiscoveredCamera {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                // A task cancelled before it got here has already run `onCancel`, and that found no
                // waiter to end.
                guard !Task.isCancelled else { return cont.resume(throwing: CancellationError()) }
                waiters.append(Waiter(id: id, continuation: cont))
                waiterTimeouts[id] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    self?.failWaiter(id: id, error: CameraError.noDeviceConnected)
                }
            }
        } onCancel: {
            // Called on the cancelling thread; the waiters belong to the main actor.
            Task { @MainActor [weak self] in self?.failWaiter(id: id, error: CancellationError()) }
        }
    }

    func succeedAllWaiters(with device: any DiscoveredCamera) {
        let pending = waiters
        waiters.removeAll()
        for w in pending {
            waiterTimeouts[w.id]?.cancel(); waiterTimeouts[w.id] = nil
            w.continuation.resume(returning: device)
        }
    }

    private func failWaiter(id: UUID, error: Error) {
        waiterTimeouts.removeValue(forKey: id)?.cancel()
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: error)
    }
}
