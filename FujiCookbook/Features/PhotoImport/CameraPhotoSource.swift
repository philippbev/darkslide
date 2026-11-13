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
    private var catalogWaiter: CheckedContinuation<Void, Never>?

    /// How long a card may take to list. A full card on a slow body takes a while; without a limit
    /// a camera that never finishes would leave the screen waiting forever.
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

    func open() async throws -> [ImportFile] {
        guard !SharedContainer.isLocalMacBuild else { throw PhotoImportError.localMacBuild }
        let found: any DiscoveredCamera
        do {
            found = try await Self.withTimeout(Self.discoveryTimeout) { [discovery] in
                try await discovery().firstCamera()
            }
        } catch let error as CameraError where error == .permissionDenied || error == .contentsAccessUnavailable {
            throw PhotoImportError.permissionDenied
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PhotoImportError.noCamera
        }
        guard let device = found as? ICCameraDevice else { throw PhotoImportError.noCamera }
        self.device = device
        displayName = device.name ?? "Camera"
        device.delegate = self
        CameraLog.info("PhotoImport: opening \(displayName)")

        if !device.hasOpenSession {
            do {
                try await device.requestOpenSession(options: nil)
            } catch {
                throw PhotoImportError.sourceFailed(error.localizedDescription)
            }
        }
        try await waitForCatalog(of: device)

        filesByID = [:]
        var files: [ImportFile] = []
        for case let item as ICCameraFile in device.mediaFiles ?? [] {
            guard let name = item.name else { continue }
            let folder = Self.path(of: item.parentFolder)
            let id = "\(folder)/\(name)"
            guard let file = ImportFile(id: id, name: name, folder: folder, byteSize: Int64(item.fileSize),
                                        captureDate: item.exifCreationDate ?? item.fileCreationDate) else { continue }
            filesByID[id] = item
            files.append(file)
        }
        CameraLog.info("PhotoImport: catalog lists \(files.count) importable file\(files.count == 1 ? "" : "s")")
        guard !files.isEmpty else { throw PhotoImportError.noPhotos }
        return files
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

    private func waitForCatalog(of device: ICCameraDevice) async throws {
        if device.contentCatalogPercentCompleted >= 100 { return }
        let timeout = Task { [weak self, catalogTimeout] in
            try? await Task.sleep(for: .seconds(catalogTimeout))
            guard !Task.isCancelled else { return }
            self?.catalogDidFinish()
        }
        await withCheckedContinuation { catalogWaiter = $0 }
        timeout.cancel()
        try Task.checkCancellation()
        guard device.contentCatalogPercentCompleted >= 100 else { throw PhotoImportError.catalogTimedOut }
    }

    private func catalogDidFinish() {
        catalogWaiter?.resume()
        catalogWaiter = nil
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
        catalogDidFinish()
        filesByID = [:]
        guard let device else { return }
        self.device = nil
        if device.hasOpenSession { try? await device.requestCloseSession(options: nil) }
        // The shared browser vends the same device to the recipe connection; only release the
        // delegate if it is still this source's.
        if device.delegate === self { device.delegate = nil }
        CameraLog.info("PhotoImport: closed \(displayName)")
    }
}

// ImageCaptureCore's delegate requirements are nonisolated; each hops to the main actor.
extension CameraPhotoSource: ICCameraDeviceDelegate {
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor in self.catalogDidFinish() }
    }

    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in
            CameraLog.info("PhotoImport: camera removed")
            self.catalogDidFinish()
        }
    }

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {}
    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
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
