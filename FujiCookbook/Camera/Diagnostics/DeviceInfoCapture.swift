import Foundation

/// Reads `GetDeviceInfo` once per connect, for every body, and records it in the report and the
/// log. The serial number is only ever hashed into the report.
@MainActor
struct DeviceInfoCapture {
    let transport: CameraTransport
    let reports: CompatibilityReportRecorder

    /// Returns the parsed dataset, or nil when the transport has none, the body refused it or it
    /// didn't parse; each of those is recorded in the report. The caller reads the firmware string
    /// from it and, before anything else, whether the body is in a USB mode that has no recipes in it.
    func run(model: CameraModel?) async -> FujiPTP.DeviceInfo? {
        do {
            guard let data = try await transport.deviceInfo() else {
                reports.note("transport offers no GetDeviceInfo")
                return nil
            }
            guard let info = FujiPTP.parseDeviceInfo(data) else {
                reports.update { $0.recordDeviceInfoFailure("unparseable dataset (\(data.count) bytes)") }
                CameraLog.error("DeviceInfo: unparseable dataset (\(data.count) bytes)")
                return nil
            }
            reports.update { $0.record(deviceInfo: info, rawLength: data.count) }
            // Model, firmware and code lists only — the serial is hashed into the report and never logged.
            CameraLog.info("DeviceInfo: \(info.manufacturer) \(info.model) fw \(info.deviceVersion.isEmpty ? "?" : info.deviceVersion) · PTP \(info.standardVersion) · ext \(String(format: "0x%08X", info.vendorExtensionID)) \"\(info.vendorExtensionDesc)\" · \(data.count) bytes")
            CameraLog.info("DeviceInfo: operations [\(info.operationsSupported.map(PTPHex.code).joined(separator: " "))]")
            CameraLog.info("DeviceInfo: properties [\(info.devicePropertiesSupported.map(PTPHex.code).joined(separator: " "))]")
            let slotProtocol = info.supportsProperty(FujiPTP.Prop.slotSelector) && info.supportsProperty(FujiPTP.Prop.presetName)
            // Corroboration, never a gate. This list is not exhaustive on Fujifilm bodies (an X-T20
            // fw 2.01 omits 0xD183 here and still answers a descriptor for it; owner report,
            // zgrimz/fujifilm-ptp-reference `docs/01-transport.md#the-advertised-lists-are-not-complete`
            // and `docs/07-cameras.md#x-t20`), so a capability is decided by the registry and only
            // *described* by DeviceInfo. Naming the registry's expectation next to it makes a
            // disagreement legible in a shared log.
            let expectation = model.map { $0.supportsSlotProtocol ? "registry expects it" : "registry expects none" }
                ?? "unrecognized body"
            CameraLog.info("DeviceInfo: slot protocol (D18C/D18D) \(slotProtocol ? "advertised" : "NOT advertised") — \(expectation) · \(info.devicePropertiesSupported.count) properties, \(info.operationsSupported.count) operations")
            return info
        } catch {
            let detail = error.cameraLogDescription
            reports.update { $0.recordDeviceInfoFailure(detail) }
            CameraLog.error("DeviceInfo: failed — \(detail)")
            return nil
        }
    }

}
