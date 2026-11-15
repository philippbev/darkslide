import Foundation

/// PTP primitives and the Fuji vendor property map.
///
/// The standard PTP operation codes and 12-byte container layout are PIMA-15740 facts. The Fuji
/// property codes below are the ones X RAW Studio uses, with the evidence for each in
/// zgrimz/fujifilm-ptp-reference `docs/02-properties.md` (see also `docs/fuji-recipe-ptp-protocol.md`).
/// On iOS these same containers are sent through `ICCameraDevice.requestSendPTPCommand`.
enum FujiPTP {

    // MARK: Standard PTP operation codes (PIMA 15740)

    enum Operation: UInt16 {
        case getDeviceInfo      = 0x1001
        case openSession        = 0x1002
        case closeSession       = 0x1003
        case getObjectHandles   = 0x1007
        case getObjectInfo      = 0x1008
        case getObject          = 0x1009
        case getThumb           = 0x100A
        /// Standard PTP read of a byte range of an object. Used only by the photo import to read a
        /// file's first bytes for its MakerNote. The X100VI answers it in card-reader mode: 12 of
        /// 12 reads of 160 KB found the simulation, 170–283 ms each (fw 1.31, 2026-11-15).
        case getPartialObject   = 0x101B
        case deleteObject       = 0x100B
        case getDevicePropDesc  = 0x1014
        case getDevicePropValue = 0x1015
        case setDevicePropValue = 0x1016
        // Fuji vendor object-transfer ops used by the RAW-conversion (X RAW Studio) flow.
        case sendObjectInfo     = 0x900C
        case sendObject2        = 0x900D
    }

    /// PTP ObjectFormatCode for a Fujifilm RAF file, used when uploading a RAW for conversion
    /// (zgrimz/fujifilm-ptp-reference `docs/05-raw-conversion.md`).
    static let rafObjectFormat: UInt16 = 0xF802

    /// The fixed object name the RAF is uploaded under for conversion — what X RAW Studio and the
    /// published implementations all use, regardless of the real filename
    /// (zgrimz/fujifilm-ptp-reference `docs/05-raw-conversion.md#the-sequence`). Early X-T50 bring-up got a real
    /// `0x2015` (No_Valid_ObjectInfo) from SendObject with a wrong upload, but which part was wrong
    /// — the name or the parameters — was not recorded, so that any other name fails is untested.
    static let rawConversionUploadName = "FUP_FILE.dat"

    enum ContainerType: UInt16 {
        case command  = 1
        case data     = 2
        case response = 3
        case event    = 4
    }

    static let responseOK: UInt16 = 0x2001

    /// The body doesn't implement this property at all. Named because it is the code that decides
    /// whether a property is missing (skip it and carry on) or the read genuinely failed — the
    /// distinction the slot walk (`SlotReader.readPresetProps`) and the read-only sweep make on a
    /// body we haven't characterized.
    static let responseDevicePropNotSupported: UInt16 = 0x200A

    /// The body implements the property but rejects the value written. The other half of the same
    /// question: the encoding is wrong or the body's current state refuses the value, rather than the
    /// property being absent.
    static let responseInvalidDevicePropValue: UInt16 = 0x201C

    /// The body refused the command as busy. A conversion that never completes can leave a body
    /// answering this to everything until it is switched off and on (zgrimz/fujifilm-ptp-reference
    /// `docs/01-transport.md`), which is why the app's message for it says to do that.
    static let responseDeviceBusy: UInt16 = 0x2019

