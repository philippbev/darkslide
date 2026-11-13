import CoreGraphics
import Foundation
import ImageCaptureCore
import ImageIO

/// The camera's card over USB, through ImageCaptureCore's content catalog.
///
/// Its own session, apart from the recipe connection (`ImageCaptureTransport`): a Fujifilm body
/// shows its card in “USB Card Reader” mode and its recipe properties in “USB RAW Conv./Backup
/// Restore”, never both, so the two are never open together.
///
/// It reads and nothing else: it lists files, asks for thumbnails and downloads copies. It sends no
/// PTP command of its own and passes no delete or truncate option.
///
/// VERIFY on hardware: not yet run against a camera. What a body lists in each USB mode, and how
/// long the catalog takes on a full card, are assumptions until it has been.
@MainActor
final class CameraPhotoSource: NSObject, PhotoSource {
    private let discovery: @MainActor () -> CameraDiscovery
    private var device: ICCameraDevice?
    private var filesByID: [String: ICCameraFile] = [:]
    /// Set when the camera goes away or the screen closes, to end a listing in progress.
    private var isEnded = false
    /// Set by `deviceDidBecomeReady(withCompleteContentCatalog:)`, the one signal that the card has
    /// been listed. `contentCatalogPercentCompleted` alone isn't: it can read 100 before a single
    /// file has arrived.
    private var catalogIsComplete = false
    /// Files the camera has announced through `didAdd`, for the diagnostics.
    private var announcedItems = 0

    /// How long a listing at 100 % may go on without the camera's done signal before it is taken
    /// as done. Not a limit on the listing itself: 2,000 frames took minutes on an X100VI.
    private let catalogTimeout: TimeInterval

    private(set) var displayName = "Camera"

    init(discovery: @escaping @MainActor () -> CameraDiscovery = { CameraDeviceBrowser.shared },
         catalogTimeout: TimeInterval = 60) {
        self.discovery = discovery
        self.catalogTimeout = catalogTimeout
    }

    /// How long finding a camera may take in all, the permission requests included. Discovery's own
    /// wait covers only a camera's arrival; a permission request the system never answers (seen on a
    /// locally signed Mac build) would otherwise leave the screen waiting with no way to tell why.
    static let discoveryTimeout: TimeInterval = 30

    func open(progress: @escaping @MainActor (CatalogProgress) -> Void,
              partial: @escaping @MainActor ([ImportFile]) -> Void) async throws -> [ImportFile] {
        guard !SharedContainer.isLocalMacBuild else { throw PhotoImportError.localMacBuild }
        let device = try await Self.findCamera(discovery: discovery)
        self.device = device
        isEnded = false
        catalogIsComplete = false
        announcedItems = 0
        displayName = device.name ?? "Camera"
        device.delegate = self
        CameraLog.info("PhotoImport: opening \(displayName)")

        PhotoImportTrace.note("Catalog: camera found, session \(device.hasOpenSession ? "already open" : "opening")")
        if !device.hasOpenSession {
            do {
                try await device.requestOpenSession(options: Self.sessionOptions)
            } catch {
                throw PhotoImportError.sourceFailed(error.localizedDescription)
            }
        }
        try await waitForCatalog(of: device, progress: progress, partial: partial)
        displayName = device.name ?? displayName

        let (files, skipped, listed) = collectFiles(of: device)
        let diagnostics = Self.diagnostics(of: device, mediaFiles: listed, importable: files.count,
                                           announced: announcedItems, catalogComplete: catalogIsComplete,
                                           skipped: skipped, order: Self.order(of: files))
        CameraLog.info("PhotoImport: \(diagnostics)")
        AppLog.flushNow()
        guard !files.isEmpty else { throw PhotoImportError.noPhotos(diagnostics: diagnostics) }
        return files
    }

    /// The attached camera, waiting `discoveryTimeout` at most, the permission requests included.
    static func findCamera(discovery: @escaping @MainActor () -> CameraDiscovery = { CameraDeviceBrowser.shared })
        async throws -> ICCameraDevice {
        let found: any DiscoveredCamera
        do {
            found = try await withTimeout(discoveryTimeout) { try await discovery().firstCamera() }
        } catch let error as CameraError where error == .permissionDenied || error == .contentsAccessUnavailable {
            throw PhotoImportError.permissionDenied
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PhotoImportError.noCamera
        }
        guard let device = found as? ICCameraDevice else { throw PhotoImportError.noCamera }
        return device
    }

