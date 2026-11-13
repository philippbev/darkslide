//  ImageCaptureTransport.swift
//
//  The hardware camera transport: drives a connected Fujifilm body via Apple's ImageCaptureCore,
//  sending Fuji PTP commands through `ICCameraDevice.requestSendPTPCommand`.
//
//  The property codes and value encodings it carries are the ones in FujiPTP and FujiEncoding
//  (see FujiPresetCodec and docs/fuji-recipe-ptp-protocol.md).

import Foundation
import CoreGraphics
import ImageCaptureCore

@MainActor
final class ImageCaptureTransport: NSObject, CameraTransport {
    private let cameraDevice: ICCameraDevice
    private var transactionID: UInt32 = 0
    private var ptpContinuation: CheckedContinuation<(inData: Data?, response: Data?), Error>?
    private var timeoutTask: Task<Void, Never>?
    /// Identifies the transaction the current `timeoutTask`/callback belongs to, so a late callback
    /// after a timeout (or vice-versa) can't resume the wrong — or an already-resumed — continuation.
    private var pendingToken: UInt64 = 0
    /// Set once the first response has shown whose numbers the session's transactions run on.
    private var transactionNumberingNoted = false

    /// Serial gate: only one PTP transaction may be in flight at a time. The keepalive ping and a
    /// user push share this transport; two overlapping `requestSendPTPCommand` calls would clobber
    /// the single `ptpContinuation` and desync the transaction ID. All I/O funnels through `sendPTP`,
    /// which acquires this before issuing a command and releases it after the callback/timeout.
    private var gateBusy = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    /// Set by `close()` and checked at the top of every transaction so a caller racing a teardown
    /// fails fast with a clear error instead of hanging behind a gate that will never open, or a
    /// transaction that will never get a callback.
    private var isClosed = false

    /// Invoked (on the main actor) when the camera reports removal, so `CameraConnector` can
    /// tear down its stale connection state instead of appearing connected to a device that's gone.
    var onDisconnect: (@MainActor () -> Void)?

    nonisolated let productName: String
    /// Not known at the transport level: `CameraConnector` reads it from `GetDeviceInfo`
    /// (`deviceVersion`) right after the session opens and carries it in `ConnectedCamera`.
    nonisolated let firmwareVersion: String? = nil
    /// From ImageCaptureCore's enumeration — the one identity that doesn't depend on the product
    /// name string, which is why the report records it alongside.
    nonisolated let usbIdentity: USBIdentity?
    /// Bounded transaction trace for the compatibility report; nil when nobody is listening.
    private var trace: PTPTraceRecorder?

    init(cameraDevice: ICCameraDevice) {
        self.cameraDevice = cameraDevice
        self.productName = cameraDevice.name ?? "Fujifilm Camera"
        self.usbIdentity = USBIdentity(vendorID: Int(cameraDevice.usbVendorID), productID: Int(cameraDevice.usbProductID))
        super.init()
        self.cameraDevice.delegate = self
    }

    func attachTrace(_ recorder: PTPTraceRecorder?) async { trace = recorder }

    // MARK: Session

    /// Open a PTP session, retrying once. The browser hands out the same, long-lived
    /// `ICCameraDevice` across reconnects (see `CameraDeviceBrowser`), so a session that's still
    /// settling from a just-closed previous connect — or a body that's briefly
    /// `ICReturnDeviceIsBusyEnumerating` right after being plugged in — is common enough to retry
    /// automatically rather than surface as a failure on the first try.
    func open() async throws {
        do {
            try await attemptOpen()
        } catch {
            CameraLog.error("Transport: open failed (\((error as? CameraError)?.errorDescription ?? AppLog.bounded(error))); retrying once")
            try? await Task.sleep(nanoseconds: 400_000_000)
            try await attemptOpen()
        }
        isClosed = false
        CameraLog.info("Transport: session open (\(productName))")
    }

