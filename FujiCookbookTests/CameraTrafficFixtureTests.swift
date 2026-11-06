import XCTest
@testable import FujiCookbook

/// The camera traffic of a connect and a push on a hardware-verified body, and of a connect on a
/// body the registry blocks, compared transaction for transaction against a recorded sequence.
///
/// Write enablement for unlisted cameras changes how the app decides to write, and promises that
/// nothing changes for the bodies it already writes to or refuses. A promise about traffic is kept
/// by comparing traffic, not by reading the gate's code, so each scenario here is diffed against
/// the sequence the mock recorded before the change (`CameraTrafficFixtures`). What the mock answers
/// is deliberately not compared: these fixtures pin what the app sends.
///
/// To re-record after a deliberate change, run with `TEST_RUNNER_FUJI_TRACE_DUMP_DIR=<dir>` and copy
/// the dumped text into the fixture, in the commit that changes the traffic.
@MainActor
final class CameraTrafficFixtureTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    private func connect(_ faults: MockCameraFaults) async -> CameraServices {
        var faults = faults
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    /// Every property the codec writes, with values that differ from the mock's seeded C1.
    private var recipe: RecipeSettings {
        RecipeSettings(
            filmSimulation: .classicNeg,
            grain: GrainEffect(strength: .weak, size: .large),
            colorChromeEffect: .strong, colorChromeFXBlue: .weak,
            whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 2, shiftBlue: -3, kelvin: nil),
            dynamicRange: .dr400,
            highlightTone: -0.5, shadowTone: 1.0, color: 2, sharpness: -1, highISONR: -3, clarity: 1)
    }

    func testTheXT50ConnectAndPushSendTheRecordedSequence() async throws {
        let m = await connect(MockCameraFaults(productName: "FUJIFILM X-T50", firmwareVersion: "1.32"))
        XCTAssertTrue(m.session.canPush, "precondition: the X-T50 writes")
        // C1: the mock seeds C1 and C2 only, and a push to an unseeded slot is refused before the
        // first write because there is no recovery copy to preserve.
        let result = await m.slotWriter.push(settings: recipe, name: "Traffic", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied, "precondition: the control push lands")
        let report = try XCTUnwrap(m.reports.report)
        try CameraTraffic.assertMatches(report.transactions, fixture: CameraTrafficFixtures.xt50ConnectAndPushC1,
                                        name: "xt50-connect-push-c1")
    }

    func testTheXPro3ConnectSendsTheRecordedSequence() async throws {
        let m = await connect(MockCameraFaults(productName: "FUJIFILM X-Pro3", firmwareVersion: "2.00"))
        XCTAssertFalse(m.session.canPush, "precondition: the X-Pro3 is refused")
        let report = try XCTUnwrap(m.reports.report)
        try CameraTraffic.assertMatches(report.transactions, fixture: CameraTrafficFixtures.xPro3Connect,
                                        name: "xpro3-connect")
    }
}

/// One line per transaction: operation, parameters, outgoing bytes, response.
enum CameraTraffic {
    static func render(_ transactions: [PTPTransaction]) -> String {
        transactions.map { t in
            let params = t.parameters.isEmpty ? "-" : t.parameters.joined(separator: ",")
            return "\(t.operation) \(params) out=\(t.outData ?? "-") resp=\(t.response ?? t.error ?? "-")"
        }.joined(separator: "\n")
    }

    static func assertMatches(_ transactions: [PTPTransaction], fixture: String, name: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let rendered = render(transactions)
        if let dir = ProcessInfo.processInfo.environment["FUJI_TRACE_DUMP_DIR"] {
            try rendered.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).txt"),
                               atomically: true, encoding: .utf8)
        }
        let expected = fixture.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let actual = rendered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard expected != actual else { return }
        let firstDifference = zip(expected, actual).enumerated().first { $0.element.0 != $0.element.1 }
        let where_ = firstDifference.map { "line \($0.offset + 1): expected “\($0.element.0)”, sent “\($0.element.1)”" }
            ?? "the sequences differ in length only"
        XCTFail("\(name): \(actual.count) transactions sent, \(expected.count) recorded — \(where_)",
                file: file, line: line)
    }
}
