import XCTest
@testable import FujiCookbook

/// The four lines every report starts with, from one place.
///
/// They were computed in three, and had drifted — two fell back to `"?"` for a missing `Info.plist`
/// key and the third to `"—"`. Low value as assertions; the point is that a fourth copy can't be
/// reintroduced without someone noticing this file.
@MainActor
final class AppIdentityTests: XCTestCase {

    func testVersionStringIsMarketingVersionThenBuild() {
        XCTAssertEqual(AppIdentity.versionString, "\(AppIdentity.version) (\(AppIdentity.build))")
    }

    func testDeviceIdentifierIsAHardwareName() {
        let id = AppIdentity.deviceIdentifier
        XCTAssertFalse(id.isEmpty)
        XCTAssertFalse(id.contains("/"), "a model identifier, not a path")
    }

    /// Load-bearing: `HostInfo.systemVersion` is a `Codable` field in the JSON wire artifact and
    /// stores the version bare; the `"iOS "` belongs to the rendering.
    func testSystemVersionIsBare() {
        XCTAssertFalse(AppIdentity.systemVersion.hasPrefix("iOS"))
    }

    func testTheCompatibilityReportReadsTheSameValues() {
        XCTAssertEqual(CameraCompatibilityReport.AppInfo.current.version, AppIdentity.version)
        XCTAssertEqual(CameraCompatibilityReport.AppInfo.current.build, AppIdentity.build)
        XCTAssertEqual(CameraCompatibilityReport.HostInfo.current.deviceIdentifier,
                       AppIdentity.deviceIdentifier)
        XCTAssertEqual(CameraCompatibilityReport.HostInfo.current.systemVersion,
                       AppIdentity.systemVersion)
    }

    /// Feedback and problem reports both open with these, and a reader lines two files up by them,
    /// so the values start in one column.
    func testReportLinesAreTheFourFieldsInOneColumn() {
        let lines = AppIdentity.reportLines
        XCTAssertEqual(lines, [
            "App          \(AppIdentity.versionString)",
            "Channel      \(BuildChannel.current.rawValue)",
            "System       iOS \(AppIdentity.systemVersion)",
            "Device       \(AppIdentity.deviceIdentifier)",
        ])
        let valueColumns = Set(lines.map { line in
            line.distance(from: line.startIndex, to: line.firstIndex(where: { $0 == " " })!)
                + line.drop(while: { $0 != " " }).prefix(while: { $0 == " " }).count
        })
        XCTAssertEqual(valueColumns, [13])
    }
}
