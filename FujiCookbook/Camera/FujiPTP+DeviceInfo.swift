import Foundation

extension FujiPTP {

    // MARK: DeviceInfo (GetDeviceInfo 0x1001)

    /// The PTP **DeviceInfo** dataset (PIMA 15740 §5.5.1): the camera's own statement of what it is
    /// and what it speaks. `operationsSupported` and `devicePropertiesSupported` are the two lists
    /// that matter for compatibility — whether the slot protocol (0xD18C…) exists on a body at all is
    /// answered here before a single property is read — and `deviceVersion` is the firmware string
    /// the app falls back to when neither the caller nor the transport supplies one.
    ///
    /// Parsed leniently: every field is read in order until the data runs out, so a truncated or
    /// vendor-bent dataset still yields whatever came before the break rather than nothing.
    struct DeviceInfo: Equatable, Codable {
        var standardVersion: UInt16 = 100
        var vendorExtensionID: UInt32 = 0
        var vendorExtensionVersion: UInt16 = 0
        var vendorExtensionDesc: String = ""
        var functionalMode: UInt16 = 0
        var operationsSupported: [UInt16] = []
        var eventsSupported: [UInt16] = []
        var devicePropertiesSupported: [UInt16] = []
        var captureFormats: [UInt16] = []
        var imageFormats: [UInt16] = []
        var manufacturer: String = ""
        var model: String = ""
        var deviceVersion: String = ""
        var serialNumber: String = ""

        func supportsProperty(_ code: UInt16) -> Bool { devicePropertiesSupported.contains(code) }

        /// Whether the dataset names the body: product name, serial and firmware all present. What
        /// identifies a body no registry entry matches (`ModelIdentification.unlisted`).
        var namesTheBody: Bool { !model.isEmpty && !serialNumber.isEmpty && !deviceVersion.isEmpty }

        /// The body is connected and talking, but in a USB mode that exposes storage rather than
        /// camera control — so no recipe property exists to read and no wrong-cable or
        /// wrong-permission explanation fits.
        ///
        /// Measured, not guessed. The same GFX100S, one cable-out and cable-in apart
        /// (2026-09-15): in the wrong mode `GetDeviceInfo` was 261 bytes advertising **four**
        /// properties — `0x5001`, `0xD303`, `0xD406`, `0xD407` — and in `USB RAW Conv./Backup
        /// Restore` it was 601 bytes advertising **168**, from `0xD001` to `0xD21B`. So the tell is
        /// not the absence of any one property (this body proves the advertised list isn't
        /// exhaustive — it answers `0xD18C` while never listing it) but the absence of the whole
        /// vendor control block, on a list far too short to be a camera describing its controls.
        ///
        /// Deliberately not triggered by tether mode, which advertises `0xD001…` and so keeps a
        /// control block. That is a different wrong mode with a different answer, and claiming this
        /// one would send the user to the right menu for the wrong reason.
        var looksLikeStorageOnlyMode: Bool {
            guard !devicePropertiesSupported.isEmpty else { return false }   // a refused DeviceInfo says nothing
            guard devicePropertiesSupported.count < 16 else { return false }
            return !devicePropertiesSupported.contains { (0xD000...0xD2FF).contains($0) }
        }
    }

    /// Parse a DeviceInfo dataset. Returns nil only when the fixed header is unreadable.
    static func parseDeviceInfo(_ data: Data) -> DeviceInfo? {
        var info = DeviceInfo()
        var offset = 0
        guard let standard = data.readLE(UInt16.self, at: offset) else { return nil }
        info.standardVersion = standard; offset += 2
        guard let extID = data.readLE(UInt32.self, at: offset) else { return info }
        info.vendorExtensionID = extID; offset += 4
        guard let extVersion = data.readLE(UInt16.self, at: offset) else { return info }
        info.vendorExtensionVersion = extVersion; offset += 2
        guard let desc = readPTPString(data, at: offset) else { return info }
        info.vendorExtensionDesc = desc.value; offset = desc.next
        guard let mode = data.readLE(UInt16.self, at: offset) else { return info }
        info.functionalMode = mode; offset += 2
        guard let ops = readUInt16Array(data, at: offset) else { return info }
        info.operationsSupported = ops.values; offset = ops.next
        guard let events = readUInt16Array(data, at: offset) else { return info }
        info.eventsSupported = events.values; offset = events.next
        guard let props = readUInt16Array(data, at: offset) else { return info }
        info.devicePropertiesSupported = props.values; offset = props.next
        guard let capture = readUInt16Array(data, at: offset) else { return info }
        info.captureFormats = capture.values; offset = capture.next
        guard let image = readUInt16Array(data, at: offset) else { return info }
        info.imageFormats = image.values; offset = image.next
        guard let manufacturer = readPTPString(data, at: offset) else { return info }
        info.manufacturer = manufacturer.value; offset = manufacturer.next
        guard let model = readPTPString(data, at: offset) else { return info }
        info.model = model.value; offset = model.next
        guard let version = readPTPString(data, at: offset) else { return info }
        info.deviceVersion = version.value; offset = version.next
        guard let serial = readPTPString(data, at: offset) else { return info }
        info.serialNumber = serial.value
        return info
    }

