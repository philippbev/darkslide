import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FujiCookbook

@MainActor
final class GeotaggingTests: XCTestCase {
    private var scratch: URL!
    private let noon = Date(timeIntervalSince1970: 1_794_571_200) // 2026-11-13 12:00 UTC

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("GeotaggingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func point(_ seconds: TimeInterval, _ lat: Double, _ lon: Double, altitude: Double? = nil) -> GeoPoint {
        GeoPoint(timestamp: noon.addingTimeInterval(seconds), latitude: lat, longitude: lon, altitude: altitude)
    }

    /// A small JPEG with a capture time, as a camera writes one.
    private func jpeg(named name: String = "DSCF0001.JPG", taken: String = "2026:11:13 12:01:00",
                      offset: String? = "+00:00") throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for x in 0..<64 {
            context.setFillColor(red: CGFloat(x) / 64, green: 0.4, blue: 1 - CGFloat(x) / 64, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: 48))
        }
        let image = try XCTUnwrap(context.makeImage())
        var exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: taken]
        if let offset { exif[kCGImagePropertyExifOffsetTimeOriginal] = offset }
        let url = scratch.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: exif,
                                                        kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func pixels(of url: URL) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try XCTUnwrap(image.dataProvider?.data as Data?)
    }

    // MARK: Recording

    func testRecorderKeepsPreciseFixesThatMovedOrAreAMinuteLater() {
        let first = point(0, 38.5, -28.5)
        XCTAssertTrue(LocationTrack.shouldKeep(first, after: nil))
        var imprecise = point(5, 38.6, -28.5); imprecise.horizontalAccuracy = 500
        XCTAssertFalse(LocationTrack.shouldKeep(imprecise, after: first))
        var invalid = point(5, 38.6, -28.5); invalid.horizontalAccuracy = -1
        XCTAssertFalse(LocationTrack.shouldKeep(invalid, after: first))
        XCTAssertFalse(LocationTrack.shouldKeep(point(-5, 38.6, -28.5), after: first), "older than the last fix")
        XCTAssertFalse(LocationTrack.shouldKeep(point(10, 38.50001, -28.5), after: first), "a metre away, ten seconds later")
        XCTAssertTrue(LocationTrack.shouldKeep(point(10, 38.5005, -28.5), after: first), "fifty metres on")
        XCTAssertTrue(LocationTrack.shouldKeep(point(61, 38.5, -28.5), after: first), "standing still still leaves a point a minute")
    }

    func testStoreKeepsTracksNewestFirstAndMergesTheirPoints() throws {
        let store = LocationTrackStore(directory: scratch.appendingPathComponent("tracks"))
        let older = LocationTrack(startedAt: noon, endedAt: noon.addingTimeInterval(60), points: [point(0, 1, 1), point(60, 2, 2)])
        let newer = LocationTrack(startedAt: noon.addingTimeInterval(3600), points: [point(3600, 3, 3)])
        try store.save(older)
        try store.save(newer)
        try Data("broken".utf8).write(to: store.directory.appendingPathComponent("junk.json"))

        XCTAssertEqual(store.all().map(\.id), [newer.id, older.id], "a file that can't be read is skipped")
        XCTAssertEqual(store.allPoints().map(\.latitude), [1, 2, 3])
        store.delete(older.id)
        XCTAssertEqual(store.all().map(\.id), [newer.id])
    }

    // MARK: Matching

    func testPhotoBetweenTwoCloseFixesIsPlacedBetweenThem() throws {
        let matcher = GeoMatcher(points: [point(120, 38.6, -28.4, altitude: 20), point(0, 38.5, -28.5, altitude: 10)])
        let found = try XCTUnwrap(matcher.point(at: noon.addingTimeInterval(30)))
        XCTAssertEqual(found.latitude, 38.525, accuracy: 1e-9)
        XCTAssertEqual(found.longitude, -28.475, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(found.altitude), 12.5, accuracy: 1e-9)
        XCTAssertEqual(found.timestamp, noon.addingTimeInterval(30))
    }

    func testAcrossALongGapTheNearerFixCountsOnlyIfItIsClose() throws {
        // Recording stopped for an hour in between.
        let matcher = GeoMatcher(points: [point(0, 1, 1), point(3600, 2, 2)])
        XCTAssertEqual(matcher.point(at: noon.addingTimeInterval(120))?.latitude, 1)
        XCTAssertEqual(matcher.point(at: noon.addingTimeInterval(3500))?.latitude, 2)
        XCTAssertNil(matcher.point(at: noon.addingTimeInterval(1800)), "better no location than a wrong one")
    }

    func testPhotoBeforeOrAfterTheTrackCountsOnlyIfClose() {
        let matcher = GeoMatcher(points: [point(0, 1, 1), point(60, 1.001, 1)])
        XCTAssertEqual(matcher.point(at: noon.addingTimeInterval(-240))?.latitude, 1)
        XCTAssertNil(matcher.point(at: noon.addingTimeInterval(-400)))
        XCTAssertNil(matcher.point(at: noon.addingTimeInterval(60 + 400)))
        XCTAssertNil(GeoMatcher(points: []).point(at: noon))
    }

    // MARK: Capture time and the camera clock

    func testCaptureTimeUsesTheZoneTheFileStatesElseThePhones() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        XCTAssertEqual(CaptureTime.date(dateTimeOriginal: "2026:11:13 13:00:00", offset: "+01:00", fallbackZone: .gmt), noon)
        XCTAssertEqual(CaptureTime.date(dateTimeOriginal: "2026:11:13 13:00:00", fallbackZone: berlin), noon)
        XCTAssertEqual(CaptureTime.date(dateTimeOriginal: "2026:11:13 02:00:00", offset: "-10:00", fallbackZone: berlin), noon)
        XCTAssertEqual(CaptureTime.date(dateTimeOriginal: "2026:11:13 12:00:00", subsecond: "25", offset: "+00:00"),
                       noon.addingTimeInterval(0.25))
        XCTAssertNil(CaptureTime.date(dateTimeOriginal: "garbage"))
        XCTAssertNil(CaptureTime.zone(fromOffset: "01:00"))
    }

    func testCaptureTimeIsReadFromTheFile() throws {
        XCTAssertEqual(CaptureTime.date(ofFileAt: try jpeg(taken: "2026:11:13 12:01:00")), noon.addingTimeInterval(60))
    }

    func testClockOffsetLabel() {
        XCTAssertEqual(CameraClockOffset.label(0), "In Sync")
        XCTAssertEqual(CameraClockOffset.label(20), "In Sync")
        XCTAssertEqual(CameraClockOffset.label(180), "Ahead 3 min")
        XCTAssertEqual(CameraClockOffset.label(-3900), "Behind 1 h 5 min")
        XCTAssertEqual(CameraClockOffset.label(7200), "Ahead 2 h")
    }

    // MARK: Writing

    func testPositionIsEmbeddedWithoutReencodingThePicture() throws {
        let url = try jpeg()
        let before = try pixels(of: url)
        XCTAssertFalse(GeoTagWriter.hasPosition(url))

        XCTAssertTrue(GeoTagWriter.embed(point(60, -38.5, -28.25, altitude: -3), into: url))

        XCTAssertEqual(try pixels(of: url), before, "the picture is copied, not compressed again")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitude] as? Double ?? 0, 38.5, accuracy: 1e-6)
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitudeRef] as? String, "S")
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitudeRef] as? String, "W")
        XCTAssertEqual(gps[kCGImagePropertyGPSAltitudeRef] as? Int, 1)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:11:13 12:01:00",
                       "the camera's own metadata survives")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), ["DSCF0001.JPG"],
                       "no temporary file is left behind")
    }

    func testFileImageIOCantWriteIsLeftAsItWas() throws {
        let url = scratch.appendingPathComponent("DSCF0001.RAF")
        let bytes = Data("FUJIFILMCCD-RAW not really".utf8)
        try bytes.write(to: url)
        XCTAssertFalse(GeoTagWriter.embed(point(0, 1, 1), into: url))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testSidecarStatesThePositionTheWayXMPWritesIt() throws {
        XCTAssertEqual(GeoTagWriter.sidecarName(for: "DSCF1284.RAF"), "DSCF1284.xmp")
        XCTAssertEqual(GeoTagWriter.xmpCoordinate(38.5, positive: "N", negative: "S"), "38,30.000000N")
        XCTAssertEqual(GeoTagWriter.xmpCoordinate(-28.25, positive: "E", negative: "W"), "28,15.000000W")

        let url = try XCTUnwrap(GeoTagWriter.writeSidecar(point(0, 38.5, -28.25, altitude: 41.5),
                                                          besideFileNamed: "DSCF1284.RAF", in: scratch))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("exif:GPSLatitude=\"38,30.000000N\""))
        XCTAssertTrue(text.contains("exif:GPSLongitude=\"28,15.000000W\""))
        XCTAssertTrue(text.contains("exif:GPSAltitude=\"4150/100\""))
        XCTAssertTrue(text.contains("exif:GPSTimeStamp=\"2026-11-13T12:00:00Z\""))
        XCTAssertTrue(XMLParser(data: Data(text.utf8)).parse(), "a sidecar other apps can parse")

        // One already there may hold the user's edits.
        try Data("mine".utf8).write(to: url)
        XCTAssertNil(try GeoTagWriter.writeSidecar(point(0, 1, 1), besideFileNamed: "DSCF1284.RAF", in: scratch))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "mine")
    }

    func testFolderGetsTheEmbeddedJPEGAndASidecarForTheRAF() async throws {
        let folder = scratch.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jpegURL = try jpeg(named: "DSCF1284.JPG")
        let position = point(60, 38.5, -28.25)
        XCTAssertTrue(GeoTagWriter.embed(position, into: jpegURL))
        let rafURL = scratch.appendingPathComponent("DSCF1284.RAF")
        try Data(repeating: 9, count: 300).write(to: rafURL)
        let jpegFile = try XCTUnwrap(ImportFile(id: "j", name: "DSCF1284.JPG", folder: "DCIM", byteSize: 1, captureDate: noon))
        let rafFile = try XCTUnwrap(ImportFile(id: "r", name: "DSCF1284.RAF", folder: "DCIM", byteSize: 300, captureDate: noon))

        try await FolderImportWriter(folder: folder).write([(jpegFile, jpegURL), (rafFile, rafURL)], position: position)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["DSCF1284.JPG", "DSCF1284.RAF", "DSCF1284.xmp"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("DSCF1284.RAF")), Data(repeating: 9, count: 300),
                       "the RAF itself is never changed")
        XCTAssertTrue(GeoTagWriter.hasPosition(folder.appendingPathComponent("DSCF1284.JPG")))
    }

    func testWithoutAPositionNoSidecarIsWritten() async throws {
        let rafURL = scratch.appendingPathComponent("DSCF1284.RAF")
        try Data(repeating: 9, count: 300).write(to: rafURL)
        let folder = scratch.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let raf = try XCTUnwrap(ImportFile(id: "r", name: "DSCF1284.RAF", folder: "DCIM", byteSize: 300, captureDate: noon))
        try await FolderImportWriter(folder: folder).write([(raf, rafURL)], position: nil)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["DSCF1284.RAF"])
    }

    // MARK: The import

    private func importModel(points: [GeoPoint], clockOffset: TimeInterval, writer: RecordingWriter,
                             files: [ImportFile]) -> PhotoImportModel {
        PhotoImportModel(source: FakePhotoSource(files: files),
                         ledger: PhotoImportLedger(url: scratch.appendingPathComponent("ledger.json")),
                         stagingRoot: scratch.appendingPathComponent("staging"),
                         clockOffset: clockOffset, loadTrackPoints: { points },
                         preferences: UserDefaults(suiteName: "GeotaggingTests-\(UUID().uuidString)")!,
                         makeWriter: { _ in writer })
    }

    private func finish(_ model: PhotoImportModel) async {
        model.selectAll()
        model.startImport()
        for _ in 0..<400 {
            if case .finished = model.phase { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("the import didn't finish")
    }

    func testImportPlacesFramesInsideTheTrackAndCorrectsTheCameraClock() async throws {
        // The camera runs an hour ahead: what it stamps 13:00 was taken at 12:00.
        let inside = try XCTUnwrap(ImportFile(id: "a", name: "DSCF0001.RAF", folder: "DCIM", byteSize: 10,
                                              captureDate: noon.addingTimeInterval(3600 + 30)))
        let outside = try XCTUnwrap(ImportFile(id: "b", name: "DSCF0002.RAF", folder: "DCIM", byteSize: 10,
                                               captureDate: noon.addingTimeInterval(3 * 3600)))
        let writer = RecordingWriter()
        let model = importModel(points: [point(0, 38.5, -28.5), point(60, 38.6, -28.5)], clockOffset: 3600,
                                writer: writer, files: [inside, outside])
        await model.open()
        XCTAssertTrue(model.addsLocation, "on by default once a track exists")
        XCTAssertNotNil(model.previewPosition(of: model.frames[0]))
        XCTAssertNil(model.previewPosition(of: model.frames[1]))

        await finish(model)

        XCTAssertEqual(model.phase, .finished(.init(imported: 2, located: 1)))
        XCTAssertEqual(writer.positions.first??.latitude ?? 0, 38.55, accuracy: 1e-9)
        XCTAssertNil(writer.positions.last ?? nil)
    }

    func testWithoutATrackLocationIsOffAndNothingIsPlaced() async throws {
        let file = try XCTUnwrap(ImportFile(id: "a", name: "DSCF0001.JPG", folder: "DCIM", byteSize: 10, captureDate: noon))
        let writer = RecordingWriter()
        let model = importModel(points: [], clockOffset: 0, writer: writer, files: [file])
        await model.open()
        XCTAssertFalse(model.addsLocation)
        await finish(model)
        XCTAssertEqual(model.phase, .finished(.init(imported: 1)))
        XCTAssertEqual(writer.positions.count, 1)
        XCTAssertNil(writer.positions[0])
    }

    func testFramesDatedInTheFutureAreFlagged() async throws {
        let later = try XCTUnwrap(ImportFile(id: "a", name: "DSCF0001.JPG", folder: "DCIM", byteSize: 10,
                                             captureDate: noon.addingTimeInterval(3600)))
        let model = importModel(points: [point(0, 1, 1)], clockOffset: 0, writer: RecordingWriter(), files: [later])
        await model.open()
        XCTAssertEqual(model.framesFromTheFuture(now: noon).count, 1)
        model.clockOffset = 3600
        XCTAssertTrue(model.framesFromTheFuture(now: noon).isEmpty, "the offset explains it")
    }

    func testDemoTracksCoverTheDemoCard() async throws {
        let files = try await DemoPhotoSource(now: noon).open(progress: { _ in }, partial: { _ in })
        let matcher = GeoMatcher(points: LocationTrack.demoTracks(now: noon).flatMap(\.points))
        XCTAssertTrue(files.allSatisfy { matcher.point(at: $0.captureDate!) != nil })
    }

    func testDurationWording() {
        XCTAssertEqual(LocationTrackView.duration(40), "40 s")
        XCTAssertEqual(LocationTrackView.duration(720), "12 min")
        XCTAssertEqual(LocationTrackView.duration(8040), "2 h 14 min")
    }
}
