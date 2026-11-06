import XCTest
@testable import FujiCookbook

/// Camera Test sessions and compatibility reports persist outcomes as JSON strings, and testers'
/// phones hold files written by every build since build 2. These pin that each stored spelling
/// still decodes, and that re-saving writes the same spelling back.
final class StoredOutcomeDecodingTests: XCTestCase {

    private func resaved<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    /// Every build has written a trial outcome as one of `SlotOutcome`'s four names, and nothing else.
    func testAStoredTrialOutcomeStillDecodes() throws {
        for (stored, expected) in [("applied", SlotOutcome.applied), ("partiallyApplied", .partiallyApplied),
                                   ("notWritten", .notWritten), ("unknown", .unknown)] {
            let json = Data(#"{"recipe":"colour","recipeName":"CT Colour","slot":2,"outcome":"\#(stored)","wrote":{}}"#.utf8)
            let trial = try JSONDecoder().decode(GuidedTestSession.PushTrial.self, from: json)
            XCTAssertEqual(trial.outcome, expected)
            XCTAssertEqual(try resaved(trial)["outcome"] as? String, stored)
        }
    }

    func testATrialWithNoOutcomeYetStillDecodes() throws {
        let json = Data(#"{"recipe":"colour","recipeName":"CT Colour","slot":2,"wrote":{}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(GuidedTestSession.PushTrial.self, from: json).outcome)
    }

    /// Builds 2–9 recorded a restore by the push outcome's name.
    func testABuild2To9RestoreStillDecodes() throws {
        for (stored, expected) in [("offered", RestoreDisposition.offered), ("applied", .applied),
                                   ("partiallyApplied", .partiallyApplied), ("notWritten", .notWritten),
                                   ("unknown", .unknown)] {
            let restore = try JSONDecoder().decode(GuidedTestSession.RestoreOutcome.self,
                                                   from: Data(#"{"slot":1,"outcome":"\#(stored)"}"#.utf8))
            XCTAssertEqual(restore.outcome, expected)
            XCTAssertEqual(try resaved(restore)["outcome"] as? String, stored)
        }
    }

    /// Build 10 on: the recovery record's dispositions, keyed by slot, in every spelling it writes.
    func testBuild10Dispositions() throws {
        let spellings = ["pending", "offered", "restored", "kept", "emptyKept", "partiallyApplied",
                         "couldNotVerify", "notWritten", "canceled"]
        let stored = Dictionary(uniqueKeysWithValues: spellings.enumerated().map { (String($0.offset + 1), $0.element) })
        let decoded = try JSONDecoder().decode([String: RestoreDisposition].self,
                                               from: JSONEncoder().encode(stored))
        XCTAssertFalse(decoded.values.contains { if case .unrecognized = $0 { return true } else { return false } })
        XCTAssertEqual(decoded["3"], .restored)
        XCTAssertEqual(decoded["5"], .emptyKept)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(decoded)), stored)
    }

    /// A spelling this build doesn't know still loads, and is written back as it was found.
    func testAnUnknownSpellingSurvivesARoundTrip() throws {
        let restore = try JSONDecoder().decode(GuidedTestSession.RestoreOutcome.self,
                                               from: Data(#"{"slot":1,"outcome":"running"}"#.utf8))
        XCTAssertEqual(restore.outcome, .unrecognized("running"))
        XCTAssertEqual(restore.outcome?.isSettled, false)
        XCTAssertEqual(try resaved(restore)["outcome"] as? String, "running")
    }
}