    /// Human-readable name for a standard PTP response code (PIMA 15740 §11.3), so error messages
    /// during hardware bring-up name the failure instead of showing a bare hex code.
    static func responseName(_ code: UInt16) -> String? {
        switch code {
        case 0x2001: return "OK"
        case 0x2002: return "General Error"
        case 0x2003: return "Session Not Open"
        case 0x2004: return "Invalid TransactionID"
        case 0x2005: return "Operation Not Supported"
        case 0x2006: return "Parameter Not Supported"
        case 0x2007: return "Incomplete Transfer"
        case 0x2008: return "Invalid StorageID"
        case 0x2009: return "Invalid ObjectHandle"
        case 0x200A: return "DeviceProp Not Supported"
        case 0x200B: return "Invalid ObjectFormatCode"
        case 0x200C: return "Store Full"
        case 0x200D: return "Object WriteProtected"
        case 0x200E: return "Store Read-Only"
        case 0x200F: return "Access Denied"
        case 0x2010: return "No Thumbnail Present"
        case 0x2013: return "Store Not Available"
        case 0x2014: return "Specification By Format Unsupported"
        case 0x2015: return "No Valid ObjectInfo"
        case 0x2016: return "Invalid Code Format"
        case 0x2019: return "Device Busy"
        case 0x201A: return "Invalid ParentObject"
        case 0x201C: return "Invalid DeviceProp Value"
        case 0x201D: return "Invalid Parameter"
        case 0x201E: return "Session Already Open"
        default: return nil
        }
    }

    // MARK: Fuji vendor device-property codes

    /// Recipe-management control properties.
    enum Prop {
        /// Trigger: 1 = full-res, 0 = downscaled ~4 MB, 2 = rejected (zgrimz/fujifilm-ptp-reference
        /// `docs/05-raw-conversion.md#the-sequence`).
        static let startRawConversion: UInt16 = 0xD183
        /// **ISO**, the standard PTP `ExposureIndex` — the only property this app reads outside the
        /// Fuji vendor range, and the reason `PTPHex.propertyLabel` exists.
        ///
        /// It is read to answer one question: the ISO is what gates `D190` (DR200 at 2× base,
        /// DR400 at 4×) and `D191` outright, and the app learns about that only by being refused —
        /// so if `0x500F` tracked the selected bank, one read after the slot select would make the
        /// refusal predictable. **On an X-T50 it is not supported at all**: `0x200A`, on banks at
        /// ISO 500 and ISO 125 alike (fw 1.32, 2026-09-18). Still open on the GFX100S, which does
        /// advertise it in DeviceInfo.
        ///
        /// Kept in both sweeps regardless. A recorded `0x200A` is the finding — it is what says the
        /// gate is invisible on this body rather than merely unread — and it costs one transaction.
        static let exposureIndex: UInt16       = 0x500F  // ISO — see both property sweeps
        static let rawConvProfile: UInt16     = 0xD185  // 600-odd-byte conversion profile blob
        static let slotSelector: UInt16        = 0xD18C  // select custom slot (C1 = 1, C2 = 2, …)
        static let presetName: UInt16          = 0xD18D  // slot name (PTP wide string)
        /// Live Image Size; outside the bank namespace and never part of bank backup/restore.
        static let liveImageSize: UInt16       = 0xD1A5
    }

    /// The 23 per-slot preset properties (0xD18E … 0xD1A4). Read all to import a slot; write the
    /// editable ones (in `FujiPresetCodec`'s order) to push.
    enum PresetProp: UInt16, CaseIterable {
        case imageSize          = 0xD18E
        case imageQuality       = 0xD18F
        case dynamicRange       = 0xD190
        case dRangePriority     = 0xD191
        case filmSimulation     = 0xD192
        case monochromaticWC    = 0xD193
        case monochromaticMG    = 0xD194
        case grain              = 0xD195
        case colorChrome        = 0xD196
        case colorChromeFXBlue  = 0xD197
        case smoothSkin         = 0xD198
        case whiteBalance       = 0xD199
        case wbShiftR           = 0xD19A
        case wbShiftB           = 0xD19B
        case colorTemp          = 0xD19C
        case highlightTone      = 0xD19D
        case shadowTone         = 0xD19E
        case color              = 0xD19F
        case sharpness          = 0xD1A0
        case highISONR          = 0xD1A1
        case clarity            = 0xD1A2
        /// Lens Modulation Optimizer, `1` ON and `2` OFF: toggling it in a bank's menu moves this
        /// property and nothing else, and toggling Long Exposure NR (the name a published source gives
        /// it) moves nothing in the block (X-T50 fw 1.32, 2026-10-15;
        /// zgrimz/fujifilm-ptp-reference `docs/02-properties.md`, `docs/errata.md`).
        /// Housekeeping: carried through, never authored.
        case lensModulationOptimizer = 0xD1A3
        case colorSpace         = 0xD1A4
    }

