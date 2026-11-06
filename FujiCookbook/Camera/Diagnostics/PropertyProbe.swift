import Foundation

/// One property as the camera describes it: the value it currently holds plus its
/// `GetDevicePropDesc` descriptor.
struct PropertyProbe: Identifiable, Equatable {
    let code: UInt16
    let name: String
    let value: Data?
    let descriptor: FujiPTP.PropertyDescriptor?
    let valueError: String?
    let descriptorError: String?

    var id: UInt16 { code }

    /// The value as raw bytes and as a signed 16-bit int — the two views a mismatch report needs.
    /// The name is a PTP string, so it's shown decoded instead.
    var valueSummary: String {
        guard let value else { return valueError ?? "—" }
        if code == FujiPTP.Prop.presetName {
            return FujiEncoding.parsePTPString(value).map { "“\($0)”" } ?? "—"
        }
        // The conversion profile is hundreds of bytes — one flat hex line is unreadable and
        // unpasteable. Lead with the resolved layout (the actionable part) and wrap the dump.
        if code == FujiPTP.Prop.rawConvProfile {
            return FujiRawConvProfile.layoutDescription(value) + "\n"
                + FujiRawConvProfile.hexDump(value, limit: value.count)
        }
        let hex = "0x" + PTPHex.bytes(value)
        if value.count == 2, let n = FujiEncoding.decodeInt16(value) { return "\(hex) (\(n))" }
        return hex
    }

    /// `1, 2, 3, 4, 5` / `-20…40 step 5` / `—`, per the descriptor's form. Flag-style values
    /// (Fuji's WB modes, the NR lookup) carry their hex too — decimal alone hides the pattern.
    var allowedSummary: String {
        guard let descriptor else { return descriptorError ?? "no descriptor" }
        switch descriptor.form {
        case .none: return "unconstrained"
        case .range(let min, let max, let step): return "\(min)…\(max) step \(step)"
        case .enumeration(let values): return values.map(Self.number).joined(separator: ", ")
        }
    }

    /// Small values read best in decimal; large or negative ones are almost always bit patterns.
    private static func number(_ value: Int) -> String {
        guard value < 0 || value > 99 else { return String(value) }
        // truncatingIfNeeded, not Int16(clamping:) — a descriptor read as UINT16 carries values
        // above 0x7FFF (Fuji's WB modes are 0x8001…), and clamping would print them all as 0x7FFF.
        return String(format: "%d (0x%04X)", value, UInt16(truncatingIfNeeded: value))
    }

    /// True when the camera enumerates its legal values and the value it holds isn't among them —
    /// i.e. the descriptor contradicts itself, which is worth seeing in the report.
    var currentValueIsOutOfSet: Bool {
        guard let descriptor, case .enumeration(let values) = descriptor.form,
              let value, value.count == 2, let n = FujiEncoding.decodeInt16(value) else { return false }
        return !values.contains(n)
    }
}

/// One candidate value's fate in a write probe: what the camera answered to the write, and what
/// the property read back afterwards.
struct WriteProbeEntry: Identifiable, Equatable {
    /// Position in the probe sequence — the identity, since a candidate value can repeat
    /// (1 is probed after different accepted values to expose write normalization).
    let step: Int
    let wrote: Int
    /// Nil when the write was answered OK; else the PTP failure, e.g. `0x201C Invalid DeviceProp Value`,
    /// or the transport error when `completionUnknown`.
    let writeError: String?
    let readBack: Int?
    /// The send failed without a PTP response, so whether the camera applied the value is unknown.
    var completionUnknown: Bool = false

    var id: Int { step }

    /// `ACCEPTED` / `OK, reads back N` / `rejected`, the three ways Fuji answers a write, or
    /// `outcome unknown` when the send never completed.
    /// An OK whose read-back differs may be a silent discard OR a normalization (grain Off:
    /// write 1, reads back 6/7) — the read-back value against the prior state tells which.
    var outcome: String {
        if completionUnknown { return "outcome unknown (\(writeError ?? "no valid completion"))" }
        if let writeError { return "rejected (\(writeError))" }
        if readBack == wrote { return "ACCEPTED" }
        return "OK, reads back \(readBack.map(String.init) ?? "—")"
    }
}
