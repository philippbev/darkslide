import XCTest
@testable import FujiCookbook

/// `ImportCoordinator.processSharedScreenshots`, driven through a fake scanner against the real
/// App Group inbox. Files already waiting in this test host's inbox are moved aside for each test
/// and put back afterwards, and the AI settings each test changes are restored.
@MainActor
final class SharedScreenshotDrainTests: XCTestCase {
    private struct ScanFailed: LocalizedError {
        var errorDescription: String? { "The scan failed." }
    }

    private var inbox: URL!
    private var setAside: URL!
    private var restoreAISettings: (() -> Void)?

    override func setUp() async throws {
        try await super.setUp()
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ScreenshotInbox.appGroupID)
        guard let container else { throw XCTSkip("no App Group container in this test host") }
        inbox = container.appendingPathComponent("ScreenshotInbox", isDirectory: true)
        setAside = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedScreenshotDrainTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: setAside, withIntermediateDirectories: true)
        for url in ScreenshotInbox.pending() {
            try FileManager.default.moveItem(at: url, to: setAside.appendingPathComponent(url.lastPathComponent))
        }
    }

    override func tearDown() async throws {
        restoreAISettings?()
        restoreAISettings = nil
        if let inbox, let setAside {
            ScreenshotInbox.removeAll()
            let waiting = (try? FileManager.default.contentsOfDirectory(at: setAside,
                                                                        includingPropertiesForKeys: nil)) ?? []
            for url in waiting {
                try? FileManager.default.moveItem(at: url, to: inbox.appendingPathComponent(url.lastPathComponent))
            }
            try? FileManager.default.removeItem(at: setAside)
        }
        try await super.tearDown()
    }

    private func queueScreenshot() throws -> URL {
        try ScreenshotInbox.save(Data("not really a png".utf8))
        return try XCTUnwrap(ScreenshotInbox.pending().last)
    }

    /// An `AISettings` with AI on or off and a key and model for Anthropic, restored in tearDown.
    private func aiSettings(enabled: Bool) -> AISettings {
        let settings = AISettings()
        let provider = settings.provider
        let isEnabled = settings.isEnabled
        settings.provider = .anthropic
        let key = settings.anthropicKey
        let modelID = settings.modelID
        restoreAISettings = {
            settings.provider = .anthropic
            settings.anthropicKey = key
            settings.modelID = modelID
            settings.isEnabled = isEnabled
            settings.provider = provider
        }
        settings.anthropicKey = "test-key"
        settings.modelID = "test-model"
        settings.isEnabled = enabled
        return settings
    }

    private func recipeFile(named name: String) throws -> Data {
        try ImportTestFixtures.data([PortableRecipe(name: name, settings: .neutral)])
    }

    func testASuccessfulScanPresentsAReviewAndRemovesTheScreenshot() async throws {
        let screenshot = try queueScreenshot()
        let coordinator = ImportCoordinator(scanScreenshot: { _, _, _, _ in
            PortableRecipe(name: "Scanned", settings: .neutral)
        })

        await coordinator.processSharedScreenshots(using: aiSettings(enabled: true))

        XCTAssertEqual(coordinator.pendingImport?.recipes.map(\.name), ["Scanned"])
        XCTAssertEqual(coordinator.pendingImport?.sourceName, "Shared Screenshot")
        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshot.path),
                       "a screenshot whose review is presented has been handled")
        XCTAssertFalse(coordinator.isScanningSharedScreenshots)
    }

    func testAFailedScanKeepsTheScreenshotAndReportsTheError() async throws {
        let screenshot = try queueScreenshot()
        let coordinator = ImportCoordinator(scanScreenshot: { _, _, _, _ in throw ScanFailed() })

        await coordinator.processSharedScreenshots(using: aiSettings(enabled: true))

        XCTAssertNil(coordinator.pendingImport)
        XCTAssertEqual(coordinator.importError, "The scan failed.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.path),
                      "the user asked for this screenshot to be held, so one failure doesn't drop it")
    }

    func testANewerFileImportTakesTheReviewAndTheScreenshotStays() async throws {
        let screenshot = try queueScreenshot()
        let scanStarted = expectation(description: "scan started")
        let (release, releaseScan) = AsyncStream<Void>.makeStream()
        let coordinator = ImportCoordinator(scanScreenshot: { _, _, _, _ in
            scanStarted.fulfill()
            for await _ in release { break }
            return PortableRecipe(name: "Scanned", settings: .neutral)
        })
        let ai = aiSettings(enabled: true)

        let drain = Task { await coordinator.processSharedScreenshots(using: ai) }
        await fulfillment(of: [scanStarted], timeout: 5)
        await coordinator.load(data: try recipeFile(named: "From File"), sourceName: "File").value
        releaseScan.yield()
        releaseScan.finish()
        await drain.value

        XCTAssertEqual(coordinator.pendingImport?.recipes.map(\.name), ["From File"],
                       "the scan finishing late must not overwrite the newer review")
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.path),
                      "a scan whose review was never shown leaves its screenshot for the next attempt")
    }

    func testWithoutAISetupTheScreenshotWaitsAndTheWarningShowsOnce() async throws {
        let screenshot = try queueScreenshot()
        var scans = 0
        let coordinator = ImportCoordinator(scanScreenshot: { _, _, _, _ in
            scans += 1
            return PortableRecipe(name: "Scanned", settings: .neutral)
        })
        let ai = aiSettings(enabled: false)

        await coordinator.processSharedScreenshots(using: ai)
        XCTAssertNotNil(coordinator.importError)
        coordinator.importError = nil
        await coordinator.processSharedScreenshots(using: ai)

        XCTAssertNil(coordinator.importError, "the setup warning shows once per launch")
        XCTAssertEqual(scans, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.path))
    }
}
