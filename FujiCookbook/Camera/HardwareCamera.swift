//  HardwareCamera.swift
//
//  `CameraDeviceBrowser` — a single, **app-lifetime** ICDeviceBrowser wrapper.
//  Requires `NSCameraUsageDescription` (declared in Info.plist).
//
//  One browser for the life of the app, started once and never stopped: ImageCaptureCore does not
//  reliably re-announce an already-attached device to a brand-new browser instance in the same
//  process, so a per-connect browser sits through the full discovery timeout on every *second*
//  connect and reports "No camera detected" — recoverable only by force-quitting the app (which
//  resets ImageCaptureCore's per-process state). `ICDeviceBrowser.devices` (iOS 13+) gives the
//  current device list synchronously, so a second connect after a disconnect finds the
//  still-attached camera immediately instead of re-discovering it.

import Foundation
import ImageCaptureCore

// `ICDeviceBrowserDelegate` predates Swift concurrency and is declared nonisolated, so a
// `@MainActor` conformer trips a data-race diagnostic (an error under Swift 6). ImageCaptureCore
// delivers browser callbacks on the main thread, so `@preconcurrency` is accurate here: it keeps
// the delegate methods main-actor-isolated and checks that at runtime instead of compile time.
@MainActor
final class CameraDeviceBrowser: NSObject, @preconcurrency ICDeviceBrowserDelegate, CameraDiscovery {
    static let shared = CameraDeviceBrowser()
    private override init() {
        super.init()
        CameraLog.info("Browser: created — control \(Self.word(for: browser.controlAuthorizationStatus)), contents \(Self.word(for: browser.contentsAuthorizationStatus))")
    }

    private let browser = ICDeviceBrowser()
    private var isStarted = false

    /// The two ImageCaptureCore grants, as words, for a connection-failure report.
    ///
    /// A camera that never appears has exactly two common causes — the cable or USB mode, and a
    /// permission the user didn't grant or that got stuck Denied (see `ensureAuthorized()`). The log
    /// carries these, but a compatibility report is only created once a session opens, which is
    /// precisely what didn't happen.
    var authorizationSummary: (control: String, contents: String) {
        (Self.word(for: browser.controlAuthorizationStatus),
         Self.word(for: browser.contentsAuthorizationStatus))
    }

