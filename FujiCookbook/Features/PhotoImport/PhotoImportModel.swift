import CoreGraphics
import Foundation
import Observation

/// One visit to the import screen: open a source, show its card as a contact sheet, copy the
/// selected frames to the destination, and remember what was imported.
@MainActor
@Observable
final class PhotoImportModel {
    struct Summary: Equatable {
        var imported: Int
        /// Frames given a position. Nil when the import didn't add locations.
        var located: Int? = nil
        var failed: [String] = []
        var cancelled = false
    }

    enum Phase: Equatable {
        case opening
        case ready
        case importing(done: Int, total: Int)
        case finished(Summary)
        case failed(String)
    }

    private(set) var phase: Phase = .opening
    private(set) var sourceName: String
    /// Every frame on the card, in the order taken.
    private(set) var frames: [ImportFrame] = []
    private(set) var thumbnails: [ImportFrame.ID: CGImage] = [:]
    var selection: Set<ImportFrame.ID> = []
    /// Hide what an earlier import already copied.
    private(set) var showsOnlyNew = true
    var destination: PhotoImportDestination
    /// Add the position from the recorded tracks to each photo.
    var addsLocation = false
    /// How far the camera's clock was off (`CameraClockOffset`).
    var clockOffset: TimeInterval
    /// Every recorded position, loaded when the card opens.
    private(set) var matcher = GeoMatcher(points: [])

    @ObservationIgnored private let source: PhotoSource
    @ObservationIgnored private var ledger: PhotoImportLedger
    @ObservationIgnored private let makeWriter: (PhotoImportDestination) -> PhotoImportWriter
    @ObservationIgnored private let stagingRoot: URL
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailRequests: Set<ImportFrame.ID> = []
    @ObservationIgnored private let loadTrackPoints: () -> [GeoPoint]

    init(source: PhotoSource,
         ledger: PhotoImportLedger = PhotoImportLedger(),
         destination: PhotoImportDestination = .photoLibrary,
         stagingRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("photo-import", isDirectory: true),
         clockOffset: TimeInterval = CameraClockOffset.load(),
         loadTrackPoints: @escaping () -> [GeoPoint] = { LocationTrackStore.standard.allPoints() },
         makeWriter: @escaping (PhotoImportDestination) -> PhotoImportWriter = { $0.writer }) {
        self.source = source
        self.sourceName = source.displayName
        self.ledger = ledger
        self.destination = destination
        self.stagingRoot = stagingRoot
        self.makeWriter = makeWriter
        self.clockOffset = clockOffset
        self.loadTrackPoints = loadTrackPoints
    }

    // MARK: What the screen shows

    var newFrames: [ImportFrame] { frames.filter { !ledger.contains($0) } }
    var visibleFrames: [ImportFrame] { showsOnlyNew ? newFrames : frames }
    var days: [ImportDay] { ImportDay.days(from: visibleFrames) }
    var selectedFrames: [ImportFrame] { visibleFrames.filter { selection.contains($0.id) } }
    var isImporting: Bool { if case .importing = phase { return true } else { return false } }

    func isAlreadyImported(_ frame: ImportFrame) -> Bool { ledger.contains(frame) }

    /// Where a frame was taken, by the date the card lists for it: a preview for the screen. The
    /// import itself goes by the date in the downloaded file.
    func previewPosition(of frame: ImportFrame) -> GeoPoint? {
        frame.captureDate.flatMap { matcher.point(at: $0.addingTimeInterval(-clockOffset)) }
    }

    /// Frames dated more than two minutes ahead of now: the camera's clock is ahead, or set to a
    /// zone east of the phone's.
    func framesFromTheFuture(now: Date = .now) -> [ImportFrame] {
        frames.filter { ($0.captureDate.map { $0.addingTimeInterval(-clockOffset) } ?? .distantPast) > now.addingTimeInterval(120) }
    }

    // MARK: Opening

