import CoreGraphics
import Foundation
import ImageIO

/// The PTP operations reading a camera's card needs. `ImageCaptureTransport` provides them; tests
/// supply their own.
@MainActor
protocol PhotoCardTransport: AnyObject {
    var productName: String { get }
    /// Called when the camera goes away.
    var onDisconnect: (@MainActor () -> Void)? { get set }
    func open() async throws
    func close() async
    func getObjectHandles(timeout: TimeInterval) async throws -> [UInt32]
    func getObjectInfo(_ handle: UInt32) async throws -> FujiPTP.ObjectInfo
    func getThumb(_ handle: UInt32) async throws -> Data
    func getObject(_ handle: UInt32, expectedBytes: Int) async throws -> Data
    /// The first bytes of a file, for its MakerNote. Read-only.
    func getPartialObject(_ handle: UInt32, offset: UInt32, maxBytes: UInt32) async throws -> Data
}

extension ImageCaptureTransport: PhotoCardTransport {}

/// What outlives one visit to the import screen while the camera stays attached: the PTP session,
/// and the metadata already read. Opening a session makes the camera index its card again, which
/// took about a minute on an X100VI with 2,000 frames; a second visit through the same session
/// lists at once. Unplugging the camera, or the recipe connection taking the device, ends it.
@MainActor
final class PTPCardCache {
    static let shared = PTPCardCache()

    fileprivate(set) var transport: PhotoCardTransport?
    var infos: [UInt32: FujiPTP.ObjectInfo] = [:]

    func adopt(_ transport: PhotoCardTransport) {
        self.transport = transport
        infos = [:]
        transport.onDisconnect = { [weak self, weak transport] in
            guard let self, self.transport === transport else { return }
            self.transport = nil
            self.infos = [:]
        }
    }

    func reset() async {
        let old = transport
        transport = nil
        infos = [:]
        await old?.close()
    }
}

/// The camera's card read over PTP directly, newest first and a portion at a time.
///
/// ImageCaptureCore's catalog asks the camera about every file before it hands over any: on an
/// X100VI with 2,000 frames that was two minutes of nothing (iPhone, 2026-11-13). One
/// `GetObjectHandles` lists every file's handle at once; the metadata (`GetObjectInfo`) is then
/// fetched only for the newest `firstBatch`, and for older ones in `nextBatch`s as the sheet
/// scrolls down.
///
/// Read-only: `GetObjectHandles`, `GetObjectInfo`, `GetThumb` and `GetObject`. Nothing on the card
/// is changed.
///
/// VERIFY on hardware: that the X100VI numbers its handles in the order the photos were taken, so
/// the highest are the newest, and that ImageCaptureCore's own listing, which still starts when the
/// session opens, doesn't hold these requests back.
@MainActor
final class PTPPhotoSource: PhotoSource {
    private let makeTransport: @MainActor () async throws -> PhotoCardTransport
    private let cache: PTPCardCache
    private let firstBatch: Int
    private let nextBatch: Int

    private var transport: PhotoCardTransport?
    /// Handles whose metadata hasn't been read yet, newest first.
    private var pending: [UInt32] = []
    private var handles: [String: UInt32] = [:]
    /// Previews already fetched, by file, so the tile and its simulation code share one read.
    private var previews: [String: Data] = [:]
    private var files: [ImportFile] = []
    private var objectCount = 0
    private var foldersSkipped = 0
    private var unreadable = 0

    private(set) var displayName = "Camera"

    /// How long the camera may take to list its handles; it indexes the card first.
    static let handlesTimeout: TimeInterval = 180

    static let indexingNote = "The camera is indexing its card. On a full card that takes a minute or two, once per connection: reopening this screen while the camera stays plugged in is quick."

    init(makeTransport: @escaping @MainActor () async throws -> PhotoCardTransport,
         cache: PTPCardCache? = nil,
         firstBatch: Int = 200, nextBatch: Int = 300) {
        self.makeTransport = makeTransport
        // A cache of its own unless given one: only the real camera shares `PTPCardCache.shared`.
        self.cache = cache ?? PTPCardCache()
        self.firstBatch = firstBatch
        self.nextBatch = nextBatch
    }

    var canLoadMore: Bool { !pending.isEmpty }