    private static func word(for status: ICAuthorizationStatus) -> String {
        // `default` rather than an exhaustive list, matching `ensure` below: ImageCaptureCore's
        // status enum has grown cases across SDKs, and a report is the wrong place to fail to build.
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        default: return "notDetermined(\(status.rawValue))"
        }
    }

    /// The callers awaiting `didAdd` because no device was already attached.
    private let arrivals = DeviceArrivalWaiters()

    /// Fired on `didRemove` for any device the browser was tracking — not filtered to "the one
    /// we're connected to", since the browser has no notion of who's connected. `CameraConnector`
    /// checks device identity before reacting.
    var onDeviceRemoved: (@MainActor (any DiscoveredCamera) -> Void)?

    /// Fired when ImageCaptureCore suspends/resumes device I/O around app background/foreground
    /// (iOS 14+ `deviceBrowserWillSuspendOperations`/`didResumeOperations`). Per Apple's header, a
    /// suspend does **not** close the PTP session — "State should always be managed by the
    /// application" — so `CameraConnector` uses these to pause and resume its keepalive and any
    /// recovery in flight, not to tear the session down.
    var onSuspend: (@MainActor () -> Void)?
    var onResume: (@MainActor () -> Void)?

    /// Return the first attached camera, of any make. If the browser already knows about one (the
    /// common case for every connect after the first in a session), returns immediately — this is
    /// what makes Disconnect → Connect fast instead of a fresh discovery wait. Otherwise waits
    /// for `didAdd`, bounded by `timeout` and ended early by cancelling the calling task.
    func firstCamera(timeout: TimeInterval) async throws -> any DiscoveredCamera {
        try await ensureReady()

        if let existing = (browser.devices ?? []).compactMap({ $0 as? ICCameraDevice }).first {
            CameraLog.info("Browser: device already known — \(existing.name ?? "Fujifilm Camera")")
            return existing
        }

        CameraLog.info("Browser: no device attached yet, waiting up to \(Int(timeout))s")
        return try await arrivals.wait(timeout: timeout)
    }

    /// Start the browser (once) and confirm PTP control authorization. Both are lazy — deferred to
    /// the first connect attempt, not app launch — so the system permission prompt (iOS 14+
    /// `requestControlAuthorizationWithCompletion`) appears only when the user actually asks to
    /// connect, not on every cold launch.
    private func ensureReady() async throws {
        if !isStarted {
            isStarted = true
            browser.delegate = self
            // On iOS the device-type mask must be OR'd with a location bit (`.local` = wired/USB);
            // `.camera` alone browses nothing — which manifests as "No camera detected".
            if let mask = ICDeviceTypeMask(
                rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue) {
                browser.browsedDeviceTypeMask = mask
            }
            browser.start()
            CameraLog.info("Browser: started — control \(Self.word(for: browser.controlAuthorizationStatus)), contents \(Self.word(for: browser.contentsAuthorizationStatus))")
        }
        try await ensureAuthorized()
    }

    /// ImageCaptureCore gates a camera behind **two** authorizations, and `didAdd` needs both.
    ///
    /// *Control* is the Camera privacy toggle (`kTCCServiceCamera`); it is what lets the app send
    /// PTP commands. *Contents* is a separate grant with its own system prompt, and without it
    /// `ptpcamerad` enumerates the camera, logs "User denied or disabled … access to *contents* on
    /// external device", and never posts the device to the browser — so the app sees nothing,
    /// reports "No camera detected", and every Settings toggle looks correct.
    ///
    /// Normally contents is granted implicitly the moment control is (the log then reads "contents
    /// authorization already granted"), or a second prompt appears. The other state is a device
    /// holding a **stuck Denied record for one bundle id** that survives uninstall and restart,
    /// cannot be flipped in Settings → Privacy & Security → Files and Folders, and makes
    /// `requestContentsAuthorization` return Denied in milliseconds with no prompt. Only the device's
    /// own log (`icprefd-xpc … User denied or disabled … access to *contents*`) says why — and it is
    /// a record on one phone, not an iOS regression.
    ///
    /// Both are requested lazily on the first connect, not at launch, so the prompts appear when the
    /// user has just asked to talk to a camera. Statuses are logged at creation, at start, and around
    /// each request, so a report shows *when* a denial first appeared.
    private func ensureAuthorized() async throws {
        try await ensure(kind: "control", status: browser.controlAuthorizationStatus,
                         denied: .permissionDenied) { done in
            browser.requestControlAuthorization(completion: done)
        }
        // Reached only with control granted. A refusal here is a stuck per-bundle-id record on the
        // device (or a dismissed second prompt), not the Camera toggle — hence its own error.
        try await ensure(kind: "contents", status: browser.contentsAuthorizationStatus,
                         denied: .contentsAccessUnavailable) { done in
            browser.requestContentsAuthorization(completion: done)
        }
    }

    /// One authorization: pass through if granted, otherwise *ask* — including when iOS already
    /// reports it denied. A stuck record reports contents as `Denied` before anyone has requested
    /// it, so treating that status as final would mean never prompting at all. Apple's header says
    /// the request prompts "if needed"; asking anyway costs nothing and the log records both the
    /// status before and the answer after, so a soft default and a hard block look different.
    /// `restricted` (parental controls / MDM) is the one state that genuinely can't be asked past.
    private func ensure(kind: String, status: ICAuthorizationStatus, denied: CameraError,
                        request: (@escaping @Sendable (ICAuthorizationStatus) -> Void) -> Void) async throws {
        switch status {
        case .authorized:
            CameraLog.info("Browser: \(kind) authorization already granted")
        case .restricted:
            CameraLog.error("Browser: \(kind) authorization is restricted — camera access is blocked by policy")
            throw CameraError.permissionDenied
        default:
            CameraLog.info("Browser: \(kind) authorization is \(status.rawValue) — requesting")
            let result = await withCheckedContinuation { (cont: CheckedContinuation<ICAuthorizationStatus, Never>) in
                request { cont.resume(returning: $0) }
            }
            CameraLog.info("Browser: \(kind) authorization request result — \(result.rawValue)")
            guard result == .authorized else {
                CameraLog.error("Browser: \(kind) authorization refused — \(denied.diagnosticReason)")
                throw denied
            }
        }
    }

    // MARK: ICDeviceBrowserDelegate

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        // Any camera is accepted. Model recognition, and whether the app writes to the body, are
        // decided later from the product name, so nothing is rejected here on a name the registry
        // might not match.
        guard let camera = device as? ICCameraDevice else { return }
        CameraLog.info("Browser: didAdd \(camera.name ?? "Fujifilm Camera") (usb \(String(format: "%04x:%04x", camera.usbVendorID, camera.usbProductID)))")
        AppLog.flushNow()   // plug and unplug are rare and are exactly what a reconnect crash follows
        arrivals.succeedAllWaiters(with: camera)
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        CameraLog.info("Browser: didRemove \(device.name ?? "camera")")
        AppLog.flushNow()
        guard let camera = device as? ICCameraDevice else { return }
        onDeviceRemoved?(camera)
    }

    func deviceBrowserWillSuspendOperations(_ browser: ICDeviceBrowser) {
        CameraLog.info("Browser: will suspend operations (app backgrounding)")
        onSuspend?()
    }

    func deviceBrowserDidSuspendOperations(_ browser: ICDeviceBrowser) {
        CameraLog.info("Browser: did suspend operations")
    }

    func deviceBrowserDidCancelSuspendOperations(_ browser: ICDeviceBrowser) {
        CameraLog.info("Browser: suspend canceled — returned to foreground before the timeout")
        onResume?()
    }

    func deviceBrowserDidResumeOperations(_ browser: ICDeviceBrowser) {
        CameraLog.info("Browser: did resume operations (app foregrounded)")
        onResume?()
    }
}

extension ICCameraDevice: DiscoveredCamera {
    @MainActor
    func makeTransport() -> CameraTransport {
        ImageCaptureTransport(cameraDevice: self)
    }
}
