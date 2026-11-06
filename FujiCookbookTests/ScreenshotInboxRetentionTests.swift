import XCTest
@testable import FujiCookbook

/// Screenshots shared to the app are held across launches on purpose — the user asked us to keep
/// them, and they arrive precisely when a scan couldn't finish. But "hold them" was unbounded:
/// files were removed on a successful scan and on unreadable bytes, and on no other path, so one
/// that kept failing (or arrived before AI was configured) stayed in the App Group forever.
final class ScreenshotInboxRetentionTests: XCTestCase {
    private var created: [URL] = []

    override func tearDown() {
        created.forEach { try? FileManager.default.removeItem(at: $0) }
        created = []
        super.tearDown()
    }

    /// Writes a file with the name shape `save` produces, backdated by `age`.
    @discardableResult
    private func plant(age: TimeInterval, in dir: URL) throws -> URL {
        let stamp = Int(Date().addingTimeInterval(-age).timeIntervalSince1970)
        let url = dir.appendingPathComponent("screenshot-\(stamp)-\(UUID().uuidString.prefix(8))")
        try Data("not really a png".utf8).write(to: url)
        created.append(url)
        return url
    }

    private func inboxDirectory() throws -> URL {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ScreenshotInbox.appGroupID)
        guard let container else { throw XCTSkip("no App Group container in this test host") }
        let dir = container.appendingPathComponent("ScreenshotInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAnAgedOutScreenshotIsDropped() throws {
        let dir = try inboxDirectory()
        let stale = try plant(age: ScreenshotInbox.maxAge + 86_400, in: dir)

        ScreenshotInbox.purgeStale()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path),
                       "a screenshot that never scanned should not outlive the retention limit")
    }

    func testARecentScreenshotIsKept() throws {
        let dir = try inboxDirectory()
        let fresh = try plant(age: 60, in: dir)

        ScreenshotInbox.purgeStale()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path),
                      "holding a failed scan for a retry is the feature, not the bug")
    }

    func testTheCeilingDropsTheOldestFirst() throws {
        let dir = try inboxDirectory()
        // All well inside the age limit, so only the ceiling can act on them.
        let planted = try (0..<(ScreenshotInbox.maxCount + 3)).map {
            try plant(age: TimeInterval(3600 * ($0 + 1)), in: dir)
        }
        let newest = try XCTUnwrap(planted.first)

        ScreenshotInbox.purgeStale()

        XCTAssertEqual(ScreenshotInbox.pending().count, ScreenshotInbox.maxCount, "the ceiling holds")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newest.path))
        for oldest in planted.suffix(3) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldest.path), "overflow comes off the oldest end")
        }
    }
}
