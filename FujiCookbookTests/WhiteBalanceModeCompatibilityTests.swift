import XCTest
@testable import FujiCookbook

/// A white balance mode the body's menu lacks — Auto (White Priority) on an X100V, Kelvin on an
/// X-M1 — is warned about before a push, named by the Works With card, and still sent: the codec
/// has no per-body gate, which is why the wording says the body may refuse it.
final class WhiteBalanceModeCompatibilityTests: XCTestCase {

    private let registry = CameraModelRegistry.shared

    private func body(_ id: String) throws -> CameraModel { try XCTUnwrap(registry.model(withID: id)) }

    private func recipe(_ mode: WhiteBalanceMode) -> RecipeSettings {
        RecipeSettings(filmSimulation: .provia,
                       whiteBalance: WhiteBalance(mode: mode, shiftRed: 0, shiftBlue: 0,
                                                  kelvin: mode.usesKelvin ? 5600 : nil))
    }

    private func modeIssues(_ s: RecipeSettings, on model: CameraModel) -> [FieldCompatibilityIssue] {
        RecipeCompatibility.analyze(s, for: model).filter { $0.kind == .whiteBalanceModeUnsupported }
    }

    func testAnUnsupportedModeIsWarnedAboutBeforeThePush() throws {
        let x100V = try body("X100V")
        let issues = modeIssues(recipe(.autoWhitePriority), on: x100V)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.field, .whiteBalance)
        XCTAssertTrue(issues.first?.message.contains("FUJIFILM X100V") == true, "names the body")
        XCTAssertTrue(issues.first?.message.contains("Auto (White Priority)") == true, "names the mode")
        XCTAssertFalse(issues.first?.message.contains("Processor") == true, "the body, not its processor")
        XCTAssertTrue(modeIssues(recipe(.autoWhitePriority), on: try body("X-T5")).isEmpty)
        XCTAssertTrue(modeIssues(recipe(.auto), on: x100V).isEmpty)
        XCTAssertTrue(modeIssues(RecipeSettings(filmSimulation: .provia), on: x100V).isEmpty,
                      "no white balance, nothing to warn about")
        XCTAssertEqual(modeIssues(recipe(.kelvin), on: try body("X-M1")).count, 1, "the X-M1 has no Kelvin mode")
        XCTAssertTrue(modeIssues(recipe(.kelvin), on: try body("X-Pro1")).isEmpty)
    }

    /// The premise of the wording: the mode goes to the camera as encoded, clamp or no clamp.
    func testThePushStillSendsTheModeTheBodyLacks() throws {
        let x100V = try body("X100V")
        let s = recipe(.autoWhitePriority)
        XCTAssertEqual(RecipeCompatibility.clamped(s, to: x100V).whiteBalance?.mode, .autoWhitePriority)
        let writes = FujiPresetCodec.encode(RecipeCompatibility.clamped(s, to: x100V), model: x100V, slot: .empty)
        let wb = writes.first { $0.code == FujiPTP.PresetProp.whiteBalance.rawValue }
        XCTAssertEqual(wb?.bytes, FujiEncoding.packU16(FujiEncoding.wbModeToValue[.autoWhitePriority]!))
    }

    func testTheWorksWithVerdictIsWithChangesAndNamesTheMode() throws {
        let fit = RecipeCameraFit(recipe(.autoWhitePriority), on: try body("X100V"))
        XCTAssertEqual(fit.verdict, .worksWithChanges)
        XCTAssertEqual(fit.changes, [.whiteBalanceModeMissing(.autoWhitePriority)])
        XCTAssertEqual(RecipeCameraFit(recipe(.autoWhitePriority), on: registry.demoModel).verdict, .worksAsWritten)
        XCTAssertEqual(RecipeCameraFit(recipe(.autoWhitePriority), on: try body("X-T5")).verdict, .worksAsWritten)
    }
}