    private func attemptOpen() async throws {
        // A session left open by a transport that didn't close cleanly (or a previous connect whose
        // slot read blew up before `CameraConnector` could disconnect) makes a fresh open() fail with
        // "session already open". Adopting that leftover session instead of closing it would also
        // leave our transaction-id counter restarting at 1 while the camera's own PTP responder may
        // still expect ids to keep climbing from the old session — always start clean.
        if cameraDevice.hasOpenSession {
            CameraLog.info("Transport: stale open session found before open — closing it first")
            try? await cameraDevice.requestCloseSession(options: nil)
        }
        do {
            // Not the bare `requestOpenSession()`: `ICDevice` also declares a void, delegate-only
            // overload of that name, and a zero-argument call leaves which one binds up to overload
            // resolution rather than intent. Naming `options:` selects the completion-handler form
            // unambiguously — the only one that hands back the `NSError` `CameraError.from` classifies.
            try await cameraDevice.requestOpenSession(options: nil)
        } catch {
            throw CameraError.from(error)
        }
    }

    /// Tear down everything this transport owns. Idempotent — safe to call more than once (a manual
    /// disconnect racing an unexpected-removal callback both call this) — and completes promptly
    /// instead of leaving in-flight work to expire on its own timers (up to 50s for a `GetObject`).
    func close() async {
        guard !isClosed else { return }
        isClosed = true
        CameraLog.info("Transport: closing (\(productName))")

        timeoutTask?.cancel(); timeoutTask = nil
        ptpContinuation?.resume(throwing: CameraError.disconnectedDuringOperation)
        ptpContinuation = nil
        let waiting = gateWaiters
        gateWaiters.removeAll()
        gateBusy = false
        // Release anything queued on the gate; each will observe `isClosed` in `sendPTP` and fail
        // fast rather than attempt a transaction against a closing session.
        for waiter in waiting { waiter.resume() }

        if cameraDevice.hasOpenSession {
            try? await cameraDevice.requestCloseSession(options: nil)
        }
        // The shared browser vends the same `ICCameraDevice` across reconnects, so a newer transport
        // may already have claimed the delegate by the time this runs (e.g. a background reconnect
        // racing a manual one) — only release it if it's still ours.
        if cameraDevice.delegate === self { cameraDevice.delegate = nil }
        onDisconnect = nil
    }

    // MARK: Device info

    /// `GetDeviceInfo` (0x1001): no parameters; the camera answers with its DeviceInfo dataset —
    /// model, firmware, and the operation and property codes it supports. Sent once per connect.
    func deviceInfo() async throws -> Data? {
        transactionID &+= 1
        let command = FujiPTP.commandContainer(operation: .getDeviceInfo, transactionID: transactionID)
        let (inData, response) = try await sendPTP(command, outData: nil)
        try checkResponse(response)
        return inData
    }

    // MARK: Property I/O

    func readProperty(_ code: UInt16) async throws -> Data? {
        transactionID &+= 1
        let command = FujiPTP.commandContainer(operation: .getDevicePropValue,
                                               transactionID: transactionID,
                                               parameters: [UInt32(code)])
        let (inData, response) = try await sendPTP(command, outData: nil)
        try checkResponse(response)
        return inData
    }

    func writeProperty(_ code: UInt16, _ bytes: Data) async throws {
        transactionID &+= 1
        let command = FujiPTP.commandContainer(operation: .setDevicePropValue,
                                               transactionID: transactionID,
                                               parameters: [UInt32(code)])
        let (_, response) = try await sendPTP(command, outData: bytes)
        try checkResponse(response)
    }

    /// `GetDevicePropDesc` (0x1014) — same command shape as a property read, but the camera answers
    /// with its description of the property instead of the value: type, get/set, factory default,
    /// current value, and the enumerated set of values it will accept. That last part is what tells
    /// us whether a silently-discarded write was simply an out-of-set value.
    func readPropertyDescriptor(_ code: UInt16) async throws -> Data? {
        transactionID &+= 1
        let command = FujiPTP.commandContainer(operation: .getDevicePropDesc,
                                               transactionID: transactionID,
                                               parameters: [UInt32(code)])
        let (inData, response) = try await sendPTP(command, outData: nil)
        try checkResponse(response)
        return inData
    }

    // MARK: PTP transport

    nonisolated static func checkResponse(_ response: Data?) throws {
        let code = try FujiPTP.validatedResponseCode(from: response)
        guard code == FujiPTP.responseOK else {
            throw CameraError.ptpError(code: code)
        }
    }

