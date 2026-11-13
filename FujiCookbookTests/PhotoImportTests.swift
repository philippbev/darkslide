import XCTest
import ImageIO
import Photos
@testable import FujiCookbook

/// A card that hands out whatever it was given, and counts what was asked of it.
@MainActor
final class FakePhotoSource: PhotoSource {
    let displayName = "X100VI"
    var files: [ImportFile]
    var openError: PhotoImportError?
    /// Names whose download fails.
    var failing: Set<String> = []
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var downloaded: [String] = []

    init(files: [ImportFile]) { self.files = files }

    func open() async throws -> [ImportFile] {
        openCount += 1
        if let openError { throw openError }
        return files
    }

    func thumbnail(for file: ImportFile) async -> CGImage? { nil }

    func download(_ file: ImportFile, to directory: URL) async throws -> URL {
        if failing.contains(file.name) {
            throw PhotoImportError.downloadFailed(file: file.name, detail: "unplugged")
        }
        downloaded.append(file.name)
        let url = directory.appendingPathComponent(file.name)
        try Data(repeating: 7, count: Int(file.byteSize)).write(to: url)
        return url
    }

    func close() async { closeCount += 1 }
}

/// A destination that remembers what it was handed.
final class RecordingWriter: PhotoImportWriter {
    private(set) var frames: [[String]] = []
    /// Whether each file was really on disk when the frame arrived.
    private(set) var filesExisted = true

    private(set) var positions: [GeoPoint?] = []

    func write(_ files: [(file: ImportFile, url: URL)], position: GeoPoint?) async throws {
        frames.append(files.map(\.file.name))
        positions.append(position)
        if files.contains(where: { !FileManager.default.fileExists(atPath: $0.url.path) }) { filesExisted = false }
    }
}

