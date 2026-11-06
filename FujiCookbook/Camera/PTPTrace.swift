import Foundation

/// One PTP transaction as the transport saw it, for the compatibility report's bounded trace.
///
/// Codes are hex strings (`"0x1015"`, `"0xD192"`) rather than integers so the JSON reads without a
/// lookup table, and so two testers' reports diff cleanly in any text tool.
struct PTPTransaction: Codable, Equatable, Sendable {
    let sequence: Int
    let operation: String
    let operationName: String?
    let parameters: [String]
    let outDataLength: Int?
    /// Outgoing bytes, hex, only when small (`PTPTraceRecorder.maxOutDumpBytes`) — a slot select
    /// or a property value, never an uploaded RAF.
    let outData: String?
    let inDataLength: Int?
    /// Leading bytes of the data phase, hex, capped at `PTPTraceRecorder.maxDumpBytes`.
    let inData: String?
    let response: String?
    let responseName: String?
    /// A transport-level failure — timeout, disconnect — when no response container came back.
    let error: String?
    let durationMs: Int
}

/// Bounded, thread-safe record of PTP transactions.
///
/// Meant for the connect/probe sequence and for each push — a few hundred small property
/// transactions — never for bulk object transfer. Two caps: `maxTransactions` entries (later ones
/// are counted, not kept) and `maxDumpBytes` of data per entry. Object transfers are recorded
/// without their payload. `isRecording` lets the camera services arm it around the sequences they
/// want and disarm it after, so a long session's keepalive pings don't crowd out the transactions
/// that matter.
///
/// The connect scan is ~190 transactions on a seven-slot body and a push ~50 more per slot, so a
/// seven-slot chapter on top of the scan is ~550; 1200 leaves room for a second chapter in the
/// same session before anything is counted instead of kept.
final class PTPTraceRecorder: @unchecked Sendable {
    static let maxTransactions = 1200
    static let maxDumpBytes = 64
    static let maxOutDumpBytes = 16

    private let lock = NSLock()
    private var entries: [PTPTransaction] = []
    private var sequence = 0
    private var dropped = 0
    private var recording = true

    var isRecording: Bool {
        get { lock.withLock { recording } }
        set { lock.withLock { recording = newValue } }
    }

    func record(operation: UInt16, parameters: [UInt32], outData: Data? = nil, outDataLength: Int? = nil,
                inData: Data?, response: UInt16?, error: String?, durationMs: Int, dumpData: Bool = true) {
        lock.withLock {
            guard recording else { return }
            sequence += 1
            guard entries.count < Self.maxTransactions else { dropped += 1; return }
            entries.append(PTPTransaction(
                sequence: sequence,
                operation: PTPHex.code(operation),
                operationName: FujiPTP.operationName(operation),
                parameters: parameters.map(PTPHex.code),
                outDataLength: outDataLength ?? outData?.count,
                outData: outData.flatMap { $0.count <= Self.maxOutDumpBytes ? PTPHex.bytes($0) : nil },
                inDataLength: inData?.count,
                inData: dumpData ? inData.map { PTPHex.dump($0, limit: Self.maxDumpBytes) } : nil,
                response: response.map(PTPHex.code),
                responseName: response.flatMap(FujiPTP.responseName),
                error: error,
                durationMs: durationMs))
        }
    }

    var snapshot: [PTPTransaction] { lock.withLock { entries } }
    var droppedCount: Int { lock.withLock { dropped } }

    func reset() {
        lock.withLock { entries.removeAll(); sequence = 0; dropped = 0; recording = true }
    }

    /// Forget what has been recorded without re-arming: Clear Diagnostics mid-connection, where
    /// the camera services' own choice of whether to record has to stand.
    func discardRecorded() {
        lock.withLock { entries.removeAll(); sequence = 0; dropped = 0 }
    }
}

/// Hex spellings shared by the trace and the report: one place, one format.
enum PTPHex {
    static func code(_ value: UInt16) -> String { String(format: "0x%04X", value) }

    /// A property code the short way — `D19D`, the spelling the property tables, the docs and every
    /// tester's report use — but **only** for the Fuji vendor range that shorthand belongs to.
    ///
    /// `String(format: "D%03X", code & 0x0FFF)` alone is right for `0xD19D` and quietly wrong for
    /// anything else: it spells `0x500F` ExposureIndex as **`D00F`** — a vendor code that does not
    /// exist, masked out of one that does.
    static func propertyLabel(_ value: UInt16) -> String {
        (0xD000...0xDFFF).contains(value) ? String(format: "D%03X", value & 0x0FFF)
                                          : String(format: "0x%04X", value)
    }

    /// PTP parameters are 32-bit, but almost every one we send is a 16-bit property code — spell
    /// those the way the property tables do, and only widen when the value needs it.
    static func code(_ value: UInt32) -> String {
        value <= 0xFFFF ? String(format: "0x%04X", value) : String(format: "0x%08X", value)
    }

    /// The inverse of `code(_:)`: `"0xD19D"` back to `0xD19D`, nil when the text isn't a code.
    static func code(from text: String) -> UInt16? { UInt16(text.dropFirst(2), radix: 16) }

    /// A property map as the backups and push records store it — `["0xD192": "0400"]` — back to
    /// `[0xD192: 04 00]`. A pair that doesn't parse is dropped.
    static func propertyBytes(_ encoded: [String: String]) -> [UInt16: Data] {
        var out: [UInt16: Data] = [:]
        for (key, hex) in encoded {
            guard let code = code(from: key), let bytes = Data(hexString: hex) else { continue }
            out[code] = bytes
        }
        return out
    }

    /// Every byte, no prefix, no spaces: `"0A1B"`. Empty data is `""`.
    static func bytes(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    /// The first `limit` bytes plus a count of what was left out, so a 600-byte profile blob shows
    /// its head and its size without swamping the entry.
    static func dump(_ data: Data, limit: Int) -> String {
        guard data.count > limit else { return bytes(data) }
        return bytes(data.prefix(limit)) + "…(+\(data.count - limit) bytes)"
    }
}

extension Data {
    /// Bytes from `"0A1B"`. Nil on an odd length or a non-hex character, so a hand-edited backup
    /// fails to load rather than restoring half a value.
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
