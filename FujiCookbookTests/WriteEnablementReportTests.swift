import XCTest
@testable import FujiCookbook

/// The compatibility report carries what promotes or corrects a registry entry: what the selector
/// answered, how the slot read ended, where the body disagreed with its entry, what the app decided
/// about writing, and how the staged first write went. Version 7; every field optional, so a report
/// an earlier build wrote still decodes.
@MainActor
final class WriteEnablementReportTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    private func connect(_ faults: MockCameraFaults) async -> CameraServices {
        var faults = faults
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    private var recipe: RecipeSettings {
        RecipeSettings(filmSimulation: .classicNeg, dynamicRange: .dr400, sharpness: -1)
    }

    func testAV6ReportStillDecodesUnderV7() throws {
        let v6 = """
        {
          "reportVersion": 6,
          "generatedAt": "2026-11-01T10:00:00Z",
          "updatedAt": "2026-11-01T10:00:05Z",
          "app": { "version": "1.0.1", "build": "16", "channel": "testflight" },
          "host": { "systemVersion": "27.0", "deviceIdentifier": "iPhone17,1" },
          "camera": { "productName": "FUJIFILM X-T50", "transport": "usb", "identification": "exact",
                      "verification": "hardware" },
          "slots": { "assumedSlotCount": 7, "probedSlotCount": 7, "selectorBeforeRead": 1, "selectorRestored": true, "reads": [] },
          "unsupportedPropertyCodes": [],
          "transactions": [],
          "transactionsDropped": 0,
          "notes": [],
          "pushes": [ { "at": "2026-11-01T10:00:03Z", "slot": 1, "outcome": "applied", "nameWritten": true,
                        "clampedFields": [], "fields": [] } ]
        }
        """
        let report = try CameraCompatibilityReport.decode(Data(v6.utf8))
        XCTAssertEqual(report.reportVersion, 6)
        XCTAssertNil(report.camera.writeAccess, "absent, not defaulted — that build made no such decision")
        XCTAssertNil(report.slots.selectorRead)
        XCTAssertNil(report.slots.walkResult)
        XCTAssertNil(report.slots.registryDisagreements)
        XCTAssertNil(report.pushes?.first?.firstWrite)
        XCTAssertFalse(report.textRendering.isEmpty, "and it still renders")
    }

    func testTheConnectRecordsWhatTheSelectorAndWalkAnsweredAndWhatWasDecided() async throws {
        let m = await connect(.unlistedBody)
        var report = try XCTUnwrap(m.reports.report)
        XCTAssertEqual(report.slots.selectorRead, "C1")
        XCTAssertEqual(report.slots.walkResult, "finished: 7 banks, all read")
        XCTAssertEqual(report.camera.writeAccess, "granted(walk, unverified)")
        XCTAssertNil(report.slots.registryDisagreements, "an unlisted body has no entry to disagree with")
        XCTAssertTrue(report.textRendering.contains("selector C1"))
        XCTAssertTrue(report.textRendering.contains("walk finished: 7 banks, all read"))
        XCTAssertTrue(report.textRendering.contains("Identified  FUJIFILM X-T99 (unlisted)"), "the body is named, not dashed out")
        XCTAssertTrue(report.textRendering.contains("Writes      granted(walk, unverified)"), "the decision is in the text a tester shares, not only in the JSON")

        let result = await m.slotWriter.push(settings: recipe, name: "Recorded", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied, result.errorMessage ?? "")
        report = try XCTUnwrap(m.reports.report)
        XCTAssertEqual(report.camera.writeAccess, "granted(walk, verified)", "the decision moved with the push")
        XCTAssertTrue(report.textRendering.contains("Writes      granted(walk, verified)"))
        let first = try XCTUnwrap(report.pushes?.first?.firstWrite)
        XCTAssertEqual(first.property, "0xD192")
        XCTAssertEqual(first.outcome, "written")
        XCTAssertNil(first.responseCode)
        XCTAssertNil(first.restore)
        XCTAssertTrue(report.textRendering.contains("first write: 0xD192 written"))
        let decoded = try CameraCompatibilityReport.decode(report.json)
        XCTAssertEqual(decoded.slots, report.slots)
        XCTAssertEqual(decoded.camera, report.camera)
        XCTAssertEqual(decoded.pushes, report.pushes)
    }

