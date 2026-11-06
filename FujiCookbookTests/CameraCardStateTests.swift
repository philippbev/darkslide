import XCTest
@testable import FujiCookbook

final class CameraCardStateTests: XCTestCase {

    func testALiveSessionIsShownAsConnected() {
        XCTAssertEqual(CameraCardState(isConnected: true, isRecovering: false), .live)
    }

    /// A dropped session keeps its camera while recovery runs. The card must stop saying connected.
    func testARecoveringSessionIsShownAsReconnecting() {
        XCTAssertEqual(CameraCardState(isConnected: true, isRecovering: true), .reconnecting)
    }

    /// A recovery that gives up clears the camera a moment before its task clears the flag. In that
    /// moment there is nothing left to reconnect to.
    func testACameraThatIsGoneIsNotShown() {
        XCTAssertNil(CameraCardState(isConnected: false, isRecovering: true))
        XCTAssertNil(CameraCardState(isConnected: false, isRecovering: false))
    }
}
