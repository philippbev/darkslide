import XCTest
@testable import FujiCookbook

/// The Kitchen's selection handling: a pick is checked up front and read one file at a time, when
/// that file's upload runs.
final class CookHarnessTests: XCTestCase {

    func testPreparedRAFsReadTheirFileWhenLoadedNotWhenPrepared() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = directory.appendingPathComponent("kept.RAF")
        let removed = directory.appendingPathComponent("removed.RAF")
        try Data([1, 2, 3]).write(to: kept)
        try Data([4, 5, 6]).write(to: removed)

        let prepared = CookHarness.prepareRAFs([kept, removed])
        XCTAssertEqual(prepared.rafs.map(\.filename), ["kept.RAF", "removed.RAF"])
        XCTAssertTrue(prepared.unreadable.isEmpty)

        // A file that goes away after the check is not served from a copy read earlier: nothing was.
        try FileManager.default.removeItem(at: removed)
        let keptBytes = try await prepared.rafs[0].load()
        XCTAssertEqual(keptBytes, Data([1, 2, 3]))
        do {
            _ = try await prepared.rafs[1].load()
            XCTFail("a removed file has no bytes to give")
        } catch {}
    }

    func testAFileThatCannotBeReadIsNamedBeforeAnythingIsSent() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).RAF")
        let prepared = CookHarness.prepareRAFs([missing])
        XCTAssertEqual(prepared.unreadable, [missing.lastPathComponent])
        XCTAssertTrue(prepared.rafs.isEmpty)
    }
}