    /// `recipeSessionActive`: the recipe connection holds the camera in the other USB mode, and the
    /// two share one device, so opening over it would take its session away.
    func open(recipeSessionActive: Bool = false) async {
        phase = .opening
        guard !recipeSessionActive else {
            phase = .failed(PhotoImportError.recipeSessionActive.localizedDescription)
            return
        }
        do {
            let files = try await source.open()
            sourceName = source.displayName
            frames = ImportFrame.frames(from: files)
            matcher = GeoMatcher(points: ProcessInfo.processInfo.isMacCatalystApp ? [] : loadTrackPoints())
            addsLocation = !matcher.isEmpty
            // What is new is what a visit is usually for.
            selection = Set(newFrames.map(\.id))
            if newFrames.isEmpty { showsOnlyNew = false }
            phase = .ready
        } catch is CancellationError {
            // The screen was closed while the card was listing.
        } catch {
            await source.close()
            phase = .failed(error.localizedDescription)
        }
    }

    func close() async {
        importTask?.cancel()
        await importTask?.value
        await source.close()
        try? FileManager.default.removeItem(at: stagingRoot)
    }

    // MARK: Selection

    func toggle(_ frame: ImportFrame) {
        guard !isImporting else { return }
        selection.formSymmetricDifference([frame.id])
    }

    /// Switching the filter drops any selected frame it hides: what is imported is what is shown.
    func setShowsOnlyNew(_ onlyNew: Bool) {
        showsOnlyNew = onlyNew
        selection.formIntersection(visibleFrames.map(\.id))
    }

    func selectAll() { selection = Set(visibleFrames.map(\.id)) }
    func selectNone() { selection = [] }

    // MARK: Thumbnails

    /// Ask for a frame's picture once; the tile shows its placeholder until it arrives.
    func loadThumbnail(for frame: ImportFrame) {
        guard thumbnails[frame.id] == nil, thumbnailRequests.insert(frame.id).inserted else { return }
        Task {
            if let image = await source.thumbnail(for: frame.preview) { thumbnails[frame.id] = image }
        }
    }

    // MARK: Importing

    func startImport() {
        let selected = selectedFrames
        guard !selected.isEmpty, !isImporting else { return }
        importTask = Task { await runImport(selected) }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    /// Back to the contact sheet after a finished import, with what was copied now marked.
    func acknowledgeSummary() {
        guard case .finished = phase else { return }
        selection = Set(newFrames.map(\.id))
        if newFrames.isEmpty { showsOnlyNew = false }
        phase = .ready
    }

    /// Where the frame was taken, by the capture time in its own files, and writes it into the
    /// JPEG or HEIF copies. Nil when the track has nothing near that time.
    private func locate(_ downloaded: [(file: ImportFile, url: URL)], frame: ImportFrame) -> GeoPoint? {
        let stated = downloaded.lazy.compactMap { CaptureTime.date(ofFileAt: $0.url) }.first
        guard let taken = stated ?? frame.captureDate,
              let position = matcher.point(at: taken.addingTimeInterval(-clockOffset)) else { return nil }
        for entry in downloaded where entry.file.kind == .jpeg || entry.file.kind == .heif {
            GeoTagWriter.embed(position, into: entry.url)
        }
        return position
    }

    /// One frame at a time: download its files, hand them to the destination, record them. A frame
    /// that fails is named in the summary and the rest go on; nothing is recorded as imported that
    /// the destination didn't take.
    private func runImport(_ selected: [ImportFrame]) async {
        let writer = makeWriter(destination)
        var summary = Summary(imported: 0, located: addsLocation ? 0 : nil)
        phase = .importing(done: 0, total: selected.count)
        for (index, frame) in selected.enumerated() {
            if Task.isCancelled { summary.cancelled = true; break }
            let staging = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                var downloaded: [(file: ImportFile, url: URL)] = []
                for file in frame.files {
                    try Task.checkCancellation()
                    downloaded.append((file, try await source.download(file, to: staging)))
                }
                try Task.checkCancellation()
                let position = addsLocation ? locate(downloaded, frame: frame) : nil
                try await writer.write(downloaded, position: position)
                try ledger.record(frame.files)
                if position != nil { summary.located? += 1 }
                selection.remove(frame.id)
                summary.imported += 1
            } catch is CancellationError {
                summary.cancelled = true
            } catch {
                AppLog.error(.importExport, "Photo import failed for a frame — \(AppLog.bounded(error))")
                summary.failed.append("\(frame.preview.name): \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: staging)
            if summary.cancelled { break }
            phase = .importing(done: index + 1, total: selected.count)
        }
        importTask = nil
        phase = .finished(summary)
    }
}
