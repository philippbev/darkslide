import XCTest
import CoreGraphics
@testable import FujiCookbook

/// A card that hands over its first files, then holds the listing open until released, and counts
/// the simulation reads it is asked for.
@MainActor
private final class HeldListingSource: PhotoSource {
    let displayName = "X100VI"
    let files: [ImportFile]
    private var release: CheckedContinuation<Void, Never>?
    private(set) var simulationReads = 0

    init(files: [ImportFile]) { self.files = files }

    func open(progress: @escaping @MainActor (CatalogProgress) -> Void,
              partial: @escaping @MainActor ([ImportFile]) -> Void) async throws -> [ImportFile] {
        partial(files)
        await withCheckedContinuation { release = $0 }
        return files
    }

    func finishListing() { release?.resume(); release = nil }

    func thumbnail(for file: ImportFile) async -> CGImage? { nil }
    func filmSimulation(for file: ImportFile) async -> FilmSimulation? {
        simulationReads += 1
        return .classicChrome
    }
    func download(_ file: ImportFile, to directory: URL) async throws -> URL { directory }
    func close() async {}
}

/// Every tile that appears gets its film simulation, read once the first portion is listed.
@MainActor
final class PhotoImportSimulationTests: XCTestCase {

    private var suiteName = ""

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func model(_ source: PhotoSource) -> PhotoImportModel {
        suiteName = "PhotoImportSimulationTests-\(UUID().uuidString)"
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        return PhotoImportModel(source: source,
                                ledger: PhotoImportLedger(url: scratch.appendingPathComponent("ledger.json")),
                                stagingRoot: scratch, clockOffset: 0, loadTrackPoints: { [] },
                                preferences: UserDefaults(suiteName: suiteName)!)
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<400 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testEachTileGetsItsSimulation() async {
        let model = model(DemoPhotoSource())
        await model.open()
        model.frames.forEach(model.loadThumbnail(for:))
        await settle { model.simulations.count == model.frames.count }
        XCTAssertFalse(model.frames.isEmpty)
        XCTAssertEqual(model.simulations.count, model.frames.count)
    }

    func testReadsWaitUntilTheFirstPortionIsListed() async throws {
        let files = try (1...3).map { n in
            try XCTUnwrap(ImportFile(id: "DCIM/100_FUJI/DSCF000\(n).JPG", name: "DSCF000\(n).JPG", folder: "DCIM/100_FUJI",
                                     byteSize: 100, captureDate: Date(timeIntervalSince1970: 1_794_571_200 + Double(n))))
        }
        let source = HeldListingSource(files: files)
        let model = model(source)
        let opening = Task { await model.open() }
        await settle { model.isListing }
        XCTAssertTrue(model.isListing)

        model.frames.forEach(model.loadThumbnail(for:))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(source.simulationReads, 0, "no extra reads while the card is still being listed")

        source.finishListing()
        await opening.value
        await settle { model.simulations.count == files.count }
        XCTAssertEqual(source.simulationReads, files.count)
        XCTAssertEqual(model.simulations.count, files.count)
    }
}
