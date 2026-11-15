import CoreGraphics
import Foundation
import Observation

/// One visit to the import screen: open a source, show its card as a contact sheet, copy the
/// selected frames to the destination, and remember what was imported.
@MainActor
@Observable
final class PhotoImportModel {
    struct Summary: Equatable {
        /// Frames copied: a RAW+JPEG pair counts once.
        var imported: Int
        /// Files copied, the RAF and the JPEG of a pair each counting.
        var files = 0
        /// Frames given a position. Nil when the import didn't add locations.
        var located: Int? = nil
        var failed: [String] = []
        var cancelled = false
    }

    enum Phase: Equatable {
        /// Nil until the source first reports.
        case opening(CatalogProgress?)
        case ready
        case importing(done: Int, total: Int)
        case finished(Summary)
        case failed(String)
    }

    private(set) var phase: Phase = .opening(nil)
    /// The camera is still listing the card while the sheet already shows what it has so far.
    private(set) var isListing = false
    /// How far the listing has got, while `isListing` or `.opening`.
    private(set) var listingProgress: CatalogProgress?
    /// Why the listing stopped early, once some of the card is already on screen.
    private(set) var listingProblem: String?
    /// Older files are left to read (`PhotoSource.loadMore`).
    private(set) var canLoadMore = false
    private(set) var isLoadingMore = false
    private(set) var sourceName: String
    /// Every frame on the card, in the order taken.
    private(set) var frames: [ImportFrame] = []
    private(set) var thumbnails: [ImportFrame.ID: CGImage] = [:]
    /// Each frame's film simulation, for the code on its tile; a frame the camera gave none for is
    /// missing.
    private(set) var simulations: [ImportFrame.ID: FilmSimulation] = [:]
    var selection: Set<ImportFrame.ID> = []
    /// Hide what an earlier import already copied.
    private(set) var showsOnlyNew = true
    /// Which of each frame's files to copy. Remembered between visits.
    private(set) var fileChoice: ImportFileChoice
    /// Which days to show.
    private(set) var period: ImportPeriod = .all
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
    @ObservationIgnored private let preferences: UserDefaults
    /// Tiles shown while the first portion was still being listed: their simulations are read
    /// once it is, so the extra reads don't slow the listing down.
    @ObservationIgnored private var simulationsWaiting: [ImportFrame] = []

    init(source: PhotoSource,
         ledger: PhotoImportLedger = PhotoImportLedger(),
         destination: PhotoImportDestination = .photoLibrary,
         stagingRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("photo-import", isDirectory: true),
         clockOffset: TimeInterval = CameraClockOffset.load(),
         loadTrackPoints: @escaping () -> [GeoPoint] = { LocationTrackStore.standard.allPoints() },
         preferences: UserDefaults = .standard,
         makeWriter: @escaping (PhotoImportDestination) -> PhotoImportWriter = { $0.writer }) {
        self.source = source
        self.sourceName = source.displayName
        self.ledger = ledger
        self.destination = destination
        self.stagingRoot = stagingRoot
        self.makeWriter = makeWriter
        self.clockOffset = clockOffset
        self.loadTrackPoints = loadTrackPoints
        self.preferences = preferences
        self.fileChoice = ImportFileChoice.load(from: preferences)
    }

    // MARK: What the screen shows

    /// The frames the file choice and the period leave: what "All" counts.
    var eligibleFrames: [ImportFrame] {
        frames.filter { !$0.files(for: fileChoice).isEmpty && period.contains($0.captureDate) }
    }
    var newFrames: [ImportFrame] { eligibleFrames.filter { !ledger.contains($0, choice: fileChoice) } }
    var visibleFrames: [ImportFrame] { showsOnlyNew ? newFrames : eligibleFrames }
    var days: [ImportDay] { ImportDay.days(from: visibleFrames) }
    var selectedFrames: [ImportFrame] { visibleFrames.filter { selection.contains($0.id) } }
    var isImporting: Bool { if case .importing = phase { return true } else { return false } }

    func isAlreadyImported(_ frame: ImportFrame) -> Bool { ledger.contains(frame, choice: fileChoice) }

