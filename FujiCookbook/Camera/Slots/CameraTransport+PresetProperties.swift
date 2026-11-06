import Foundation

/// What a complete property pass over the selected slot found (`readAllPresetProperties`).
struct PresetPropertyRead {
    /// The bytes each property answered, by code. A property that answered OK with no data phase is
    /// absent here, and so is one the body lacks.
    var values: [UInt16: Data] = [:]
    /// The properties that answered `0x200A DeviceProp Not Supported`: the body lacks them, so the
    /// slot holds nothing for them to preserve or put back. An X100V answers it to `0xD18E`,
    /// `0xD18F`, `0xD1A3` and `0xD1A4` on every bank while the other 19 read
    /// (zgrimz/fujifilm-ptp-reference `docs/01-transport.md#response-codes`).
    var unsupported: [FujiPTP.PresetProp] = []
}

extension CameraTransport {

    /// A complete property pass over the selected slot, for push preflight and verification.
    ///
    /// A property the body lacks (`0x200A`) goes into `unsupported` and stays out of `values`, as it
    /// stays out of a walked slot (`SlotReader.readPresetProps`), so preflight plans nothing for it.
    /// Any other failure throws: a read that fails for another reason leaves the slot's contents
    /// unknown, and preflight requires every planned write's original.
    func readAllPresetProperties() async throws -> PresetPropertyRead {
        var read = PresetPropertyRead()
        for prop in FujiPTP.PresetProp.allCases {
            do {
                if let bytes = try await readProperty(prop.rawValue) { read.values[prop.rawValue] = bytes }
            } catch CameraError.ptpError(let code) where code == FujiPTP.responseDevicePropNotSupported {
                read.unsupported.append(prop)
            }
        }
        return read
    }
}