    private func checkResponse(_ response: Data?) throws {
        do { try Self.checkResponse(response) }
        catch {
            CameraLog.error("Transport: response rejected — \(error.diagnosticReason)")
            throw error
        }
    }

    /// Seconds to allow a transaction moving `bytes` of payload. Property reads and writes are a
    /// handful of bytes and keep the flat floor; the RAW-conversion transfers are not — a RAF is
    /// 87 MB from an X-T50 and 198 MiB from a GFX100S (`RAFSource` cites the record) and a
    /// full-resolution JPEG can be 20 MB+, which over USB 2.0 through ImageCaptureCore
    /// takes longer than the floor on its own. Timing those out reports "the camera stopped
    /// responding" for a transfer that was working fine.
    nonisolated static func transferTimeout(forPayloadBytes bytes: Int) -> TimeInterval {
        Self.baseTimeout + Double(bytes) / 1_000_000   // ≈1s per MB on top of the floor
    }

    nonisolated static let baseTimeout: TimeInterval = 20

    /// Bridge `requestSendPTPCommand` (selector-callback based) to async/await.
    ///
    /// Serialized (one transaction at a time) and bounded by `timeout`: if the camera sleeps or the
    /// USB pipe stalls, `didSendPTPCommand` may never fire. Without the timeout the continuation
    /// would never resume and every later camera call would await behind it — the app appears frozen
    /// until it's restarted. On timeout we fail with `CameraError.timeout` so the caller can recover.
    ///
    /// `timeout` defaults to the flat floor; the bulk object transfers pass a size-scaled value.
    private func sendPTP(_ command: Data, outData: Data?,
                         timeout: TimeInterval = ImageCaptureTransport.baseTimeout) async throws -> (inData: Data?, response: Data?) {
        guard let trace else { return try await sendPTPUntraced(command, outData: outData, timeout: timeout) }
        // The trace sees the wire form: opcode and parameters straight out of the container it is
        // about to send, so a framing mistake here would show up in the report as what was sent.
        let opcode = command.readLE(UInt16.self, at: 6) ?? 0
        var parameters: [UInt32] = []
        var offset = 12
        while let p = command.readLE(UInt32.self, at: offset) { parameters.append(p); offset += 4 }
        // Object transfers are traced by size only — a RAF or a JPEG has no place in a report.
        let isBulk = opcode == FujiPTP.Operation.getObject.rawValue || opcode == FujiPTP.Operation.sendObject2.rawValue
        let started = DispatchTime.now().uptimeNanoseconds
        func elapsedMs() -> Int { Int((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000) }
        do {
            let result = try await sendPTPUntraced(command, outData: outData, timeout: timeout)
            trace.record(operation: opcode, parameters: parameters, outData: outData,
                         inData: result.inData, response: result.response.flatMap(FujiPTP.responseCode(from:)),
                         error: nil, durationMs: elapsedMs(), dumpData: !isBulk)
            return result
        } catch {
            trace.record(operation: opcode, parameters: parameters, outData: outData,
                         inData: nil, response: nil, error: error.diagnosticReason,
                         durationMs: elapsedMs(), dumpData: false)
            throw error
        }
    }

    private func sendPTPUntraced(_ command: Data, outData: Data?,
                                 timeout: TimeInterval) async throws -> (inData: Data?, response: Data?) {
        guard !isClosed else { throw CameraError.disconnectedDuringOperation }
        await acquireGate()
        defer { releaseGate() }
        // Re-check after the suspension: `close()` may have drained this call out of the gate while
        // it was waiting, in which case there's no live session left to send anything to.
        guard !isClosed else { throw CameraError.disconnectedDuringOperation }

        pendingToken &+= 1
        let token = pendingToken
        let result: (inData: Data?, response: Data?) = try await withCheckedThrowingContinuation { cont in
            ptpContinuation = cont
            // Carry the transaction token through contextInfo so the callback can recognize a stale
            // delivery: after a timeout releases the gate, the timed-out command's callback may
            // still arrive once the next command is already in flight — without the token it would
            // resume the WRONG continuation with the old transaction's data and cancel the new
            // command's timeout, desyncing every transaction after the first slow one.
            let tokenBox = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UInt64>.size,
                                                            alignment: MemoryLayout<UInt64>.alignment)
            tokenBox.storeBytes(of: token, as: UInt64.self)
            cameraDevice.requestSendPTPCommand(
                command,
                outData: outData,
                sendCommandDelegate: self,
                didSendCommand: #selector(didSendPTPCommand(_:inData:response:error:contextInfo:)),
                contextInfo: tokenBox)
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self, self.pendingToken == token, let waiting = self.ptpContinuation else { return }
                self.ptpContinuation = nil
                self.timeoutTask = nil
                CameraLog.error("Transport: PTP transaction timed out after \(Int(timeout))s")
                waiting.resume(throwing: CameraError.timeout)
            }
        }
        noteTransactionNumbering(command: command, response: result.response)
        return result
    }

    /// One line per session on whose numbers its transactions run. ImageCaptureCore shares the
    /// PTP session with its own traffic and renumbers what it forwards, so the ID the camera echoes
    /// is expected to differ from the one in the container we built; the line in a report is the
    /// evidence for that, and the reason no response check compares the two.
    private func noteTransactionNumbering(command: Data, response: Data?) {
        guard !transactionNumberingNoted, let response,
              let sent = FujiPTP.transactionID(from: command),
              let echoed = FujiPTP.transactionID(from: response) else { return }
        transactionNumberingNoted = true
        CameraLog.info(sent == echoed
            ? "Transport: the camera echoes our transaction IDs (\(sent))"
            : "Transport: the camera answered transaction \(echoed) to our \(sent) — ImageCaptureCore numbers the session's transactions itself")
    }

    @objc private func didSendPTPCommand(_ command: Data, inData: Data?, response: Data?,
                                         error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        let token = contextInfo?.load(as: UInt64.self)
        contextInfo?.deallocate()
        // A callback for anything but the current transaction is a late delivery from a command
        // that already timed out — ignore it entirely (touching timeoutTask/ptpContinuation here
        // would clobber the transaction now in flight).
        guard token == pendingToken else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        let cont = ptpContinuation      // nil if the timeout already fired for this transaction
        ptpContinuation = nil
        if let error {
            let mapped = CameraError.from(error)
            CameraLog.error("Transport: PTP command failed — \(mapped.errorDescription ?? AppLog.bounded(error))")
            cont?.resume(throwing: mapped)
        } else {
            cont?.resume(returning: (inData, response))
        }
    }

    // MARK: Serial gate

    /// Suspend until no other transaction is in flight, then mark the gate busy.
    private func acquireGate() async {
        if !gateBusy { gateBusy = true; return }
        await withCheckedContinuation { gateWaiters.append($0) }
    }

    /// Hand the gate to the next waiter, or mark it free.
    private func releaseGate() {
        if gateWaiters.isEmpty { gateBusy = false }
        else { gateWaiters.removeFirst().resume() }
    }
}

