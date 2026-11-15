import XCTest
import CoreGraphics
@testable import FujiCookbook

/// A card answering PTP from a table: per handle, its metadata (nil: the camera refuses it) and bytes.
@MainActor
private final class FakeCardTransport: PhotoCardTransport {
    let productName = "X100VI"
    var onDisconnect: (@MainActor () -> Void)?
    var objects: [UInt32: (info: FujiPTP.ObjectInfo?, data: Data)] = [:]
    var openError: Error?
    /// Thrown by the next handle listing, once: a session the recipe connection took over.
    var handlesError: Error?
    private(set) var infoRequests: [UInt32] = []
    private(set) var openCount = 0
    private(set) var closed = false
    private(set) var handlesTimeout: TimeInterval?

    func open() async throws {
        openCount += 1
        if let openError { throw openError }
    }
    func close() async { closed = true }
    func getObjectHandles(timeout: TimeInterval) async throws -> [UInt32] {
        handlesTimeout = timeout
        if let error = handlesError {
            handlesError = nil
            throw error
        }
        return Array(objects.keys).shuffled()
    }

    func getObjectInfo(_ handle: UInt32) async throws -> FujiPTP.ObjectInfo {
        infoRequests.append(handle)
        guard let info = objects[handle]?.info else { throw CameraError.ptpError(code: 0x2009) }
        return info
    }

    func getThumb(_ handle: UInt32) async throws -> Data { Data() }

    func getObject(_ handle: UInt32, expectedBytes: Int) async throws -> Data {
        objects[handle]?.data ?? Data()
    }

    private(set) var partialRequests: [(handle: UInt32, maxBytes: UInt32)] = []
    func getPartialObject(_ handle: UInt32, offset: UInt32, maxBytes: UInt32) async throws -> Data {
        partialRequests.append((handle, maxBytes))
        return (objects[handle]?.data ?? Data()).prefix(Int(maxBytes))
    }
}

/// A source that fails to open, or lists what it was given.
@MainActor
private final class StubSource: PhotoSource {
    let displayName: String
    var error: PhotoImportError?
    var files: [ImportFile] = []
    private(set) var opened = false

    init(_ name: String) { displayName = name }

    func open(progress: @escaping @MainActor (CatalogProgress) -> Void,
              partial: @escaping @MainActor ([ImportFile]) -> Void) async throws -> [ImportFile] {
        opened = true
        if let error { throw error }
        return files
    }
    func thumbnail(for file: ImportFile) async -> CGImage? { nil }
    func download(_ file: ImportFile, to directory: URL) async throws -> URL { directory }
    func close() async {}
}