    // MARK: DevicePropDesc (GetDevicePropDesc 0x1014)

    /// A parsed PTP **DevicePropDesc** dataset (PIMA-15740 §5.5.4): the camera's own description of a
    /// property — its data type, whether it's writable, and the set of values it will accept. This is
    /// the ground truth the hand-transcribed encodings in `FujiEncoding` are checked against: when a
    /// body silently discards a `SetDevicePropValue` (answering OK but keeping its old value), the
    /// enumeration here says which values it would have taken. Not every body answers it; the X-T50
    /// refuses `GetDevicePropDesc`.
    ///
    /// Diagnostics only — nothing in the read/import/push path depends on it.
    struct PropertyDescriptor: Equatable {
        enum Form: Equatable {
            case none
            case range(min: Int, max: Int, step: Int)
            case enumeration([Int])
        }

        var code: UInt16
        var dataType: UInt16
        /// GetSet byte: 0 = read-only, 1 = read/write.
        var isWritable: Bool
        /// Factory default and current value, decoded per `dataType`. Nil for the types this parser
        /// doesn't decode (strings, arrays, 128-bit) — the descriptor is still returned.
        var factoryDefault: Int?
        var current: Int?
        var form: Form

        /// e.g. `UINT16`, or `type 0x4004` for the ones we don't name.
        var dataTypeName: String {
            switch dataType {
            case 0x0001: return "INT8"
            case 0x0002: return "UINT8"
            case 0x0003: return "INT16"
            case 0x0004: return "UINT16"
            case 0x0005: return "INT32"
            case 0x0006: return "UINT32"
            case 0x0007: return "INT64"
            case 0x0008: return "UINT64"
            case 0xFFFF: return "STR"
            default: return String(format: "type 0x%04X", dataType)
            }
        }
    }

    /// Byte width of a scalar PTP data type, or nil for strings/arrays/128-bit values.
    private static func scalarSize(of dataType: UInt16) -> Int? {
        switch dataType {
        case 0x0001, 0x0002: return 1
        case 0x0003, 0x0004: return 2
        case 0x0005, 0x0006: return 4
        case 0x0007, 0x0008: return 8
        default: return nil
        }
    }

    private static func isSigned(_ dataType: UInt16) -> Bool {
        dataType == 0x0001 || dataType == 0x0003 || dataType == 0x0005 || dataType == 0x0007
    }

    /// Read one scalar of `dataType` at `offset`, sign-extended when the type is signed.
    private static func scalar(_ data: Data, at offset: Int, dataType: UInt16) -> Int? {
        switch scalarSize(of: dataType) {
        case 1:
            guard let v = data.readLE(UInt8.self, at: offset) else { return nil }
            return isSigned(dataType) ? Int(Int8(bitPattern: v)) : Int(v)
        case 2:
            guard let v = data.readLE(UInt16.self, at: offset) else { return nil }
            return isSigned(dataType) ? Int(Int16(bitPattern: v)) : Int(v)
        case 4:
            guard let v = data.readLE(UInt32.self, at: offset) else { return nil }
            return isSigned(dataType) ? Int(Int32(bitPattern: v)) : Int(v)
        case 8:
            guard let v = data.readLE(UInt64.self, at: offset) else { return nil }
            return isSigned(dataType) ? Int(Int64(bitPattern: v)) : Int(exactly: v)
        default:
            return nil
        }
    }

