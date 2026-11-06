import XCTest
@testable import FujiCookbook

/// The registry's write states, audited. `.blocked` only where the record holds a USB observation
/// of this body refusing or failing the bank path; `.untested` wherever it holds none, for or
/// against; a reason quoted for every failure and for nothing else.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference: `docs/07-cameras.md#x-pro3`,
/// `docs/07-cameras.md#x-t3-and-x-t30`, `docs/07-cameras.md#x-t20` and `docs/07-cameras.md#summary`.
@MainActor
final class RegistryAuditTests: XCTestCase {
    private let registry = CameraModelRegistry.shared

    private var blocked: [CameraModel] {
        registry.models.filter { if case .blocked = $0.writeSupport { return true }; return false }
    }
    private var untested: [CameraModel] { registry.models.filter { $0.writeSupport == .untested } }

    func testOnlyBodiesWithARecordedFailureAreBlocked() {
        XCTAssertEqual(Set(blocked.map(\.id)), ["X-Pro3", "X-T3", "X-T30", "X-T20"],
                       "the X-Pro3 fails reads, writes and names at fw 2.00; the X-T3 fails every "
                       + "select at fw 5.11 and the X-T30 the first at fw 2.01; the X-T20 answers "
                       + "0x200A to all 26 bank reads at fw 2.01. Nothing else is measured against")
    }

    func testEveryBlockedEntryQuotesTheFailureInItsOwnName() {
        for model in blocked {
            let reason = model.writeSupport.blockReason ?? ""
            XCTAssertFalse(reason.isEmpty, model.id)
            XCTAssertTrue(reason.contains(model.displayName), "\(model.id) names itself in its reason")
        }
    }

    func testUntestedEntriesAreTheBodiesTheRecordHoldsNothingOn() {
        XCTAssertEqual(Set(untested.map(\.id)),
                       ["X-H1", "X-Pro2", "X-T2", "X100F", "X-E3",
                        "GFX50S", "GFX50R", "GFX100 II", "GFX100S II",
                        "X-Pro1", "X-E1", "X-M1", "X100S", "X-T1", "X-E2", "X-E2S", "X-T10", "X70", "X100T"])
        for model in untested {
            XCTAssertNil(model.writeSupport.blockReason, "\(model.id): nothing to quote")
            XCTAssertFalse(model.allowsWrite, model.id)
        }
    }

    func testEveryEntryIsInExactlyOneState() {
        let writable = registry.models.filter(\.allowsWrite).count
        XCTAssertEqual(writable + blocked.count + untested.count, registry.models.count)
    }
}