@MainActor
final class PhotoImportTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoImportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private let noon = Date(timeIntervalSince1970: 1_794_571_200) // 2026-11-13 12:00 UTC

    private func file(_ name: String, folder: String = "DCIM/100_FUJI", size: Int64 = 100,
                      at date: Date? = nil) throws -> ImportFile {
        try XCTUnwrap(ImportFile(id: "\(folder)/\(name)", name: name, folder: folder, byteSize: size,
                                 captureDate: date ?? noon))
    }

    private func model(_ source: FakePhotoSource, writer: PhotoImportWriter = RecordingWriter(),
                       ledger: String = "ledger.json") -> PhotoImportModel {
        PhotoImportModel(source: source, ledger: PhotoImportLedger(url: scratch.appendingPathComponent(ledger)),
                         stagingRoot: scratch.appendingPathComponent("staging"), clockOffset: 0,
                         loadTrackPoints: { [] }, makeWriter: { _ in writer })
    }

    private func runImport(_ model: PhotoImportModel) async {
        model.startImport()
        for _ in 0..<400 {
            if case .finished = model.phase { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("the import didn't finish")
    }

    // MARK: Files and frames

    func testOnlyPhotosAndMoviesAreImportable() {
        XCTAssertEqual(ImportFile.Kind.of(fileName: "DSCF0001.RAF"), .raw)
        XCTAssertEqual(ImportFile.Kind.of(fileName: "dscf0001.jpg"), .jpeg)
        XCTAssertEqual(ImportFile.Kind.of(fileName: "DSCF0001.HIF"), .heif)
        XCTAssertEqual(ImportFile.Kind.of(fileName: "DSCF0001.MOV"), .movie)
        XCTAssertNil(ImportFile.Kind.of(fileName: "FUJIFILM.DAT"))
        XCTAssertNil(ImportFile(id: "x", name: "AUTPRINT.MRK", folder: "MISC", byteSize: 1, captureDate: nil))
    }

    func testRawAndJPEGOfOneExposureAreOneFrame() throws {
        let frames = ImportFrame.frames(from: [try file("DSCF1284.RAF", size: 50_000), try file("DSCF1284.JPG", size: 9_000),
                                               try file("DSCF1285.JPG", at: noon.addingTimeInterval(60))])
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].formatLabel, "RAF+JPG")
        XCTAssertEqual(frames[0].preview.kind, .jpeg, "the catalog has a thumbnail for the JPEG on every body")
        XCTAssertEqual(frames[0].frameNumber, "1284")
        XCTAssertEqual(frames[0].byteSize, 59_000)
        XCTAssertEqual(frames[1].formatLabel, "JPG")
    }

    func testSameFrameNumberInAnotherFolderIsAnotherFrame() throws {
        let frames = ImportFrame.frames(from: [try file("DSCF0001.JPG", folder: "DCIM/100_FUJI"),
                                               try file("DSCF0001.JPG", folder: "DCIM/101_FUJI")])
        XCTAssertEqual(frames.count, 2, "the counter wraps at 9999 and starts a new folder")
        XCTAssertNotEqual(frames[0].id, frames[1].id)
    }

    func testFramesRunInTheOrderTakenAndUndatedOnesLast() throws {
        let undated = try XCTUnwrap(ImportFile(id: "u", name: "DSCF0009.JPG", folder: "DCIM/100_FUJI",
                                               byteSize: 1, captureDate: nil))
        let frames = ImportFrame.frames(from: [undated, try file("DSCF0002.JPG", at: noon.addingTimeInterval(10)),
                                               try file("DSCF0001.JPG", at: noon)])
        XCTAssertEqual(frames.map(\.frameNumber), ["0001", "0002", "0009"])
    }

    func testDaysRunNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let undated = try XCTUnwrap(ImportFile(id: "u", name: "DSCF0009.JPG", folder: "DCIM/100_FUJI",
                                               byteSize: 1, captureDate: nil))
        let frames = ImportFrame.frames(from: [try file("DSCF0001.JPG", at: noon.addingTimeInterval(-86_400)),
                                               try file("DSCF0002.JPG", at: noon), try file("DSCF0003.JPG", at: noon.addingTimeInterval(60)),
                                               undated])
        let days = ImportDay.days(from: frames, calendar: calendar)
        XCTAssertEqual(days.map { $0.frames.map(\.frameNumber) }, [["0002", "0003"], ["0001"], ["0009"]])
        XCTAssertNil(days.last?.day)
    }

    // MARK: Ledger

    func testLedgerRemembersAcrossLaunchesAndNeedsEveryFileOfAFrame() throws {
        let url = scratch.appendingPathComponent("ledger.json")
        let raw = try file("DSCF1284.RAF"), jpeg = try file("DSCF1284.JPG")
        let frame = ImportFrame.frames(from: [raw, jpeg])[0]
        var ledger = PhotoImportLedger(url: url)
        XCTAssertFalse(ledger.contains(frame))
        try ledger.record([jpeg])
        XCTAssertFalse(ledger.contains(frame), "a frame whose RAF never arrived isn't imported")
        try ledger.record([raw])
        XCTAssertTrue(PhotoImportLedger(url: url).contains(frame))
    }

    func testReusedFileNameIsANewFile() throws {
        var ledger = PhotoImportLedger(url: scratch.appendingPathComponent("ledger.json"))
        try ledger.record([try file("DSCF0001.JPG", size: 100)])
        let later = ImportFrame.frames(from: [try file("DSCF0001.JPG", size: 100, at: noon.addingTimeInterval(86_400))])[0]
        XCTAssertFalse(ledger.contains(later), "the counter wrapped: same name, another photo")
    }

    func testUnreadableLedgerStartsEmptyRatherThanFailing() throws {
        let url = scratch.appendingPathComponent("ledger.json")
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(PhotoImportLedger(url: url).keys.isEmpty)
    }

    // MARK: Destinations

    func testRawBesideARenderedFileIsTheAlternateAndAloneIsThePhoto() throws {
        let raw = try file("DSCF1284.RAF"), jpeg = try file("DSCF1284.JPG"), movie = try file("DSCF1290.MOV")
        XCTAssertEqual(PhotoLibraryImportWriter.resources(for: [jpeg, raw]), [.photo, .alternatePhoto])
        XCTAssertEqual(PhotoLibraryImportWriter.resources(for: [raw]), [.photo])
        XCTAssertEqual(PhotoLibraryImportWriter.resources(for: [movie]), [.video])
    }

    func testFolderDestinationCopiesSkipsTheSameFileAndKeepsADifferentOne() async throws {
        let folder = scratch.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = scratch.appendingPathComponent("DSCF1284.JPG")
        try Data(repeating: 1, count: 100).write(to: source)
        let photo = try file("DSCF1284.JPG", size: 100)
        let writer = FolderImportWriter(folder: folder)

        try await writer.write([(photo, source)], position: nil)
        try await writer.write([(photo, source)], position: nil)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["DSCF1284.JPG"],
                       "the same file a second time adds nothing")

        // Another photo under the same name: both are kept.
        let other = scratch.appendingPathComponent("other.JPG")
        try Data(repeating: 2, count: 250).write(to: other)
        try await writer.write([(try file("DSCF1284.JPG", size: 250), other)], position: nil)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["DSCF1284 (2).JPG", "DSCF1284.JPG"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("DSCF1284.JPG")).count, 100,
                       "the file that was there is untouched")
    }

    func testFolderDestinationThatCantBeWrittenLeavesNoHalfFrame() async throws {
        let folder = scratch.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jpeg = scratch.appendingPathComponent("DSCF1284.JPG")
        try Data(repeating: 1, count: 100).write(to: jpeg)
        let missing = scratch.appendingPathComponent("DSCF1284.RAF")

        do {
            try await FolderImportWriter(folder: folder).write([(try file("DSCF1284.JPG"), jpeg),
                                                                (try file("DSCF1284.RAF"), missing)], position: nil)
            XCTFail("a frame with a missing file must fail")
        } catch {
            XCTAssertTrue(error is PhotoImportError)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [],
                       "a JPEG without its RAF would look imported and not be")
    }

    // MARK: The import

    func testOpeningSelectsWhatIsNew() async throws {
        let source = FakePhotoSource(files: [try file("DSCF0001.JPG"), try file("DSCF0002.JPG", at: noon.addingTimeInterval(60))])
        let model = model(source)
        await model.open()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.sourceName, "X100VI")
        XCTAssertEqual(model.selectedFrames.map(\.frameNumber), ["0001", "0002"])
    }

    func testImportHandsWholeFramesToTheDestinationAndRemembersThem() async throws {
        let files = [try file("DSCF0001.RAF"), try file("DSCF0001.JPG"), try file("DSCF0002.JPG", at: noon.addingTimeInterval(60))]
        let source = FakePhotoSource(files: files)
        let writer = RecordingWriter()
        let first = model(source, writer: writer)
        await first.open()
        await runImport(first)

        XCTAssertEqual(first.phase, .finished(.init(imported: 2)))
        XCTAssertEqual(writer.frames, [["DSCF0001.JPG", "DSCF0001.RAF"], ["DSCF0002.JPG"]])
        XCTAssertTrue(writer.filesExisted, "the files are on disk while the destination takes them")
        first.acknowledgeSummary()
        XCTAssertEqual(first.phase, .ready)
        XCTAssertTrue(first.newFrames.isEmpty)
        XCTAssertFalse(first.showsOnlyNew, "with nothing new the sheet shows the card rather than an empty page")

        // The next connection offers nothing: the ledger outlives the screen.
        let second = model(FakePhotoSource(files: files), writer: RecordingWriter())
        await second.open()
        XCTAssertTrue(second.selectedFrames.isEmpty)
        XCTAssertEqual(second.visibleFrames.count, 2)
    }

    func testFrameThatFailsIsReportedAndStaysNew() async throws {
        let source = FakePhotoSource(files: [try file("DSCF0001.JPG"), try file("DSCF0002.RAF", at: noon.addingTimeInterval(60)),
                                             try file("DSCF0002.JPG", at: noon.addingTimeInterval(60))])
        source.failing = ["DSCF0002.RAF"]
        let writer = RecordingWriter()
        let model = model(source, writer: writer)
        await model.open()
        await runImport(model)

        guard case .finished(let summary) = model.phase else { return XCTFail("not finished") }
        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.failed.count, 1)
        XCTAssertEqual(writer.frames, [["DSCF0001.JPG"]], "a frame missing a file never reaches the destination")
        model.acknowledgeSummary()
        XCTAssertEqual(model.newFrames.map(\.frameNumber), ["0002"])
        XCTAssertEqual(model.selectedFrames.map(\.frameNumber), ["0002"], "ready to try again")
    }

    func testOnlySelectedFramesAreImported() async throws {
        let source = FakePhotoSource(files: [try file("DSCF0001.JPG"), try file("DSCF0002.JPG", at: noon.addingTimeInterval(60))])
        let writer = RecordingWriter()
        let model = model(source, writer: writer)
        await model.open()
        model.toggle(model.frames[0])
        await runImport(model)
        XCTAssertEqual(writer.frames, [["DSCF0002.JPG"]])
        XCTAssertEqual(source.downloaded, ["DSCF0002.JPG"])
    }

    func testHidingImportedFramesDropsThemFromTheSelection() async throws {
        let files = [try file("DSCF0001.JPG"), try file("DSCF0002.JPG", at: noon.addingTimeInterval(60))]
        var ledger = PhotoImportLedger(url: scratch.appendingPathComponent("ledger.json"))
        try ledger.record([files[0]])
        let model = model(FakePhotoSource(files: files))
        await model.open()
        XCTAssertEqual(model.selectedFrames.map(\.frameNumber), ["0002"])
        model.setShowsOnlyNew(false)
        model.selectAll()
        XCTAssertEqual(model.selectedFrames.count, 2)
        model.setShowsOnlyNew(true)
        XCTAssertEqual(model.selectedFrames.map(\.frameNumber), ["0002"], "what is imported is what is shown")
    }

    func testRecipeConnectionIsNotOpenedOver() async throws {
        let source = FakePhotoSource(files: [try file("DSCF0001.JPG")])
        let model = model(source)
        await model.open(recipeSessionActive: true)
        XCTAssertEqual(model.phase, .failed(PhotoImportError.recipeSessionActive.localizedDescription))
        XCTAssertEqual(source.openCount, 0, "the two share one device; opening would take the recipe session away")
    }

    func testCardThatListsNothingNamesTheUSBMode() async throws {
        let source = FakePhotoSource(files: [])
        source.openError = .noPhotos
        let model = model(source)
        await model.open()
        guard case .failed(let message) = model.phase else { return XCTFail("not failed") }
        XCTAssertTrue(message.contains("USB Card Reader"))
        XCTAssertEqual(source.closeCount, 1)
    }

    // MARK: Finding the camera

    func testCameraSearchThatNeverAnswersEndsInTheNoCameraMessage() async {
        let started = Date()
        do {
            _ = try await CameraPhotoSource.withTimeout(0.2) { () async throws -> Int in
                // A permission request whose answer never comes.
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                return 1
            }
            XCTFail("a search that never answers must end")
        } catch {
            XCTAssertEqual(error as? PhotoImportError, .noCamera)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testCameraSearchThatAnswersInTimeGivesItsAnswer() async throws {
        let value = try await CameraPhotoSource.withTimeout(5) { 42 }
        XCTAssertEqual(value, 42)
        do {
            _ = try await CameraPhotoSource.withTimeout(5) { () async throws -> Int in throw PhotoImportError.permissionDenied }
            XCTFail("the operation's own error comes through")
        } catch {
            XCTAssertEqual(error as? PhotoImportError, .permissionDenied)
        }
    }

    // MARK: Demo card and wording

    func testDemoCardSpansTwoDaysAndItsPicturesCarryTheirDate() async throws {
        let source = DemoPhotoSource(now: noon)
        let files = try await source.open()
        XCTAssertEqual(files.count, 9)
        XCTAssertEqual(ImportDay.days(from: ImportFrame.frames(from: files)).count, 2)

        let url = try await source.download(files[0], to: scratch)
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNotNil(exif?[kCGImagePropertyExifDateTimeOriginal], "the photo library files a picture by this date")
        let thumbnail = await source.thumbnail(for: files[0])
        XCTAssertNotNil(thumbnail)
    }

    func testDayHeadingsAndSummaryUseSpacesNotDots() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: .now)
        XCTAssertTrue(PhotoImportView.heading(for: today, calendar: calendar).hasPrefix("Today   "))
        XCTAssertTrue(PhotoImportView.heading(for: today.addingTimeInterval(-86_400), calendar: calendar).hasPrefix("Yesterday   "))
        XCTAssertEqual(PhotoImportView.heading(for: nil), "No Date")
        XCTAssertFalse(PhotoImportView.heading(for: today).contains("·"))

        let text = PhotoImportView.text(for: .init(imported: 1, failed: ["DSCF0002.JPG: unplugged"], cancelled: true),
                                        destination: .photoLibrary)
        XCTAssertTrue(text.contains("1 photo copied to Photo Library"))
        XCTAssertTrue(text.contains("Nothing on the card was changed"))
        XCTAssertTrue(text.contains("cancelled"))
        XCTAssertTrue(text.contains("DSCF0002.JPG"))
    }
}