    /// Asks for the card newest first, so the days an import is usually for are listed first.
    ///
    /// VERIFY on hardware: Apple documents the key but not its value. This passes
    /// `ComparisonResult.orderedDescending`; the diagnostics line records the order the camera
    /// actually listed in. A body that ignores it lists oldest first, which still works, only slower.
    static var sessionOptions: [ICSessionOptions: Any] {
        [.enumerationChronologicalOrder: NSNumber(value: ComparisonResult.orderedDescending.rawValue)]
    }

    /// Every importable file the camera has listed so far, refreshing what downloads and thumbnails
    /// look up. Also the names it skipped and how many media files it listed in all.
    private func collectFiles(of device: ICCameraDevice) -> (files: [ImportFile], skipped: [String], listed: Int) {
        var byID: [String: ICCameraFile] = [:]
        var files: [ImportFile] = []
        var skipped: [String] = []
        let listed = device.mediaFiles ?? []
        for case let item as ICCameraFile in listed {
            guard let name = item.name else { continue }
            let folder = Self.path(of: item.parentFolder)
            let id = "\(folder)/\(name)"
            guard let file = ImportFile(id: id, name: name, folder: folder, byteSize: Int64(item.fileSize),
                                        captureDate: item.exifCreationDate ?? item.fileCreationDate) else {
                if skipped.count < 5 { skipped.append(name) }
                continue
            }
            byID[id] = item
            files.append(file)
        }
        filesByID = byID
        return (files, skipped, listed.count)
    }

    /// "newest first", "oldest first" or "mixed": how the first files listed run, for the diagnostics.
    static func order(of files: [ImportFile]) -> String {
        let dates = files.prefix(50).compactMap(\.captureDate)
        guard dates.count >= 2 else { return "unknown" }
        if dates == dates.sorted(by: >) { return "newest first" }
        if dates == dates.sorted() { return "oldest first" }
        return "mixed"
    }

    /// `operation`, or `PhotoImportError.noCamera` once `seconds` have passed, whichever comes first.
    /// The operation is cancelled then; one that never returns is left behind rather than waited
    /// for, which a task group would do.
    static func withTimeout<T>(_ seconds: TimeInterval,
                               _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let outcome = FirstOutcome()
            let work = Task { @MainActor in
                do {
                    let value = try await operation()
                    if outcome.claim() { continuation.resume(returning: value) }
                } catch {
                    if outcome.claim() { continuation.resume(throwing: error) }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                guard outcome.claim() else { return }
                work.cancel()
                continuation.resume(throwing: PhotoImportError.noCamera)
            }
        }
    }

    /// Lets exactly one of the two racers resume the continuation.
    @MainActor
    private final class FirstOutcome {
        private var claimed = false
        func claim() -> Bool {
            defer { claimed = true }
            return !claimed
        }
    }