// MARK: - ICCameraDeviceDelegate / ICDeviceDelegate (requirements are nonisolated)

extension ImageCaptureTransport: ICCameraDeviceDelegate {
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {}

    /// The header notes this also fires "if the device module in control of the device ceases to
    /// control the device" — an unsolicited session-death signal distinct from a normal `close()`.
    /// Logged only (not routed to `onDisconnect`): `didRemove` below is the actual removal signal
    /// `CameraConnector` reacts to, and firing both would double-trigger recovery.
    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            let mapped = CameraError.from(error)
            CameraLog.error("Transport: session closed with error — \(mapped.errorDescription ?? AppLog.bounded(error))")
        }
    }

    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in
            CameraLog.info("Transport: didRemove — device removed while the session was live")
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.ptpContinuation?.resume(throwing: CameraError.disconnectedDuringOperation)
            self.ptpContinuation = nil
            self.onDisconnect?()
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: (any Error)?) {}
    nonisolated func cameraDeviceDidEnumerateItems(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}

// MARK: - RawConversionTransport (real object transfer for the Kitchen RAW-conversion flow)

extension ImageCaptureTransport: RawConversionTransport {

    /// Checked before the develop's object transfers, so a body whose `capabilities` lack
    /// `ICCameraDeviceCanAcceptPTPCommands` fails as `rawConversionUnsupported` before anything is
    /// uploaded. Property reads and writes don't check it. The device has no
    /// `cameraDeviceCanAcceptPTPCommands` property; the capability list is the only place to look.
    private func ensurePTPCapable() throws {
        // `capabilities` is `[String]` on iOS; the constant is an `ICDeviceCapability`, so compare
        // its `rawValue`.
        guard cameraDevice.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue) else {
            throw CameraError.rawConversionUnsupported
        }
    }

    func sendObject(_ data: Data, filename: String) async throws {
        try ensurePTPCapable()
        // SendObjectInfo (0x900C) with the ObjectInfo dataset, then SendObject2 (0x900D) with bytes.
        // The sequence zgrimz/fujifilm-ptp-reference `docs/05-raw-conversion.md` records:
        // SendObjectInfo takes [storageID, parent, 0] = [0, 0, 0], and the object is named
        // `FUP_FILE.dat`, as every known client names it, not the
        // real RAF filename (`filename` is kept only for higher-level labeling). A malformed upload
        // has drawn PTP 0x2015 (No_Valid_ObjectInfo) from SendObject on an X-T50; whether the name
        // alone causes it is untested.
        transactionID &+= 1
        let info = FujiPTP.objectInfo(compressedSize: UInt32(data.count),
                                      filename: FujiPTP.rawConversionUploadName)
        let infoCmd = FujiPTP.commandContainer(operation: .sendObjectInfo, transactionID: transactionID,
                                               parameters: [0, 0, 0])
        let (_, infoResp) = try await sendPTP(infoCmd, outData: info)
        try checkResponse(infoResp)

        transactionID &+= 1
        let objCmd = FujiPTP.commandContainer(operation: .sendObject2, transactionID: transactionID)
        let (_, objResp) = try await sendPTP(objCmd, outData: data,
                                             timeout: Self.transferTimeout(forPayloadBytes: data.count))
        try checkResponse(objResp)
    }

    func getObjectHandles() async throws -> [UInt32] {
        try await getObjectHandles(timeout: Self.baseTimeout)
    }

    /// `GetObjectHandles` with room for a camera that indexes its card first: an X100VI with 2,000
    /// frames took longer than the 20-second floor in USB Card Reader mode (iPhone, 2026-11-13).
    func getObjectHandles(timeout: TimeInterval) async throws -> [UInt32] {
        try ensurePTPCapable()
        transactionID &+= 1
        // params: storageID (0xFFFFFFFF = all), objectFormat (0 = any), parent (0).
        let cmd = FujiPTP.commandContainer(operation: .getObjectHandles, transactionID: transactionID,
                                           parameters: [0xFFFF_FFFF, 0, 0])
        let (inData, response) = try await sendPTP(cmd, outData: nil, timeout: timeout)
        let code: UInt16
        do {
            code = try FujiPTP.validatedResponseCode(from: response)
        } catch {
            // A response container is a twelve-byte header and up to five parameters, never user
            // content, so the rejected bytes belong in the log: the trace records the wire as OK
            // and would otherwise leave nothing to say why a develop stopped here.
            CameraLog.error("Transport: GetObjectHandles response rejected — \(response.map { PTPHex.dump($0, limit: 32) } ?? "no response container")")
            throw error
        }
        guard code == FujiPTP.responseOK else { throw CameraError.ptpError(code: code) }
        return try FujiPTP.parseObjectHandles(inData)
    }

    func getObjectInfo(_ handle: UInt32) async throws -> FujiPTP.ObjectInfo {
        try ensurePTPCapable()
        transactionID &+= 1
        let command = FujiPTP.commandContainer(operation: .getObjectInfo, transactionID: transactionID,
                                                parameters: [handle])
        let (data, response) = try await sendPTP(command, outData: nil)
        try checkResponse(response)
        return try FujiPTP.parseObjectInfo(data)
    }

    /// `GetThumb` — the small JPEG the camera keeps for an object. Read-only.
    func getThumb(_ handle: UInt32) async throws -> Data {
        try ensurePTPCapable()
        transactionID &+= 1
        let cmd = FujiPTP.commandContainer(operation: .getThumb, transactionID: transactionID,
                                           parameters: [handle])
        let (inData, response) = try await sendPTP(cmd, outData: nil)
        try checkResponse(response)
        return inData ?? Data()
    }

    /// `GetObject` for a file whose size the camera has stated, timed for that size rather than
    /// the converted JPEG's budget: a RAF from a 40 MP body is over 50 MB. Read-only.
    func getObject(_ handle: UInt32, expectedBytes: Int) async throws -> Data {
        try ensurePTPCapable()
        transactionID &+= 1
        let cmd = FujiPTP.commandContainer(operation: .getObject, transactionID: transactionID,
                                           parameters: [handle])
        let (inData, response) = try await sendPTP(cmd, outData: nil,
                                                   timeout: Self.transferTimeout(forPayloadBytes: max(expectedBytes, 1_000_000)))
        try checkResponse(response)
        return inData ?? Data()
    }

    func getObject(_ handle: UInt32) async throws -> Data {
        try ensurePTPCapable()
        transactionID &+= 1
        let cmd = FujiPTP.commandContainer(operation: .getObject, transactionID: transactionID,
                                           parameters: [handle])
        // The JPEG's size isn't known until it arrives, so budget for a large full-resolution one
        // (40MP bodies produce 20 MB+) rather than risk timing out mid-download.
        let (inData, response) = try await sendPTP(cmd, outData: nil,
                                                   timeout: Self.transferTimeout(forPayloadBytes: 30_000_000))
        try checkResponse(response)
        return inData ?? Data()
    }

    func deleteObject(_ handle: UInt32) async throws {
        try ensurePTPCapable()
        transactionID &+= 1
        let cmd = FujiPTP.commandContainer(operation: .deleteObject, transactionID: transactionID,
                                           parameters: [handle])
        let (_, response) = try await sendPTP(cmd, outData: nil)
        try checkResponse(response)
    }
}

