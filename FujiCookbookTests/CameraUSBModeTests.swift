import XCTest
@testable import FujiCookbook

/// A body connected in a USB mode that exposes storage instead of camera control, and a health
/// probe that must not read the resulting refusal as a dropped connection. A GFX100S has connected
/// this way (zgrimz/fujifilm-ptp-reference `docs/01-transport.md#recognizing-the-wrong-usb-mode`).
final class CameraUSBModeTests: XCTestCase {

    // MARK: - Reading the mode off GetDeviceInfo

    /// The GFX100S in a storage mode: four properties, nothing in the vendor control block
    /// (zgrimz/fujifilm-ptp-reference `docs/01-transport.md#recognizing-the-wrong-usb-mode`).
    private func storageMode() -> FujiPTP.DeviceInfo {
        var info = FujiPTP.DeviceInfo()
        info.model = "GFX100S"
        info.devicePropertiesSupported = [0x5001, 0xD303, 0xD406, 0xD407]
        return info
    }

    /// A synthetic stand-in for the GFX100S in `USB RAW Conv./Backup Restore`, whose 168 properties
    /// are in zgrimz/fujifilm-ptp-reference `evidence/gfx100s-20260915-194552`: the standard block,
    /// the control block, and the two high vendor codes present in both modes. Its ranges are
    /// approximate; only the shape matters here.
    private func controlMode() -> FujiPTP.DeviceInfo {
        var info = FujiPTP.DeviceInfo()
        info.model = "GFX100S"
        info.devicePropertiesSupported =
            [0x5001, 0x5003, 0x5005, 0x500A, 0x500B, 0x500C, 0x500E, 0x500F]
            + (0xD001...0xD01C).map { UInt16($0) }
            + (0xD100...0xD161).map { UInt16($0) }
            + [0xD406, 0xD407]
        return info
    }

    func testAStorageModeDeviceInfoIsRecognized() {
        XCTAssertTrue(storageMode().looksLikeStorageOnlyMode)
    }

    func testTheRightModeIsNotMistakenForIt() {
        let control = controlMode()
        XCTAssertFalse(control.looksLikeStorageOnlyMode)
        XCTAssertTrue(control.devicePropertiesSupported.count > 100, "sanity: this is the long list")
        // The property the app reads recipes through is absent from BOTH lists on this body — it
        // answers 0xD18C without ever advertising it — so the mode check must not look for it.
        XCTAssertFalse(control.supportsProperty(FujiPTP.Prop.slotSelector))
        XCTAssertFalse(control.supportsProperty(FujiPTP.Prop.presetName))
    }

    /// A body that refused `GetDeviceInfo` outright tells us nothing about its USB mode, and must
    /// not be sent to the menu on the strength of an empty list.
    func testARefusedDeviceInfoIsNotADiagnosis() {
        XCTAssertFalse(FujiPTP.DeviceInfo().looksLikeStorageOnlyMode)
    }

    /// Tether mode keeps the `0xD001…` control block. It is a different wrong mode with a
    /// different answer, so this check has to stay quiet and let it through.
    func testTetherModeIsNotClaimedAsStorageMode() {
        var tether = FujiPTP.DeviceInfo()
        tether.devicePropertiesSupported = [0x5001, 0xD001, 0xD002, 0xD003]
        XCTAssertFalse(tether.looksLikeStorageOnlyMode)
    }

    /// The user-facing half: the message names the menu and the setting.
    func testTheErrorNamesTheSettingToChange() {
        let message = CameraError.wrongUSBMode.errorDescription ?? ""
        XCTAssertTrue(message.contains("USB Mode"), message)
        XCTAssertTrue(message.contains("RAW Conv"), message)
    }

    // MARK: - A refusal is still an answer

    /// A PTP response code counts as the camera answering, so the health probe keeps the session.
    /// Through iOS the rejecting endpoint of a `0x200A` can be unresolved
    /// (zgrimz/fujifilm-ptp-reference `docs/01-transport.md#response-codes`); the probe treats the
    /// response as an answer regardless.
    func testAPTPRefusalProvesTheCameraIsStillTalking() {
        XCTAssertTrue(CameraError.ptpError(code: FujiPTP.responseDevicePropNotSupported).provesCameraAnswered)
        XCTAssertTrue(CameraError.ptpError(code: 0x2002).provesCameraAnswered, "General Error is still an answer")
        XCTAssertTrue(CameraError.ptpError(code: FujiPTP.responseInvalidDevicePropValue).provesCameraAnswered)
    }

    /// The exceptions: the body replied, and what it replied was that the session is gone.
    func testSessionStateCodesStillCountAsLoss() {
        for code: UInt16 in [0x2003, 0x2004, 0x201E] {
            XCTAssertFalse(CameraError.ptpError(code: code).provesCameraAnswered,
                           "0x\(String(format: "%04X", code)) — \(FujiPTP.responseName(code) ?? "?") — is a dead session")
        }
    }

    /// And the errors that are not a PTP response at all: nothing answered, so nothing is proven.
    func testNonProtocolErrorsAreNotProofOfLife() {
        XCTAssertFalse(CameraError.timeout.provesCameraAnswered)
        XCTAssertFalse(CameraError.disconnectedDuringOperation.provesCameraAnswered)
        XCTAssertFalse(CameraError.noDeviceConnected.provesCameraAnswered)
        XCTAssertFalse(CameraError.sessionFailed("cable").provesCameraAnswered)
    }
}