    func testAStageOneStopIsRecordedWithItsRestore() async throws {
        var faults = MockCameraFaults.unlistedBody
        faults.unsupportedWriteCodes = [FujiPTP.PresetProp.filmSimulation.rawValue]
        let m = await connect(faults)
        _ = await m.slotWriter.push(settings: recipe, name: "Stopped", toSlot: 1)
        let report = try XCTUnwrap(m.reports.report)
        let first = try XCTUnwrap(report.pushes?.first?.firstWrite)
        XCTAssertEqual(first.outcome, "refused")
        XCTAssertEqual(first.responseCode, "0x200A")
        XCTAssertEqual(first.restore, "unchanged")
        XCTAssertEqual(report.camera.writeAccess, "granted(walk, unverified)", "a stop doesn't verify")
        XCTAssertTrue(report.textRendering.contains("first write: 0xD192 refused 0x200A · unchanged"))
    }

    func testWhereTheBodyDisagreesWithItsEntryIsRecorded() async throws {
        let xH1 = await connect(MockCameraFaults(productName: "FUJIFILM X-H1", firmwareVersion: "2.01"))
        let protocolRow = try XCTUnwrap(xH1.reports.report?.slots.registryDisagreements?.first { $0.field == "slot protocol" })
        XCTAssertEqual(protocolRow.registry, "none expected")
        XCTAssertEqual(protocolRow.observed, "the selector answered C1")
        XCTAssertTrue(xH1.reports.report?.textRendering.contains("! registry disagrees on slot protocol") ?? false)

        let gfx = await connect(.readOnlyWithSlots)
        let countRow = try XCTUnwrap(gfx.reports.report?.slots.registryDisagreements?.first { $0.field == "documented slot count" })
        XCTAssertEqual(countRow.registry, "6", "the GFX100 II's manual gives six")
        XCTAssertEqual(countRow.observed, "7 accepted a select", "the mock accepts seven")
        XCTAssertNil(gfx.reports.report?.slots.registryDisagreements?.first { $0.field == "slot protocol" },
                     "the entry expects the protocol and the selector answered")
    }

    func testABlockedBodyAndAHardwareBodyRecordTheirDecisions() async throws {
        let blocked = await connect(.noSlotProtocolBody)
        XCTAssertEqual(blocked.reports.report?.camera.writeAccess, "refused(blocked-by-record)")
        XCTAssertEqual(blocked.reports.report?.slots.selectorRead, "not read")
        XCTAssertEqual(blocked.reports.report?.slots.walkResult, "swept read-only")
        XCTAssertNil(blocked.reports.report?.slots.registryDisagreements)

        let xt50 = await connect(MockCameraFaults(productName: "FUJIFILM X-T50", firmwareVersion: "1.32"))
        XCTAssertEqual(xt50.reports.report?.camera.writeAccess, "granted(trusted-entry(hardware), verified)")
        XCTAssertNil(xt50.reports.report?.slots.registryDisagreements, "seven banks, as the registry and the manual say")
    }

    func testARefusedWalkRecordsItsReason() async throws {
        var faults = MockCameraFaults.readOnlyWithSlots
        faults.silentlyIgnoredWriteCodes = [FujiPTP.Prop.slotSelector]
        let m = await connect(faults)
        XCTAssertEqual(m.reports.report?.camera.writeAccess, "refused(select-ignored(C2))")
        XCTAssertEqual(m.reports.report?.slots.walkResult, "stopped: select of C2 answered OK and did not take")
    }
}