    /// The first and last day on the card, for choosing a period.
    var dateBounds: ClosedRange<Date>? {
        let dates = frames.compactMap(\.captureDate)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first...last
    }

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
        PhotoImportTrace.start("Opening \(source.displayName)")
        phase = .opening(nil)
        isListing = false
        listingProgress = nil
        listingProblem = nil
        guard !recipeSessionActive else {
            phase = .failed(PhotoImportError.recipeSessionActive.localizedDescription)
            return
        }
        do {
            let files = try await source.open(progress: { [weak self] progress in
                guard let self else { return }
                self.listingProgress = progress
                if case .opening = self.phase { self.phase = .opening(progress) }
            }, partial: { [weak self] files in
                self?.receive(files)
            })
            receive(files)
            isListing = false
            listingProgress = nil
            readWaitingSimulations()
            canLoadMore = source.canLoadMore
            // With older files still unread, "nothing new" only means nothing new so far.
            if newFrames.isEmpty, !canLoadMore { showsOnlyNew = false }
        } catch is CancellationError {
            // The screen was closed while the card was listing.
        } catch {
            PhotoImportTrace.note("Opening failed — \(error.localizedDescription)")
            if frames.isEmpty {
                await source.close()
                phase = .failed(error.localizedDescription)
            } else {
                // Part of the card is on screen and can still be imported.
                isListing = false
                listingProblem = error.localizedDescription
                readWaitingSimulations()
            }
        }
    }

    /// What the source has listed so far. The first files show the sheet; later ones extend it
    /// without touching the selection.
    private func receive(_ files: [ImportFile]) {
        guard !files.isEmpty else { return }
        sourceName = source.displayName
        frames = ImportFrame.frames(from: files)
        guard case .opening = phase else { return }
        matcher = GeoMatcher(points: ProcessInfo.processInfo.isMacCatalystApp ? [] : loadTrackPoints())
        addsLocation = !matcher.isEmpty
        // Nothing chosen in advance: a visit is usually for one day, picked with Select Day.
        selection = []
        isListing = true
        phase = .ready
        PhotoImportTrace.note("Sheet shown with \(frames.count) frames")
    }

    func close() async {
        importTask?.cancel()
        await importTask?.value
        await source.close()
        try? FileManager.default.removeItem(at: stagingRoot)
    }

    /// Read the next portion of older files: the sheet calls this when it is scrolled to its end.
    func loadOlder() {
        guard canLoadMore, !isLoadingMore, phase == .ready else { return }
        isLoadingMore = true
        listingProblem = nil
        Task {
            do {
                let files = try await source.loadMore { [weak self] progress in self?.listingProgress = progress }
                if !files.isEmpty { frames = ImportFrame.frames(from: files) }
            } catch is CancellationError {
            } catch {
                listingProblem = error.localizedDescription
            }
            listingProgress = nil
            canLoadMore = source.canLoadMore
            isLoadingMore = false
        }
    }

    // MARK: Selection

    func toggle(_ frame: ImportFrame) {
        guard !isImporting else { return }
        selection.formSymmetricDifference([frame.id])
    }

    /// Switching a filter drops any selected frame it hides: what is imported is what is shown.
    func setShowsOnlyNew(_ onlyNew: Bool) {
        showsOnlyNew = onlyNew
        dropHiddenSelection()
    }

    func setFileChoice(_ choice: ImportFileChoice) {
        fileChoice = choice
        choice.save(to: preferences)
        dropHiddenSelection()
    }

    func setPeriod(_ period: ImportPeriod) {
        self.period = period
        dropHiddenSelection()
    }

    private func dropHiddenSelection() {
        selection.formIntersection(visibleFrames.map(\.id))
    }

    func isSelected(_ day: ImportDay) -> Bool {
        !day.frames.isEmpty && day.frames.allSatisfy { selection.contains($0.id) }
    }

    /// Select every frame of the day, or, when all are, none of them.
    func toggle(_ day: ImportDay) {
        guard !isImporting else { return }
        let ids = Set(day.frames.map(\.id))
        if isSelected(day) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    func selectAll() { selection = Set(visibleFrames.map(\.id)) }
    func selectNone() { selection = [] }

    // MARK: Thumbnails

    /// Ask for a frame's picture once; the tile shows its placeholder until it arrives. Its film
    /// simulation follows, read from the start of the file (`PhotoSource.filmSimulation`): about
    /// 0.2 s a frame on an X100VI (2026-11-15), so only for tiles that appear, and only once the
    /// first portion of the card is listed.
    func loadThumbnail(for frame: ImportFrame) {
        guard thumbnails[frame.id] == nil, thumbnailRequests.insert(frame.id).inserted else { return }
        Task {
            if let image = await source.thumbnail(for: frame.preview) { thumbnails[frame.id] = image }
            if isListing {
                simulationsWaiting.append(frame)
            } else {
                await readSimulation(of: frame)
            }
        }
    }

    private func readWaitingSimulations() {
        let waiting = simulationsWaiting
        simulationsWaiting = []
        guard !waiting.isEmpty else { return }
        Task { for frame in waiting { await readSimulation(of: frame) } }
    }

    private func readSimulation(of frame: ImportFrame) async {
        let clock = ContinuousClock()
        let start = clock.now
        // The JPEG when the frame has one: its EXIF sits at the very start of the file.
        let carrier = frame.files.first { $0.kind == .jpeg } ?? frame.preview
        let simulation = await source.filmSimulation(for: carrier)
        if let simulation { simulations[frame.id] = simulation }
        AppLog.info(.importExport, "Import simulation: \(simulation?.dsCode ?? "none") in \(Self.milliseconds(clock.now - start)) ms")
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
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

    /// Back to the contact sheet after a finished import. A frame that failed stays selected, ready
    /// to try again.
    func acknowledgeSummary() {
        guard case .finished = phase else { return }
        dropHiddenSelection()
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
        let choice = fileChoice
        var summary = Summary(imported: 0, located: addsLocation ? 0 : nil)
        phase = .importing(done: 0, total: selected.count)
        for (index, frame) in selected.enumerated() {
            if Task.isCancelled { summary.cancelled = true; break }
            let staging = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                var downloaded: [(file: ImportFile, url: URL)] = []
                let chosen = frame.files(for: choice)
                for file in chosen {
                    try Task.checkCancellation()
                    downloaded.append((file, try await source.download(file, to: staging)))
                }
                try Task.checkCancellation()
                let position = addsLocation ? locate(downloaded, frame: frame) : nil
                try await writer.write(downloaded, position: position)
                try ledger.record(chosen)
                if position != nil { summary.located? += 1 }
                selection.remove(frame.id)
                summary.imported += 1
                summary.files += chosen.count
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