    /// Build a DeviceInfo dataset — the inverse of `parseDeviceInfo` — so the demo transport can
    /// answer `GetDeviceInfo` through the real parser, and tests can round-trip it.
    static func encodeDeviceInfo(_ info: DeviceInfo) -> Data {
        var d = Data()
        d.appendLE(info.standardVersion)
        d.appendLE(info.vendorExtensionID)
        d.appendLE(info.vendorExtensionVersion)
        d.append(ptpString(info.vendorExtensionDesc))
        d.appendLE(info.functionalMode)
        for list in [info.operationsSupported, info.eventsSupported, info.devicePropertiesSupported,
                     info.captureFormats, info.imageFormats] {
            d.appendLE(UInt32(list.count))
            for code in list { d.appendLE(code) }
        }
        d.append(ptpString(info.manufacturer))
        d.append(ptpString(info.model))
        d.append(ptpString(info.deviceVersion))
        d.append(ptpString(info.serialNumber))
        return d
    }

    /// A PTP string at `offset`: one byte holding the number of UTF-16 code units *including* the
    /// terminating null, then that many little-endian units. The empty string is a single zero byte.
    /// Returns the string and the offset just past it.
    static func readPTPString(_ data: Data, at offset: Int) -> (value: String, next: Int)? {
        guard let count = data.readLE(UInt8.self, at: offset) else { return nil }
        let end = offset + 1 + Int(count) * 2
        guard end <= data.count else { return nil }
        var units: [UInt16] = []
        var cursor = offset + 1
        while cursor < end, let unit = data.readLE(UInt16.self, at: cursor), unit != 0 {
            units.append(unit)
            cursor += 2
        }
        return (String(utf16CodeUnits: units, count: units.count), end)
    }

    /// A PTP `AUINT16` at `offset`: a 32-bit count, then that many 16-bit values.
    static func readUInt16Array(_ data: Data, at offset: Int) -> (values: [UInt16], next: Int)? {
        guard let count = data.readLE(UInt32.self, at: offset) else { return nil }
        let end = offset + 4 + Int(count) * 2
        guard end <= data.count else { return nil }
        var values: [UInt16] = []
        values.reserveCapacity(Int(count))
        var cursor = offset + 4
        while cursor < end, let value = data.readLE(UInt16.self, at: cursor) {
            values.append(value)
            cursor += 2
        }
        return (values, end)
    }

    /// PIMA form of a string: empty is a lone zero byte, otherwise `FujiEncoding.packPTPString`.
    private static func ptpString(_ value: String) -> Data {
        value.isEmpty ? Data([0]) : FujiEncoding.packPTPString(value)
    }

    // MARK: Names

    /// Human name for a PTP operation code (PIMA 15740 §10 plus the Fuji vendor ops the app uses),
    /// so a trace and a DeviceInfo listing read without a lookup table.
    static func operationName(_ code: UInt16) -> String? {
        switch code {
        case 0x1001: return "GetDeviceInfo"
        case 0x1002: return "OpenSession"
        case 0x1003: return "CloseSession"
        case 0x1004: return "GetStorageIDs"
        case 0x1005: return "GetStorageInfo"
        case 0x1006: return "GetNumObjects"
        case 0x1007: return "GetObjectHandles"
        case 0x1008: return "GetObjectInfo"
        case 0x1009: return "GetObject"
        case 0x100A: return "GetThumb"
        case 0x100B: return "DeleteObject"
        case 0x100C: return "SendObjectInfo"
        case 0x100D: return "SendObject"
        case 0x100E: return "InitiateCapture"
        case 0x100F: return "FormatStore"
        case 0x1010: return "ResetDevice"
        case 0x1011: return "SelfTest"
        case 0x1012: return "SetObjectProtection"
        case 0x1013: return "PowerDown"
        case 0x1014: return "GetDevicePropDesc"
        case 0x1015: return "GetDevicePropValue"
        case 0x1016: return "SetDevicePropValue"
        case 0x1017: return "ResetDevicePropValue"
        case 0x1018: return "TerminateOpenCapture"
        case 0x1019: return "MoveObject"
        case 0x101A: return "CopyObject"
        case 0x101B: return "GetPartialObject"
        case 0x101C: return "InitiateOpenCapture"
        case 0x900C: return "SendObjectInfo (Fuji)"
        case 0x900D: return "SendObject2 (Fuji)"
        default: return nil
        }
    }

    /// Human name for a device property the app knows: the `Prop` codes listed below plus the preset
    /// set (`PresetProp.debugName`). Unknown codes get nil, and are spelled as hex by the caller.
    static func propertyName(_ code: UInt16) -> String? {
        switch code {
        case Prop.slotSelector: return "Slot Selector"
        case Prop.presetName: return "Preset Name"
        case Prop.rawConvProfile: return "RAW Conv. Profile"
        case Prop.startRawConversion: return "Start RAW Conversion"
        case Prop.exposureIndex: return "ISO (ExposureIndex)"
        default: return PresetProp(rawValue: code)?.debugName
        }
    }
}