    /// Until the camera says its card is listed, handing over what it has listed whenever that
    /// grows. No time limit while it is below 100 %: an X100VI sat at 0 % for over a minute before
    /// its first file (iPhone, 2026-11-13), and the screen says so and can be closed. At 100 % without
    /// the signal, `catalogTimeout` without progress ends the wait. A camera that says it's done
    /// with nothing listed gets a few seconds more, for files it announces after the signal.
    private func waitForCatalog(of device: ICCameraDevice,
                                progress: @MainActor (CatalogProgress) -> Void,
                                partial: @MainActor ([ImportFile]) -> Void) async throws {
        // Listed on an earlier visit, through the session left open (see `close()`): nothing to wait
        // for. Only with files in it: a listing at 100 % with none is the one that hasn't started.
        if device.contentCatalogPercentCompleted >= 100, !(device.mediaFiles ?? []).isEmpty {
            catalogIsComplete = true
        }
        var listed = 0
        var lastPercent = -1
        var lastChange = Date()
        while !catalogIsComplete {
            guard !isEnded else { throw PhotoImportError.sourceFailed("The camera was disconnected.") }
            let percent = Int(device.contentCatalogPercentCompleted)
            let count = device.mediaFiles?.count ?? 0
            if count != listed || percent != lastPercent {
                PhotoImportTrace.note("Catalog: \(percent)%, \(count) media files")
                lastChange = Date()
                lastPercent = percent
                if count != listed {
                    listed = count
                    partial(collectFiles(of: device).files)
                }
            }
            let idle = Date().timeIntervalSince(lastChange)
            progress(CatalogProgress(percent: percent, files: filesByID.count, idleSeconds: Int(idle)))
            if percent >= 100, idle > catalogTimeout { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        progress(CatalogProgress(percent: 100, files: max(filesByID.count, device.mediaFiles?.count ?? 0)))
        for _ in 0..<10 where (device.mediaFiles ?? []).isEmpty {
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    /// What the camera answered, in one line for the error screen and the log.
    private static func diagnostics(of device: ICCameraDevice, mediaFiles: Int, importable: Int, announced: Int,
                                    catalogComplete: Bool, skipped: [String], order: String) -> String {
        var parts = [
            "device \(device.name ?? "unnamed")",
            String(format: "usb %04x:%04x", device.usbVendorID, device.usbProductID),
            "catalog \(device.contentCatalogPercentCompleted)%\(catalogComplete ? " complete" : "")",
            "items \(device.contents?.count ?? 0) top-level, \(mediaFiles) media, \(announced) announced",
            "importable \(importable)",
            "listed \(order)",
            "PTP \(device.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue) ? "yes" : "no")"
        ]
        if !skipped.isEmpty { parts.append("skipped \(skipped.joined(separator: " "))") }
        return parts.joined(separator: "  ")
    }

    private static func path(of folder: ICCameraFolder?) -> String {
        var names: [String] = []
        var current = folder
        while let next = current {
            if let name = next.name { names.insert(name, at: 0) }
            current = next.parentFolder
        }
        return names.joined(separator: "/")
    }

    func thumbnail(for file: ImportFile) async -> CGImage? {
        guard let item = filesByID[file.id] else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            item.requestThumbnailData(options: [.imageSourceThumbnailMaxPixelSize: 360]) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func download(_ file: ImportFile, to directory: URL) async throws -> URL {
        guard let item = filesByID[file.id] else {
            throw PhotoImportError.downloadFailed(file: file.name, detail: "The camera no longer lists it.")
        }
        // Nothing but where to put the copy: no delete, no truncate, the card stays as it is.
        let options: [ICDownloadOption: Any] = [.downloadsDirectoryURL: directory,
                                                .saveAsFilename: file.name,
                                                .overwrite: true]
        let saved: String = try await withCheckedThrowingContinuation { continuation in
            _ = item.requestDownload(options: options) { name, error in
                if let error {
                    continuation.resume(throwing: PhotoImportError.downloadFailed(file: file.name,
                                                                                  detail: error.localizedDescription))
                } else {
                    continuation.resume(returning: name ?? file.name)
                }
            }
        }
        return directory.appendingPathComponent(saved)
    }

    func close() async {
        isEnded = true
        filesByID = [:]
        guard let device else { return }
        self.device = nil
        // The session stays open while the camera is attached: closing it throws away the card's
        // listing, which takes minutes on a full card, and the next visit would wait for all of it
        // again. Unplugging the camera ends it. The recipe connection reuses an open session.
        // The shared browser vends the same device to the recipe connection; only release the
        // delegate if it is still this source's.
        if device.delegate === self { device.delegate = nil }
        CameraLog.info("PhotoImport: closed \(displayName)")
    }
}

// ImageCaptureCore's delegate requirements are nonisolated; each hops to the main actor.
extension CameraPhotoSource: ICCameraDeviceDelegate {
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor in self.catalogIsComplete = true }
    }

    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in
            CameraLog.info("PhotoImport: camera removed")
            self.isEnded = true
        }
    }

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {}
    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        let count = items.count
        Task { @MainActor in self.announcedItems += count }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?,
                                  for item: ICCameraItem, error: (any Error)?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?,
                                  for item: ICCameraItem, error: (any Error)?) {}
    nonisolated func cameraDeviceDidEnumerateItems(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}
