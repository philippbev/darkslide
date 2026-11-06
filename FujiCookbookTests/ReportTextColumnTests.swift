import XCTest
@testable import FujiCookbook

/// A report is drawn in chunks of lines; the chunks must add back up to the report.
final class ReportTextColumnTests: XCTestCase {
    func testAShortReportIsOneChunk() {
        XCTAssertEqual(ReportTextColumn.chunks("", linesPerChunk: 3), [""])
        XCTAssertEqual(ReportTextColumn.chunks("a\nb\nc", linesPerChunk: 3), ["a\nb\nc"])
    }

    func testChunksCutOnLinesAndJoinBackToTheReport() {
        let report = (1...250).map(String.init).joined(separator: "\n") + "\n"
        let chunks = ReportTextColumn.chunks(report, linesPerChunk: 100)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].split(separator: "\n").count, 100)
        XCTAssertEqual(chunks[2], (201...250).map(String.init).joined(separator: "\n") + "\n",
                       "the trailing newline survives as an empty last line")
        XCTAssertEqual(chunks.joined(separator: "\n"), report)
    }

    func testTheDefaultChunkKeepsAJSONReportInDrawableViews() {
        let lines = Array(repeating: "{", count: 6_592)
        let chunks = ReportTextColumn.chunks(lines.joined(separator: "\n"))
        XCTAssertEqual(chunks.count, 66)
        XCTAssertTrue(chunks.allSatisfy {
            $0.split(separator: "\n", omittingEmptySubsequences: false).count <= ReportTextColumn.linesPerChunk
        })
    }
}
