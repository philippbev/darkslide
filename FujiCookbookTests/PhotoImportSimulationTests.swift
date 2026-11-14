import XCTest
@testable import FujiCookbook

/// The import reads each frame's film simulation only while the diagnostic switch is on.
@MainActor
final class PhotoImportSimulationTests: XCTestCase {

    private var suiteName = ""

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func model(readsSimulation: Bool) -> PhotoImportModel {
        suiteName = "PhotoImportSimulationTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        preferences.set(readsSimulation, forKey: DiagnosticMode.readsImportSimulationKey)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        return PhotoImportModel(source: DemoPhotoSource(),
                                ledger: PhotoImportLedger(url: scratch.appendingPathComponent("ledger.json")),
                                stagingRoot: scratch, clockOffset: 0, loadTrackPoints: { [] },
                                preferences: preferences)
    }

    private func loadAll(_ model: PhotoImportModel) async {
        await model.open()
        model.frames.forEach(model.loadThumbnail(for:))
        for _ in 0..<400 where model.thumbnails.count < model.frames.count
            || (model.simulations.count < model.frames.count && model.readsSimulation) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testWithTheSwitchOnEachTileGetsItsSimulation() async {
        let model = model(readsSimulation: true)
        await loadAll(model)
        XCTAssertFalse(model.frames.isEmpty)
        XCTAssertEqual(model.simulations.count, model.frames.count)
    }

    func testWithTheSwitchOffNothingIsRead() async {
        let model = model(readsSimulation: false)
        await loadAll(model)
        XCTAssertEqual(model.thumbnails.count, model.frames.count)
        XCTAssertTrue(model.simulations.isEmpty)
    }
}
