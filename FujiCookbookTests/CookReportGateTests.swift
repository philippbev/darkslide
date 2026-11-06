import XCTest
@testable import FujiCookbook

/// The develop-anomaly log gate. A clean success must log nothing — the anomaly line exists so a
/// shared problem report shows the develops that may not reflect the recipe (failed, clamped, or
/// profile-unverified), not every routine development.
final class CookReportGateTests: XCTestCase {
    private func result(success: Bool, clamped: [String] = [], warnings: [String] = []) -> ConversionResult {
        var result = ConversionResult(sourceFilename: "DSCF0001.RAF", success: success,
                                      clampedFields: clamped)
        result.warnings = warnings
        return result
    }

    func testACleanSuccessIsNotReported() {
        XCTAssertFalse(result(success: true).isReportableAnomaly,
                       "a routine success is not worth a log entry")
    }

    func testEachAnomalyIsReported() {
        XCTAssertTrue(result(success: false).isReportableAnomaly, "a failed conversion")
        XCTAssertTrue(result(success: true, clamped: ["Highlight Tone"]).isReportableAnomaly,
                      "the camera disagreed with an assumed range")
        XCTAssertTrue(result(success: true, warnings: ["profile unverified"]).isReportableAnomaly,
                      "a JPEG that may not reflect the recipe — the unverified-body case")
    }
}