    /// Parse a DevicePropDesc dataset. Returns nil only if the header itself is unreadable; a
    /// descriptor whose value type we can't decode still comes back (with `.none` form), so the
    /// report can show the camera answered at all.
    static func parsePropertyDescriptor(_ data: Data) -> PropertyDescriptor? {
        guard let code = data.readLE(UInt16.self, at: 0),
              let dataType = data.readLE(UInt16.self, at: 2),
              let getSet = data.readLE(UInt8.self, at: 4) else { return nil }

        var desc = PropertyDescriptor(code: code, dataType: dataType, isWritable: getSet == 1,
                                      factoryDefault: nil, current: nil, form: .none)
        guard let size = scalarSize(of: dataType) else { return desc }

        var offset = 5
        desc.factoryDefault = scalar(data, at: offset, dataType: dataType); offset += size
        desc.current = scalar(data, at: offset, dataType: dataType); offset += size

        guard let formFlag = data.readLE(UInt8.self, at: offset) else { return desc }
        offset += 1
        switch formFlag {
        case 1:   // range: min, max, step
            guard let min = scalar(data, at: offset, dataType: dataType),
                  let max = scalar(data, at: offset + size, dataType: dataType),
                  let step = scalar(data, at: offset + 2 * size, dataType: dataType) else { return desc }
            desc.form = .range(min: min, max: max, step: step)
        case 2:   // enumeration: count, then that many values
            guard let count = data.readLE(UInt16.self, at: offset) else { return desc }
            offset += 2
            var values: [Int] = []
            for _ in 0..<Int(count) {
                guard let v = scalar(data, at: offset, dataType: dataType) else { break }
                values.append(v)
                offset += size
            }
            desc.form = .enumeration(values)
        default:
            break
        }
        return desc
    }

    /// Build a DevicePropDesc dataset (the inverse of `parsePropertyDescriptor`) — used by the demo
    /// transport so the property probe exercises the real parser with no hardware attached.
    static func encodePropertyDescriptor(_ desc: PropertyDescriptor) -> Data {
        var d = Data()
        d.appendLE(desc.code)
        d.appendLE(desc.dataType)
        d.append(UInt8(desc.isWritable ? 1 : 0))
        guard scalarSize(of: desc.dataType) != nil else { return d }
        func appendScalar(_ value: Int) {
            switch scalarSize(of: desc.dataType) {
            case 1: d.append(UInt8(truncatingIfNeeded: value))
            case 2: d.appendLE(UInt16(truncatingIfNeeded: value))
            case 4: d.appendLE(UInt32(truncatingIfNeeded: value))
            default: d.appendLE(UInt32(truncatingIfNeeded: value)); d.appendLE(UInt32(0))
            }
        }
        appendScalar(desc.factoryDefault ?? 0)
        appendScalar(desc.current ?? 0)
        switch desc.form {
        case .none:
            d.append(UInt8(0))
        case .range(let min, let max, let step):
            d.append(UInt8(1)); appendScalar(min); appendScalar(max); appendScalar(step)
        case .enumeration(let values):
            d.append(UInt8(2)); d.appendLE(UInt16(values.count)); values.forEach(appendScalar)
        }
        return d
    }

    // MARK: Container construction

    /// Build a PTP **command** container: `[u32 length][u16 type][u16 code][u32 transactionID][params…]`
    /// (little-endian, up to five uint32 params).
    static func commandContainer(operation: Operation,
                                 transactionID: UInt32,
                                 parameters: [UInt32] = []) -> Data {
        var body = Data()
        for param in parameters.prefix(5) { body.appendLE(param) }
        var data = Data()
        data.appendLE(UInt32(12 + body.count))
        data.appendLE(ContainerType.command.rawValue)
        data.appendLE(operation.rawValue)
        data.appendLE(transactionID)
        data.append(body)
        return data
    }

    /// Parse the response code from a PTP response container.
    static func responseCode(from container: Data) -> UInt16? {
        guard container.count >= 8 else { return nil }
        return container.readLE(UInt16.self, at: 6)
    }

    /// The transaction ID a container carries: ours in a command we built, the session's in a
    /// response the camera sent back.
    static func transactionID(from container: Data) -> UInt32? {
        guard container.count >= 12 else { return nil }
        return container.readLE(UInt32.self, at: 8)
    }

    // MARK: ObjectInfo dataset (for SendObjectInfo during RAW conversion)

