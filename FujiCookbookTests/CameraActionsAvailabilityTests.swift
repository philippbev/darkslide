import XCTest
@testable import FujiCookbook

final class CameraActionsAvailabilityTests: XCTestCase {

    func testALiveIdleSessionOffersImportAndPush() {
        XCTAssertTrue(CameraView.actionsAvailable(status: .connected, cardState: .live))
    }

    func testAnOperationInProgressHoldsThemOff() {
        XCTAssertFalse(CameraView.actionsAvailable(status: .working("Reading slot C2…"), cardState: .live))
    }

    /// A failed recovery attempt reports `.failed` while the next attempt waits, with the camera last
    /// seen still set. The transport is down, so nothing may open on it.
    func testAFailedAttemptDuringRecoveryHoldsThemOff() {
        XCTAssertFalse(CameraView.actionsAvailable(status: .failed("The camera didn't respond."),
                                                   cardState: .reconnecting))
    }

    func testEveryRecoveryStageHoldsThemOff() {
        for status: CameraSession.Status in [.connecting, .working("Reconnecting…"), .connected] {
            XCTAssertFalse(CameraView.actionsAvailable(status: status, cardState: .reconnecting), "\(status)")
        }
    }

    func testNoCameraOffersNothing() {
        XCTAssertFalse(CameraView.actionsAvailable(status: .connected, cardState: nil))
    }
}
