import XCTest
@testable import FujiCookbook

final class CameraPropertyReportTextTests: XCTestCase {

    private func connected(_ identification: ModelIdentification) -> ConnectedCamera {
        ConnectedCamera(productName: identification.model?.displayName ?? "FUJIFILM X-T99",
                        firmwareVersion: "1.32", identification: identification, isDemo: false,
                        writeAccess: WriteDecision.decide(identification: identification, observed: ObservedCapabilities(),
                                                          firmwareVersion: "1.32", serialHash: nil))
    }

    private func model(_ id: String) throws -> CameraModel {
        try XCTUnwrap(CameraModelRegistry.shared.model(withID: id))
    }

    private let grain = PropertyProbe(code: FujiPTP.PresetProp.grain.rawValue, name: "Grain Effect",
                                      value: Data([0x06, 0x00]), descriptor: nil,
                                      valueError: nil, descriptorError: "0x2005 Operation Not Supported")

    /// The report names the slot the read came back with, which on a read-only body is the camera's
    /// own selection, not whatever the picker shows.
    func testTheReportNamesTheSlotItRead() throws {
        let text = CameraPropertyReportView.reportText(camera: connected(.exact(try model("X-T50"))),
                                                       read: .init(slot: 3, probes: [grain]))
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Darkslide — camera property report")
        XCTAssertEqual(lines[1], "Camera: \(try model("X-T50").displayName) · model X-T50 · firmware 1.32")
        XCTAssertEqual(lines[2], "Slot: C3")
        XCTAssertEqual(lines[3], "")
        XCTAssertEqual(lines[4], "\(PTPHex.propertyLabel(grain.code))  Grain Effect")
        XCTAssertEqual(lines[5], "      holds:   \(grain.valueSummary)")
        XCTAssertEqual(lines[6], "      accepts: 0x2005 Operation Not Supported")
        XCTAssertEqual(lines.count, 7)
    }

    func testAnUnrecognizedBodyIsSaidSo() {
        let text = CameraPropertyReportView.reportText(camera: connected(.unknown), read: .init(slot: 1, probes: []))
        XCTAssertTrue(text.contains("Camera: FUJIFILM X-T99 · unrecognized model · firmware 1.32"), text)
    }

    func testAProbeExportNamesTheSlotItRanOn() {
        let run = CameraPropertyReportView.ProbeRun(slot: 4, entries: [
            WriteProbeEntry(step: 0, wrote: 1, writeError: nil, readBack: 1),
            WriteProbeEntry(step: 1, wrote: 2, writeError: "0x201C Invalid DeviceProp Value", readBack: nil),
        ])
        XCTAssertEqual(CameraPropertyReportView.grainProbeText(camera: nil, run: run), """
            Darkslide — D195 grain write probe
            Slot: C4
            wrote 1: ACCEPTED
            wrote 2: rejected (0x201C Invalid DeviceProp Value)
            """)
    }

    func testTheDynamicRangeExportLabelsAutoAndCarriesTheNote() {
        let run = CameraPropertyReportView.ProbeRun(slot: 2, entries: [
            WriteProbeEntry(step: 0, wrote: FujiEncoding.drAutoSlotValue, writeError: nil, readBack: FujiEncoding.drAutoSlotValue),
        ])
        let lines = CameraPropertyReportView.dynamicRangeProbeText(camera: connected(.unknown), run: run)
            .components(separatedBy: "\n")
        XCTAssertEqual(Array(lines.prefix(4)), [
            "Darkslide — D190 dynamic range write probe",
            "Camera: FUJIFILM X-T99",
            "Slot: C2",
            "wrote DR Auto: ACCEPTED",
        ])
        XCTAssertTrue(lines.last?.hasPrefix("Note: the slot's own ISO and D-Range Priority") == true)
    }
}