    /// Build a minimal PTP **ObjectInfo** dataset for uploading a RAF: format + compressed size +
    /// filename, with the remaining fields zeroed (the camera only needs these to accept the object
    /// for conversion). Layout per PIMA-15740 §5.5.3.
    static func objectInfo(compressedSize: UInt32, filename: String) -> Data {
        var d = Data()
        d.appendLE(UInt32(0))                 // StorageID (0 = default/buffer)
        d.appendLE(rafObjectFormat)           // ObjectFormatCode (RAF)
        d.appendLE(UInt16(0))                 // ProtectionStatus
        d.appendLE(compressedSize)            // ObjectCompressedSize
        d.appendLE(UInt16(0))                 // ThumbFormat
        d.appendLE(UInt32(0))                 // ThumbCompressedSize
        d.appendLE(UInt32(0))                 // ThumbPixWidth
        d.appendLE(UInt32(0))                 // ThumbPixHeight
        d.appendLE(UInt32(0))                 // ImagePixWidth
        d.appendLE(UInt32(0))                 // ImagePixHeight
        d.appendLE(UInt32(0))                 // ImageBitDepth
        d.appendLE(UInt32(0))                 // ParentObject
        d.appendLE(UInt16(0))                 // AssociationType
        d.appendLE(UInt32(0))                 // AssociationDesc
        d.appendLE(UInt32(0))                 // SequenceNumber
        d.append(FujiEncoding.packPTPString(filename))   // Filename (PTP string)
        d.append(UInt8(0))                    // CaptureDate (empty PTP string)
        d.append(UInt8(0))                    // ModificationDate (empty PTP string)
        d.append(UInt8(0))                    // Keywords (empty PTP string)
        return d
    }

    enum InvalidDataset: LocalizedError, Equatable {
        case response
        case objectHandles
        case objectInfo

        var errorDescription: String? {
            switch self {
            case .response:
                return "The camera returned an incomplete or invalid response. Reconnect and try again."
            case .objectHandles:
                return "The camera returned an incomplete or invalid object list. No object will be selected for cleanup from this list."
            case .objectInfo:
                return "The camera returned incomplete or invalid image information. The object was retained on the camera."
            }
        }

        /// The bucket the Kitchen log and a develop's `failureReason` file this under.
        var diagnosticReason: String {
            switch self {
            case .response: return "invalid_response"
            case .objectHandles: return "invalid_object_list"
            case .objectInfo: return "invalid_object_info"
            }
        }
    }

    /// Strict response decoding for operations whose result authorizes object cleanup: a complete
    /// response container — the header, a length field that matches, at most five parameters — so
    /// a truncated or foreign buffer is never read as an OK. The trace's permissive `responseCode`
    /// remains useful for displaying even an incomplete response.
    ///
    /// The transaction ID is deliberately not compared with the command's. ImageCaptureCore shares
    /// the PTP session with its own traffic and numbers every transaction it forwards, so the ID the
    /// camera echoes is the session's, not the one in the container we handed it: a well-formed OK
    /// from a real body fails that comparison every time, and the mock is the only transport that
    /// passes it. A late delivery from a timed-out command is dropped by the transport's token
    /// before it reaches this far.
    static func validatedResponseCode(from response: Data?) throws -> UInt16 {
        guard let response, (12...32).contains(response.count), response.count % 4 == 0,
              response.readLE(UInt32.self, at: 0) == UInt32(response.count),
              response.readLE(UInt16.self, at: 4) == ContainerType.response.rawValue,
              let code = response.readLE(UInt16.self, at: 6) else {
            throw InvalidDataset.response
        }
        return code
    }

    /// Decode the complete `[u32 count][u32 handle…]` dataset. A valid zero count is empty;
    /// missing/truncated data is not. An incomplete baseline would make an existing object look new
    /// to the conversion and harvest cleanup paths. Never admit PTP's all-objects sentinel.
    static func parseObjectHandles(_ data: Data?) throws -> [UInt32] {
        guard let data, let count = data.readLE(UInt32.self, at: 0),
              data.count >= 4, (data.count - 4) % 4 == 0,
              UInt64(count) == UInt64((data.count - 4) / 4) else {
            throw InvalidDataset.objectHandles
        }
        var handles: [UInt32] = []
        var seen: Set<UInt32> = []
        for index in 0..<Int(count) {
            guard let handle = data.readLE(UInt32.self, at: 4 + index * 4),
                  handle != 0, handle != UInt32.max, seen.insert(handle).inserted else {
                throw InvalidDataset.objectHandles
            }
            handles.append(handle)
        }
        return handles
    }

