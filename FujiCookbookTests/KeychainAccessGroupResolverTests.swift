import XCTest
@testable import FujiCookbook

final class KeychainAccessGroupResolverTests: XCTestCase {
    private final class ScriptedProbe {
        var answers: [String?]
        private(set) var calls = 0

        init(_ answers: [String?]) { self.answers = answers }

        func next() -> String? {
            calls += 1
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }

    func testFailedProbeIsNotKept() {
        let probe = ScriptedProbe([nil, "TEAMID"])
        let resolver = KeychainStore.AccessGroupResolver(groupName: "com.example.app", teamPrefix: probe.next)

        XCTAssertNil(resolver.group(), "no group, prefixed or bare, while the probe fails")
        XCTAssertEqual(resolver.group(), "TEAMID.com.example.app", "the next call probes again")
        XCTAssertEqual(probe.calls, 2)
    }

    func testSuccessfulProbeIsKept() {
        let probe = ScriptedProbe(["TEAMID", "OTHERTEAM"])
        let resolver = KeychainStore.AccessGroupResolver(groupName: "com.example.app", teamPrefix: probe.next)

        XCTAssertEqual(resolver.group(), "TEAMID.com.example.app")
        XCTAssertEqual(resolver.group(), "TEAMID.com.example.app")
        XCTAssertEqual(probe.calls, 1)
    }
}
