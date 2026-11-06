import Foundation
import Observation

/// The live connection: what it is doing, which camera it is talking to, and what that camera
/// allows. Changed only by the camera services; views observe it.
@MainActor
@Observable
final class CameraSession {

    enum Status: Equatable {
        case disconnected, connecting, connected
        case working(String)
        case failed(String)

        var isBusy: Bool {
            switch self { case .connecting, .working: return true; default: return false }
        }
    }

    private(set) var status: Status = .disconnected
    private(set) var connected: ConnectedCamera?
    private(set) var transport: CameraTransport?
    /// The live session's id (see `SessionEpoch`). Advanced by `CameraConnector` on every connect
    /// and disconnect.
    private(set) var epoch = SessionEpoch()

    var model: CameraModel? { connected?.model }
    var isConnected: Bool { connected != nil }
    /// Whether a push may be offered: a connected body with a granted write permission.
    var canPush: Bool { connected?.isWritable ?? false }
    /// Why it may not be, in one sentence, when it may not.
    var pushBlockReason: String? { connected?.writeBlockReason }

    /// Whether the Kitchen RAW-conversion flow is available: a connected body with a trusted
    /// identification, a model the registry allows conversion on, and a transport that supports
    /// object transfer. The Kitchen UI's counterpart of `canPush`.
    var canConvert: Bool {
        // Conversion leaves nothing on the camera, but it does drive a reverse-engineered path on
        // it; a body identified by guess doesn't get that either.
        guard let connected, connected.identification.isTrusted,
              let model = connected.model, model.supportsRawConversion else { return false }
        return transport is RawConversionTransport
    }

    /// Whether the app may write `FujiPTP.Prop.slotSelector` to put the camera on a chosen slot
    /// (`ConnectedCamera.maySelectSlots`). False with nothing connected.
    var maySelectSlots: Bool { connected?.maySelectSlots ?? false }

    /// The transport's RAW-conversion capability, when the connected body supports it.
    var rawConversionTransport: RawConversionTransport? { transport as? RawConversionTransport }

    // MARK: - Mutation, by the camera services only

    func setStatus(_ status: Status) {
        self.status = status
    }

    func setCamera(_ camera: ConnectedCamera?) {
        connected = camera
    }

    /// File how the staged first write ended (`SlotWriter`), beside the rest of what the body answered.
    func recordFirstWrite(_ outcome: FirstWriteOutcome) {
        guard let connected else { return }
        self.connected = connected.recording(firstWrite: outcome)
    }

    /// The one transition a permission makes, and the session's to make: a push has been read back
    /// on this body (`StagedWrite.provesBankPath`), so later pushes in this session run unstaged.
    /// Nothing persists it; the next connect decides again. The writer reports, the session moves.
    func markWriteVerified() {
        guard let connected, case .granted(let permission) = connected.writeAccess,
              permission.stage == .unverified else { return }
        self.connected = connected.deciding(.granted(permission.verified()))
    }

    func attach(_ transport: CameraTransport) {
        self.transport = transport
    }

    func detach() {
        transport = nil
    }

    @discardableResult
    func advanceEpoch() -> UInt64 {
        epoch.advance()
    }

    /// Whether an operation that started under `token` is still talking to the session it started
    /// with: the epoch hasn't moved, and the transport is still attached.
    func operationIsCurrent(_ token: UInt64) -> Bool {
        token == epoch.current && transport != nil
    }
}
