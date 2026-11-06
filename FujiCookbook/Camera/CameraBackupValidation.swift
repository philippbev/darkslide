import Foundation

/// Validation for bytes that may be restored. Diagnostics can retain unfamiliar data; a restore
/// must account for every property before selecting a slot or writing its name.
enum CameraBackupValidation {
    // Version 1 describes C1–C7. Connected-camera bounds are checked again at the write boundary.
    static let slotRange = 1...7

    static func slot(_ index: Int, maximum: Int = slotRange.upperBound) throws {
        guard slotRange.contains(index), index <= maximum else {
            throw CameraBackupError.invalidContents("Slot C\(index) is outside this camera's custom-slot range.")
        }
    }

    static func properties(_ encoded: [String: String]) throws -> [UInt16: Data] {
        var decoded: [UInt16: Data] = [:]
        for (key, hex) in encoded {
            let digits = key.dropFirst(2)
            guard key.count == 6, key.prefix(2).lowercased() == "0x",
                  digits.utf8.allSatisfy(isHexDigit), let code = UInt16(digits, radix: 16) else {
                throw CameraBackupError.invalidContents("A property code is malformed; expected a code such as 0xD192.")
            }
            guard decoded[code] == nil else {
                throw CameraBackupError.invalidContents("Property \(PTPHex.code(code)) appears more than once.")
            }
            guard hex.count == 4, hex.utf8.allSatisfy(isHexDigit), let bytes = Data(hexString: hex) else {
                throw CameraBackupError.invalidContents("Property \(PTPHex.code(code)) must contain exactly two bytes of hexadecimal data.")
            }
            decoded[code] = bytes
        }
        try properties(decoded)
        return decoded
    }

    static func properties(_ decoded: [UInt16: Data]) throws {
        for (code, bytes) in decoded {
            guard code != FujiPTP.Prop.liveImageSize else {
                throw CameraBackupError.invalidContents("Property 0xD1A5 controls live Image Size, not a bank setting. This older backup cannot be replayed as a bank restore.")
            }
            guard FujiPTP.PresetProp(rawValue: code) != nil else {
                throw CameraBackupError.invalidContents("Property \(PTPHex.code(code)) is not a supported custom-slot property.")
            }
            guard bytes.count == 2 else {
                throw CameraBackupError.invalidContents("Property \(PTPHex.code(code)) must contain exactly two bytes.")
            }
        }
    }

    static func restore(_ properties: [UInt16: Data], slot index: Int, maximum: Int) throws {
        try slot(index, maximum: maximum)
        guard !properties.isEmpty else {
            throw CameraBackupError.invalidContents("The saved slot has no settings to restore.")
        }
        try self.properties(properties)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }
}