@MainActor
final class PTPPhotoSourceTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let noon = Date(timeIntervalSince1970: 1_794_571_200) // 2026-11-13 12:00 UTC

    private func info(_ name: String, minute: Int, size: UInt32 = 4) -> FujiPTP.ObjectInfo {
        FujiPTP.ObjectInfo(objectFormat: 0x3801, compressedSize: size, filename: name, parentObject: 0x10,
                           captureDate: String(format: "20261113T12%02d00", minute))
    }

    /// Ten frames, handle n taken at minute n; handle 0x10 is the folder they're in.
    private func card() -> FakeCardTransport {
        let transport = FakeCardTransport()
        for n in 1...10 {
            transport.objects[UInt32(n)] = (info(String(format: "DSCF%04d.JPG", n), minute: n), Data(repeating: UInt8(n), count: 4))
        }
        transport.objects[0x10] = (FujiPTP.ObjectInfo(objectFormat: 0x3001, compressedSize: 0, filename: "100_FUJI",
                                                      associationType: 1), Data())
        return transport
    }

    // MARK: Datasets

    func testPTPDateTimeReadsLocalUTCAndOffsetForms() {
        XCTAssertEqual(FujiPTP.parseDateTime("20261113T120000", fallbackZone: utc), noon)
        XCTAssertEqual(FujiPTP.parseDateTime("20261113T120000Z", fallbackZone: TimeZone(secondsFromGMT: 3600)!), noon)
        XCTAssertEqual(FujiPTP.parseDateTime("20261113T130000+0100", fallbackZone: utc), noon)
        XCTAssertEqual(FujiPTP.parseDateTime("20261113T120000.5", fallbackZone: utc), noon)
        XCTAssertNil(FujiPTP.parseDateTime(""))
        XCTAssertNil(FujiPTP.parseDateTime("2026-11-13"))
    }

    func testObjectInfoCarriesFolderAndCaptureDate() throws {
        func ptpString(_ text: String) -> Data {
            guard !text.isEmpty else { return Data([0]) }
            var data = Data([UInt8(text.utf16.count + 1)])
            for unit in text.utf16 { data.appendLE(unit) }
            data.appendLE(UInt16(0))
            return data
        }
        var data = Data()
        data.appendLE(UInt32(0x0001_0001))   // StorageID
        data.appendLE(UInt16(0x3801))        // ObjectFormat
        data.appendLE(UInt16(0))             // ProtectionStatus
        data.appendLE(UInt32(12_345))        // CompressedSize
        data.append(Data(count: 38 - data.count))
        data.appendLE(UInt32(0x0000_0042))   // ParentObject
        data.appendLE(UInt16(0))             // AssociationType
        data.append(Data(count: 52 - data.count))
        data.append(ptpString("DSCF1284.JPG"))
        data.append(ptpString("20261113T120000"))
        data.append(ptpString(""))
        data.append(ptpString(""))

        let info = try FujiPTP.parseObjectInfo(data)
        XCTAssertEqual(info.filename, "DSCF1284.JPG")
        XCTAssertEqual(info.compressedSize, 12_345)
        XCTAssertEqual(info.parentObject, 0x42)
        XCTAssertEqual(info.captureDate, "20261113T120000")
        XCTAssertFalse(info.isFolder)
    }

    // MARK: Simulation

    /// GetThumb's bare thumbnail has no MakerNote, so the source reads the file's first bytes.
    func testWithoutAMakerNoteInThePreviewTheFilesHeadIsRead() async throws {
        let transport = card()
        let source = PTPPhotoSource(makeTransport: { transport }, firstBatch: 10, nextBatch: 10)
        let files = try await source.open(progress: { _ in }, partial: { _ in })
        let file = try XCTUnwrap(files.first)
        let simulation = await source.filmSimulation(for: file)
        XCTAssertNil(simulation, "the fake card's files carry no MakerNote")
        XCTAssertEqual(transport.partialRequests.count, 1)
        XCTAssertEqual(transport.partialRequests.first?.maxBytes, PTPPhotoSource.headBytes)
    }

    // MARK: Listing

    func testFirstPortionIsTheNewestAndMoreFollowsOnRequest() async throws {
        let transport = card()
        let source = PTPPhotoSource(makeTransport: { transport }, firstBatch: 4, nextBatch: 5)
        var reports: [CatalogProgress] = []
        let first = try await source.open(progress: { reports.append($0) }, partial: { _ in })

        // The four highest handles are the folder 0x10 and frames 10, 9, 8: the folder is skipped.
        XCTAssertEqual(first.map(\.name).sorted(), ["DSCF0008.JPG", "DSCF0009.JPG", "DSCF0010.JPG"],
                       "only the newest are asked about")
        XCTAssertEqual(transport.infoRequests.count, 4)
        XCTAssertEqual(source.displayName, "X100VI")
        XCTAssertTrue(source.canLoadMore)
        XCTAssertEqual(reports.last?.percent, 100)

        let more = try await source.loadMore { _ in }
        XCTAssertEqual(more.count, 8, "frames 7 to 3")
        let rest = try await source.loadMore { _ in }
        XCTAssertEqual(rest.count, 10)
        XCTAssertFalse(source.canLoadMore)
        XCTAssertTrue(source.diagnostics.contains("1 folders"))
    }

    func testObjectTheCameraRefusesIsLeftOutButAPortionOfRefusalsFails() async throws {
        let transport = card()
        transport.objects[10] = (nil, Data())
        let source = PTPPhotoSource(makeTransport: { transport }, firstBatch: 20)
        let files = try await source.open(progress: { _ in }, partial: { _ in })
        XCTAssertEqual(files.count, 9)
        XCTAssertTrue(source.diagnostics.contains("1 unreadable"))

        let refusing = FakeCardTransport()
        refusing.objects = [1: (nil, Data()), 2: (nil, Data())]
        do {
            _ = try await PTPPhotoSource(makeTransport: { refusing }).open(progress: { _ in }, partial: { _ in })
            XCTFail("a card that answers nothing can't be listed")
        } catch {
            guard case .sourceFailed = error as? PhotoImportError else { return XCTFail("\(error)") }
        }
    }

    func testDownloadWritesTheFileAndRefusesAShortOne() async throws {
        let transport = card()
        let source = PTPPhotoSource(makeTransport: { transport }, firstBatch: 20)
        let files = try await source.open(progress: { _ in }, partial: { _ in })
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let newest = try XCTUnwrap(files.first { $0.name == "DSCF0010.JPG" })
        let url = try await source.download(newest, to: scratch)
        XCTAssertEqual(try Data(contentsOf: url), Data(repeating: 10, count: 4))

        transport.objects[9] = (info("DSCF0009.JPG", minute: 9), Data(repeating: 9, count: 2))
        let short = try XCTUnwrap(files.first { $0.name == "DSCF0009.JPG" })
        do {
            _ = try await source.download(short, to: scratch)
            XCTFail("a file cut short isn't imported as if whole")
        } catch {
            guard case .downloadFailed = error as? PhotoImportError else { return XCTFail("\(error)") }
        }
        await source.close()
        XCTAssertFalse(transport.closed, "the session is kept for the next visit")
    }

    // MARK: Keeping the session

    func testCameraIsGivenTimeToIndexItsCard() async throws {
        let transport = card()
        var notes: [String?] = []
        _ = try await PTPPhotoSource(makeTransport: { transport }).open(progress: { notes.append($0.note) }, partial: { _ in })
        XCTAssertEqual(transport.handlesTimeout, PTPPhotoSource.handlesTimeout)
        XCTAssertGreaterThanOrEqual(PTPPhotoSource.handlesTimeout, 120, "a full card took over 20 seconds")
        XCTAssertEqual(notes.first ?? nil, PTPPhotoSource.indexingNote, "the screen says what the wait is")
    }

    func testSecondVisitReusesTheSessionAndWhatWasRead() async throws {
        let transport = card()
        let cache = PTPCardCache()
        var made = 0
        let make: @MainActor () async throws -> PhotoCardTransport = { made += 1; return transport }

        let first = PTPPhotoSource(makeTransport: make, cache: cache, firstBatch: 20)
        _ = try await first.open(progress: { _ in }, partial: { _ in })
        await first.close()
        let asked = transport.infoRequests.count

        let second = PTPPhotoSource(makeTransport: make, cache: cache, firstBatch: 20)
        let files = try await second.open(progress: { _ in }, partial: { _ in })
        XCTAssertEqual(files.count, 10)
        XCTAssertEqual(made, 1)
        XCTAssertEqual(transport.openCount, 1, "no second session, so no second indexing")
        XCTAssertEqual(transport.infoRequests.count, asked, "nothing read twice")
    }

    func testKeptSessionThatStoppedAnsweringIsOpenedAfresh() async throws {
        let old = card(), fresh = card()
        let cache = PTPCardCache()
        _ = try await PTPPhotoSource(makeTransport: { old }, cache: cache, firstBatch: 20).open(progress: { _ in }, partial: { _ in })
        old.handlesError = CameraError.disconnectedDuringOperation

        let files = try await PTPPhotoSource(makeTransport: { fresh }, cache: cache, firstBatch: 20)
            .open(progress: { _ in }, partial: { _ in })
        XCTAssertEqual(files.count, 10)
        XCTAssertTrue(old.closed)
        XCTAssertEqual(fresh.openCount, 1)
        XCTAssertTrue(cache.transport === fresh)
    }

    func testVisitClosedWhileTheCameraIndexesStopsWithoutListing() async throws {
        let transport = card()
        let source = PTPPhotoSource(makeTransport: { transport })
        let opening = Task { try await source.open(progress: { _ in }, partial: { _ in }) }
        opening.cancel()
        do {
            _ = try await opening.value
            XCTFail("a closed visit doesn't list the card")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertTrue(transport.infoRequests.isEmpty, "no metadata read for nobody")

        let primary = StubSource("PTP"), fallback = StubSource("Catalog")
        primary.error = .noPhotos(diagnostics: nil)
        let card = CameraCardSource(primary: primary, fallback: { fallback })
        let task = Task { try await card.open(progress: { _ in }, partial: { _ in }) }
        task.cancel()
        _ = try? await task.value
        XCTAssertFalse(fallback.opened, "no catalog listing after the screen closed")
    }

    func testUnpluggingTheCameraForgetsTheSession() async throws {
        let transport = card()
        let cache = PTPCardCache()
        _ = try await PTPPhotoSource(makeTransport: { transport }, cache: cache).open(progress: { _ in }, partial: { _ in })
        XCTAssertNotNil(cache.transport)
        transport.onDisconnect?()
        XCTAssertNil(cache.transport)
        XCTAssertTrue(cache.infos.isEmpty)
    }

    // MARK: Falling back

    func testCatalogTakesOverWhenPTPFailsButNotWithoutACamera() async throws {
        let primary = StubSource("PTP"), fallback = StubSource("Catalog")
        primary.error = .sourceFailed("PTP refused")
        fallback.files = [try XCTUnwrap(ImportFile(id: "1", name: "DSCF0001.JPG", folder: "", byteSize: 1, captureDate: noon))]
        let source = CameraCardSource(primary: primary, fallback: { fallback })
        let files = try await source.open(progress: { _ in }, partial: { _ in })
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(source.displayName, "Catalog")

        let noCamera = StubSource("PTP"), unused = StubSource("Catalog")
        noCamera.error = .noCamera
        do {
            _ = try await CameraCardSource(primary: noCamera, fallback: { unused }).open(progress: { _ in }, partial: { _ in })
            XCTFail("no camera is no camera")
        } catch {
            XCTAssertEqual(error as? PhotoImportError, .noCamera)
        }
        XCTAssertFalse(unused.opened)
    }

    func testEmptyPTPListingIsReportedRatherThanHandedToTheCatalog() async throws {
        // In “USB RAW Conv./Backup Restore” the camera lists nothing and the catalog never
        // finishes: the screen must say so instead of waiting.
        let primary = StubSource("PTP"), unused = StubSource("Catalog")
        primary.error = .noPhotos(diagnostics: "PTP  X100VI  0 objects")
        do {
            _ = try await CameraCardSource(primary: primary, fallback: { unused }).open(progress: { _ in }, partial: { _ in })
            XCTFail("an empty card is an answer")
        } catch {
            XCTAssertEqual(error as? PhotoImportError, .noPhotos(diagnostics: "PTP  X100VI  0 objects"))
            XCTAssertTrue(error.localizedDescription.contains("USB Card Reader"))
        }
        XCTAssertFalse(unused.opened)
    }

    // MARK: The sheet

    func testScrollingToTheEndLoadsOlderPhotos() async throws {
        let transport = card()
        let model = PhotoImportModel(source: PTPPhotoSource(makeTransport: { transport }, firstBatch: 4, nextBatch: 20),
                                     ledger: PhotoImportLedger(url: FileManager.default.temporaryDirectory
                                         .appendingPathComponent("ledger-\(UUID().uuidString).json")),
                                     clockOffset: 0, loadTrackPoints: { [] },
                                     preferences: UserDefaults(suiteName: "PTPPhotoSourceTests-\(UUID().uuidString)")!)
        await model.open()
        XCTAssertEqual(model.frames.count, 3)
        XCTAssertTrue(model.canLoadMore)
        XCTAssertTrue(model.showsOnlyNew, "nothing new so far isn't nothing new on the card")

        model.loadOlder()
        for _ in 0..<400 where model.isLoadingMore || model.canLoadMore { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.frames.count, 10)
        XCTAssertFalse(model.canLoadMore)
    }
}