// MARK: - ImageCaptureCore error classification

extension CameraError {
    /// Map an `NSError` from ImageCaptureCore (`ICErrorDomain`) to a specific, actionable
    /// `CameraError` instead of letting it fall through to the generic "No camera detected" or a
    /// bare `localizedDescription`. Every `ICReturn*` code in `ImageCaptureConstants.h` shares this
    /// one domain — the header only splits them into several `NS_ERROR_ENUM` types for compile-time
    /// grouping in Objective-C — so classification here is by raw numeric code.
    ///
    /// VERIFY on hardware: the `.wrongUSBMode` mapping is the one inference in this table. Put a
    /// body in a non-RAW-Conv USB mode, Connect, and read the code out of the Connection Log. If it
    /// differs from what's mapped here, demote the mismatch to `.sessionFailed` with the raw code
    /// rather than keep telling the user to check a setting that isn't the actual problem.
    static func from(_ error: Error) -> CameraError {
        if let already = error as? CameraError { return already }
        let ns = error as NSError
        guard ns.domain == ICErrorDomain else {
            return .sessionFailed(ns.localizedDescription)
        }
        switch ns.code {
        case -21343, -21249:               // NotAuthorizedToOpenDevice / PTPNotAuthorizedToSendCommand
            return .permissionDenied
        case -21345, -21344, -9927:        // FailedToOpen(Device) / DeviceFailedToOpenSession — enumerates but won't hold a session
            return .wrongUSBMode
        case -9943, -9953:                 // DeviceIsPasscodeLocked / DeviceNeedsCredentials
            return .wrongUSBMode
        case -21349, -21348, -21350, -9958: // ClosedSessionSuddenly / EjectedSuddenly / DriverExited / SessionNotOpened
            return .disconnectedDuringOperation
        case -9923:                        // CommunicationTimedOut
            return .timeout
        case -9954:                        // DeviceIsBusyEnumerating — the body is still cataloguing its card
            return .sessionFailed("The camera is still starting up. Try again in a moment.")
        default:
            return .sessionFailed("\(ns.localizedDescription) (code \(ns.code))")
        }
    }
}
