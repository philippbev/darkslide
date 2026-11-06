import XCTest
@testable import FujiCookbook

/// Which store comes up at launch, and how many tries it takes, for each sync preference.
final class OpenedStoreTests: XCTestCase {
    private struct StoreUnavailable: Error {}

    /// Stands in for `ModelContainer`: records each attempt and fails the configurations it is told to.
    private final class Opener {
        private let failing: Set<Bool>
        private(set) var attempts: [Bool] = []

        init(failingCloudKit failing: Set<Bool> = []) {
            self.failing = failing
        }

        func open(cloudKit: Bool) throws -> String {
            attempts.append(cloudKit)
            if failing.contains(cloudKit) { throw StoreUnavailable() }
            return cloudKit ? "cloud" : "local"
        }
    }

    func testSyncOffOpensALocalStore() throws {
        let opener = Opener()
        let opened = try OpenedStore.open(wantsCloud: false, using: opener.open)

        XCTAssertEqual(opened.store, "local")
        XCTAssertEqual(opened.state, .local)
        XCTAssertEqual(opener.attempts, [false])
    }

    func testSyncOnOpensACloudKitStore() throws {
        let opener = Opener()
        let opened = try OpenedStore.open(wantsCloud: true, using: opener.open)

        XCTAssertEqual(opened.store, "cloud")
        XCTAssertEqual(opened.state, .cloudKit)
        XCTAssertEqual(opener.attempts, [true])
    }

    func testAFailedCloudKitStoreFallsBackToLocal() throws {
        let opener = Opener(failingCloudKit: [true])
        let opened = try OpenedStore.open(wantsCloud: true, using: opener.open)

        XCTAssertEqual(opened.store, "local")
        XCTAssertEqual(opened.state, .fellBack(CloudStoreFailure(StoreUnavailable())))
        XCTAssertEqual(opener.attempts, [true, false])
    }

    func testAFailedLocalStoreIsNotRetriedWhenSyncIsOff() {
        let opener = Opener(failingCloudKit: [false])

        XCTAssertThrowsError(try OpenedStore.open(wantsCloud: false, using: opener.open))
        XCTAssertEqual(opener.attempts, [false])
    }

    func testNoStoreAtAllThrows() {
        let opener = Opener(failingCloudKit: [true, false])

        XCTAssertThrowsError(try OpenedStore.open(wantsCloud: true, using: opener.open))
        XCTAssertEqual(opener.attempts, [true, false])
    }
}