    struct ObjectInfo: Equatable, Sendable {
        let objectFormat: UInt16
        let compressedSize: UInt32
        let filename: String
        /// The folder the object is in; 0 at the top of the store.
        var parentObject: UInt32 = 0
        /// Non-zero for a folder.
        var associationType: UInt16 = 0
        /// The PTP date string as the camera wrote it, "20261113T153012"; empty when it gave none.
        var captureDate: String = ""

        /// A folder rather than a file: an association, or the association object format.
        var isFolder: Bool { associationType != 0 || objectFormat == 0x3001 }
    }

    /// A PTP DateTime string, "YYYYMMDDThhmmss" with optional tenths and zone, as a date. Without a
    /// zone it is the camera's local time, taken to be `fallbackZone`.
    static func parseDateTime(_ text: String, fallbackZone: TimeZone = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 15 else { return nil }
        let core = String(trimmed.prefix(15))
        var rest = trimmed.dropFirst(15)
        if rest.first == "." { rest = rest.dropFirst().drop(while: \.isNumber) }
        var zone = fallbackZone
        if rest.first == "Z" {
            zone = TimeZone(secondsFromGMT: 0) ?? fallbackZone
        } else if let sign = rest.first, sign == "+" || sign == "-", rest.count >= 5,
                  let hours = Int(rest.dropFirst().prefix(2)), let minutes = Int(rest.dropFirst(3).prefix(2)) {
            zone = TimeZone(secondsFromGMT: (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)) ?? fallbackZone
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = zone
        return formatter.date(from: core)
    }

    /// Validate the fixed ObjectInfo header and all four length-delimited PTP strings.
    /// Truncated metadata cannot authorize downloading or deleting a candidate image.
    static func parseObjectInfo(_ data: Data?) throws -> ObjectInfo {
        guard let data, data.count >= 56,
              let format = data.readLE(UInt16.self, at: 4),
              let size = data.readLE(UInt32.self, at: 8),
              let parent = data.readLE(UInt32.self, at: 38),
              let association = data.readLE(UInt16.self, at: 42) else { throw InvalidDataset.objectInfo }
        var offset = 52
        func string() throws -> String {
            guard let count = data.readLE(UInt8.self, at: offset) else { throw InvalidDataset.objectInfo }
            offset += 1
            guard count > 0 else { return "" }
            let byteCount = Int(count) * 2
            guard offset <= data.count - byteCount,
                  data.readLE(UInt16.self, at: offset + byteCount - 2) == 0 else {
                throw InvalidDataset.objectInfo
            }
            var units: [UInt16] = []
            for index in 0..<(Int(count) - 1) {
                guard let unit = data.readLE(UInt16.self, at: offset + index * 2), unit != 0 else {
                    throw InvalidDataset.objectInfo
                }
                units.append(unit)
            }
            offset += byteCount
            return String(decoding: units, as: UTF16.self)
        }
        let filename = try string()
        let captureDate = try string()
        for _ in 0..<2 { _ = try string() }
        guard offset == data.count else { throw InvalidDataset.objectInfo }
        return ObjectInfo(objectFormat: format, compressedSize: size, filename: filename,
                          parentObject: parent, associationType: association, captureDate: captureDate)
    }
}

// MARK: - Little-endian byte helpers

extension Data {
    mutating func appendLE(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Overwrite `count`-matching bytes at `offset` with the little-endian encoding of `value`.
    /// No-op if the range would fall outside the data.
    mutating func writeLE<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= count else { return }
        let bytes = Swift.withUnsafeBytes(of: value.littleEndian) { Data($0) }
        let start = index(startIndex, offsetBy: offset)
        replaceSubrange(start..<index(start, offsetBy: size), with: bytes)
    }

    func readLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= count else { return nil }
        let sub = subdata(in: (startIndex + offset)..<(startIndex + offset + size))
        var value: T = 0
        Swift.withUnsafeMutableBytes(of: &value) { raw in
            _ = sub.copyBytes(to: raw.bindMemory(to: UInt8.self))
        }
        return T(littleEndian: value)
    }
}