    func open(progress: @escaping @MainActor (CatalogProgress) -> Void,
              partial: @escaping @MainActor ([ImportFile]) -> Void) async throws -> [ImportFile] {
        let all: [UInt32]
        if let kept = cache.transport {
            // The session from an earlier visit: the camera has its index, unless the recipe
            // connection took the device since, which the first request finds out.
            PhotoImportTrace.note("PTP: reusing the session from an earlier visit")
            do {
                all = try await listHandles(on: kept, progress: progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                PhotoImportTrace.note("PTP: kept session no longer answers — \(error.localizedDescription)")
                await cache.reset()
                all = try await listHandles(on: try await openTransport(), progress: progress)
            }
        } else {
            all = try await listHandles(on: try await openTransport(), progress: progress)
        }
        // The camera may answer long after the screen was closed: indexing a full card takes a
        // minute, and the request doesn't stop for a cancelled task.
        try Task.checkCancellation()
        objectCount = all.count
        pending = all.sorted(by: >)
        files = []
        handles = [:]
        CameraLog.info("PhotoImport: PTP lists \(all.count) object handle\(all.count == 1 ? "" : "s")")
        try await loadBatch(firstBatch, progress: progress, partial: partial)
        PhotoImportTrace.note("PTP: first portion read — \(diagnostics)")
        CameraLog.info("PhotoImport: \(diagnostics)")
        AppLog.flushNow()
        guard !files.isEmpty else { throw PhotoImportError.noPhotos(diagnostics: diagnostics) }
        return files
    }

    private func openTransport() async throws -> PhotoCardTransport {
        PhotoImportTrace.note("PTP: finding the camera")
        let transport = try await makeTransport()
        PhotoImportTrace.note("PTP: camera found, opening the session")
        do {
            try await transport.open()
        } catch let error as PhotoImportError {
            throw error
        } catch {
            throw PhotoImportError.sourceFailed(error.localizedDescription)
        }
        PhotoImportTrace.note("PTP: session open")
        cache.adopt(transport)
        return transport
    }

    private func listHandles(on transport: PhotoCardTransport,
                             progress: @MainActor (CatalogProgress) -> Void) async throws -> [UInt32] {
        self.transport = transport
        displayName = transport.productName
        progress(CatalogProgress(percent: 0, files: 0, note: Self.indexingNote))
        do {
            let all = try await transport.getObjectHandles(timeout: Self.handlesTimeout)
            PhotoImportTrace.note("PTP: GetObjectHandles listed \(all.count) handles, highest \(all.max() ?? 0), lowest \(all.min() ?? 0)")
            return all
        } catch {
            PhotoImportTrace.note("PTP: GetObjectHandles failed — \(error.localizedDescription)")
            throw error
        }
    }

    func loadMore(progress: @escaping @MainActor (CatalogProgress) -> Void) async throws -> [ImportFile] {
        try await loadBatch(nextBatch, progress: progress, partial: { _ in })
        return files
    }

    /// The metadata of the next `count` handles. An object whose metadata the camera won't give is
    /// left out; a portion where it gives none at all is an error.
    private func loadBatch(_ count: Int, progress: @MainActor (CatalogProgress) -> Void,
                           partial: @MainActor ([ImportFile]) -> Void) async throws {
        guard !pending.isEmpty else { return }
        // Closed while the camera was busy: this visit is over.
        guard let transport else { throw CancellationError() }
        let batch = Array(pending.prefix(count))
        pending.removeFirst(batch.count)
        var read = 0
        var lastError: Error?
        for (index, handle) in batch.enumerated() {
            try Task.checkCancellation()
            do {
                let info: FujiPTP.ObjectInfo
                if let known = cache.infos[handle] {
                    info = known
                } else {
                    info = try await transport.getObjectInfo(handle)
                    cache.infos[handle] = info
                }
                read += 1
                if info.isFolder {
                    foldersSkipped += 1
                } else if let file = ImportFile(id: "\(handle)", name: info.filename,
                                                folder: String(format: "%08X", info.parentObject),
                                                byteSize: Int64(info.compressedSize),
                                                captureDate: FujiPTP.parseDateTime(info.captureDate)) {
                    handles[file.id] = handle
                    files.append(file)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                unreadable += 1
                lastError = error
            }
            if (index + 1) % 50 == 0 || index + 1 == batch.count {
                PhotoImportTrace.note("PTP: \(index + 1) of \(batch.count) object infos read, \(files.count) files")
            }
            if (index + 1) % 10 == 0 || index + 1 == batch.count {
                progress(CatalogProgress(percent: (index + 1) * 100 / batch.count, files: files.count))
                partial(files)
            }
        }
        if read == 0, let lastError {
            throw PhotoImportError.sourceFailed(lastError.localizedDescription)
        }
    }

    /// What the card answered, in one line for the error screen and the log.
    var diagnostics: String {
        "PTP  \(displayName)  \(objectCount) objects  \(handles.count) importable read  "
            + "\(foldersSkipped) folders  \(unreadable) unreadable  \(pending.count) not read yet  "
            + "listed \(CameraPhotoSource.order(of: files))"
    }

    func thumbnail(for file: ImportFile) async -> CGImage? {
        guard let data = await previewData(for: file),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The preview first, which costs nothing more: the tile already fetched it. Fujifilm's
    /// GetThumb answer is the bare embedded thumbnail, without the MakerNote (X100VI, 2026-11-15:
    /// no tile got a code), so then the file's own first bytes, where a JPEG's EXIF and a RAF's
    /// embedded JPEG sit. Both reads only; how each went is noted in the import trace.
    func filmSimulation(for file: ImportFile) async -> FilmSimulation? {
        if let preview = await previewData(for: file),
           let simulation = PreviewSimulation.read(preview, name: file.name) {
            traceSimulation("from the preview")
            return simulation
        }
        guard let transport, let handle = handles[file.id] else { return nil }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let head = try await transport.getPartialObject(handle, offset: 0, maxBytes: Self.headBytes)
            let simulation = PreviewSimulation.read(head, name: file.name)
            let elapsed = clock.now - start
            let milliseconds = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            traceSimulation("from \(head.count / 1024) KB of the file in \(milliseconds) ms: "
                            + (simulation?.dsCode ?? "no MakerNote found"))
            return simulation
        } catch {
            traceSimulation("GetPartialObject refused: \(error.localizedDescription)")
            return nil
        }
    }

    /// Enough for a JPEG's EXIF block (at most 64 KB) and for a RAF's header and the start of its
    /// embedded JPEG.
    static let headBytes: UInt32 = 160 * 1024

    /// The first dozen reads of a visit go to the trace, which holds counts and timings and no file
    /// names.
    private var simulationTraces = 0
    private func traceSimulation(_ line: String) {
        guard simulationTraces < 12 else { return }
        simulationTraces += 1
        PhotoImportTrace.note("Simulation \(line)")
    }

    /// The camera's preview of a file, fetched once (GetThumb, a read).
    private func previewData(for file: ImportFile) async -> Data? {
        if let cached = previews[file.id] { return cached }
        guard let transport, let handle = handles[file.id],
              let data = try? await transport.getThumb(handle), !data.isEmpty else { return nil }
        previews[file.id] = data
        return data
    }

    func download(_ file: ImportFile, to directory: URL) async throws -> URL {
        guard let transport, let handle = handles[file.id] else {
            throw PhotoImportError.downloadFailed(file: file.name, detail: "The camera no longer lists it.")
        }
        let data: Data
        do {
            data = try await transport.getObject(handle, expectedBytes: Int(file.byteSize))
        } catch {
            throw PhotoImportError.downloadFailed(file: file.name, detail: error.localizedDescription)
        }
        guard file.byteSize == 0 || Int64(data.count) == file.byteSize else {
            throw PhotoImportError.downloadFailed(file: file.name,
                detail: "The camera sent \(data.count) bytes for a \(file.byteSize)-byte file.")
        }
        let url = directory.appendingPathComponent(file.name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Leaves the session open in the cache for the next visit (see `PTPCardCache`).
    func close() async {
        transport = nil
    }
}

/// The camera's card: over PTP, newest first (`PTPPhotoSource`), and through ImageCaptureCore's
/// catalog (`CameraPhotoSource`) when the PTP route doesn't work on a body.
@MainActor
final class CameraCardSource: PhotoSource {
    private let primary: PhotoSource
    private let fallback: () -> PhotoSource
    private var active: PhotoSource

    init(primary: PhotoSource, fallback: @escaping () -> PhotoSource) {
        self.primary = primary
        self.fallback = fallback
        self.active = primary
    }

    /// The real camera: PTP first, the catalog after.
    static func camera() -> CameraCardSource {
        CameraCardSource(primary: PTPPhotoSource(makeTransport: {
            ImageCaptureTransport(cameraDevice: try await CameraPhotoSource.findCamera())
        }, cache: .shared), fallback: { CameraPhotoSource() })
    }

    var displayName: String { active.displayName }
    var canLoadMore: Bool { active.canLoadMore }

    func open(progress: @escaping @MainActor (CatalogProgress) -> Void,
              partial: @escaping @MainActor ([ImportFile]) -> Void) async throws -> [ImportFile] {
        guard !SharedContainer.isLocalMacBuild else { throw PhotoImportError.localMacBuild }
        active = primary
        do {
            return try await primary.open(progress: progress, partial: partial)
        } catch is CancellationError {
            throw CancellationError()
        } catch where Task.isCancelled {
            // The screen is gone; the catalog would only list the card for nobody.
            throw CancellationError()
        } catch let error as PhotoImportError where error == .noCamera || error == .permissionDenied {
            // No camera is no camera either way; the catalog would only wait to say so again.
            throw error
        } catch {
            CameraLog.error("PhotoImport: PTP listing failed, using the catalog — \(AppLog.bounded(error))")
            PhotoImportTrace.note("Falling back to the catalog — \(error.localizedDescription)")
            await primary.close()
            active = fallback()
            return try await active.open(progress: progress, partial: partial)
        }
    }

    func loadMore(progress: @escaping @MainActor (CatalogProgress) -> Void) async throws -> [ImportFile] {
        try await active.loadMore(progress: progress)
    }

    func thumbnail(for file: ImportFile) async -> CGImage? { await active.thumbnail(for: file) }
    func filmSimulation(for file: ImportFile) async -> FilmSimulation? { await active.filmSimulation(for: file) }
    func download(_ file: ImportFile, to directory: URL) async throws -> URL { try await active.download(file, to: directory) }
    func close() async { await active.close() }
}
