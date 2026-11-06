import Foundation

/// Value encodings for the Fuji preset properties, as recorded in
/// zgrimz/fujifilm-ptp-reference `docs/03-encodings.md`, which tags each one with the bodies it has
/// been verified on. See `docs/fuji-recipe-ptp-protocol.md`. Per-model re-verification is still
/// required for older generations.
enum FujiEncoding {

    // MARK: Film simulation  (preset property byte ⇄ app enum)

    static let filmSimToByte: [FilmSimulation: Int] = [
        .provia: 0x01, .velvia: 0x02, .astia: 0x03, .proNegHi: 0x04, .proNegStd: 0x05,
        .monochrome: 0x06, .monochromeYe: 0x07, .monochromeR: 0x08, .monochromeG: 0x09,
        .sepia: 0x0A, .classicChrome: 0x0B, .acros: 0x0C, .acrosYe: 0x0D, .acrosR: 0x0E,
        .acrosG: 0x0F, .eterna: 0x10, .classicNeg: 0x11, .eternaBleachBypass: 0x12,
        .nostalgicNeg: 0x13, .realaAce: 0x14
    ]
    static let byteToFilmSim: [Int: FilmSimulation] =
        Dictionary(uniqueKeysWithValues: filmSimToByte.map { ($1, $0) })

    // MARK: White balance mode

    static let wbModeToValue: [WhiteBalanceMode: Int] = [
        .auto: 0x0002, .daylight: 0x0004, .incandescent: 0x0006, .underwater: 0x0008,
        .fluorescent1: 0x8001, .fluorescent2: 0x8002, .fluorescent3: 0x8003,
        .shade: 0x8006, .kelvin: 0x8007,
        // The two AWB priority variants sit adjacent in Fuji's enum. Ambience (0x8021) is
        // published for the X100VI; White Priority (0x8020) was set by hand on an X-T50 and read
        // back (fw 1.32, 2026-10-15), and both are published for the X-H2 and GFX100RF
        // (zgrimz/fujifilm-ptp-reference `docs/03-encodings.md#0xd199-white-balance-mode`).
        .autoWhitePriority: 0x8020, .autoAmbiencePriority: 0x8021
    ]
    static let valueToWBMode: [Int: WhiteBalanceMode] =
        Dictionary(uniqueKeysWithValues: wbModeToValue.map { ($1, $0) })

    /// The Fuji "ColorTemp" WB value — Kelvin (D19C) is only writable in this mode.
    static let wbColorTempValue = 0x8007

    /// Custom white balance 1–3, `0x8008`–`0x800A`: a white balance the user measured and stored
    /// on that camera. Recognised when a bank is read, so the slot can say what it holds, and never
    /// a recipe value — a recipe naming it would be naming a measurement the destination body
    /// doesn't have (see `DecodeDivergence.Kind.cameraOnly`). Custom 1 was set by hand on an X-T50
    /// and read back as `0x8008` (fw 1.32, 2026-10-15); all three are published for the X-H2.
    static func customWhiteBalanceLabel(_ raw: Int) -> String? {
        switch raw {
        case 0x8008: return "Custom 1"
        case 0x8009: return "Custom 2"
        case 0x800A: return "Custom 3"
        default: return nil
        }
    }

    // MARK: Dynamic range  (preset stores raw percentage)

    /// `.auto` has no percentage, because DR Auto isn't one — it's the camera deciding at capture
    /// from the scene and the ISO. That is all this table's missing entry means. It does **not**
    /// mean Auto is unrepresentable on the wire: D190 has a value for it (`drAutoSlotValue`).
    ///
    /// The absence is still load-bearing, so read every `drToPercent[dr]` lookup as "is this a DR
    /// expressible as a percentage" — never as a guard around the whole write. A DR-Auto recipe
    /// writes `drAutoSlotValue`; skipping the write would hand the recipe whatever the destination
    /// already holds, the slot's previous DR on a push or the RAF's as-shot DR on a develop, with
    /// nothing said (docs/fuji-recipe-ptp-protocol.md §"Value encodings" and §"What read-back
    /// verification cannot catch").
    static let drToPercent: [DynamicRange: Int] = [.dr100: 100, .dr200: 200, .dr400: 400]
    static let percentToDR: [Int: DynamicRange] =
        Dictionary(uniqueKeysWithValues: drToPercent.map { ($1, $0) })

    // **D190 is gated by the slot's own ISO.** Fujifilm makes DR200 available only at 2× base ISO
    // and DR400 only at 4×; below that the camera answers `0x201C Invalid DeviceProp Value` to the
    // write.
    //
    // **That it is the *slot's* ISO rather than the camera's comes from the GFX100S**, not from the
    // X-T50: three banks in one session, one live ISO, `0xD190 = 400` accepted on C2 and refused
    // `0x201C` on C3 and C4. A live-ISO gate would have answered all three the same way. (The three
    // banks matched in all 23 readable bank properties; the ISO is not among them, so they could
    // still differ in it.)
    //
    // The X-T50 run is what pins the *thresholds*, and it cannot separate the two readings: the body
    // sat on the bank whose ISO was being changed, so bank and live moved together. At ISO 125,
    // DR100 and Auto were accepted while DR200 and DR400 were refused; at ISO 500 all four were
    // accepted (fw 1.32, base ISO 125, D-Range Priority off, 2026-09-17).
    //
    // The app cannot predict it: the ISO is not among the 23 bank properties, so a refusal is the
    // only way it finds out. That is why it is reported rather than pre-empted, and why
    // `CameraDiagnostics.dynamicRangeProbeCandidates` exists.
    //
    // `0x500F` ExposureIndex, the standard PTP property for ISO, would make it predictable if it
    // tracked the selected bank: one read after the slot select. **It doesn't answer at all on an
    // X-T50**: `0x200A DeviceProp Not Supported`, on banks at ISO 500 and ISO 125 alike (fw 1.32,
    // 2026-09-18), so the gate is invisible on that body. Still open for the GFX100S, which
    // advertises the property; the sweep reads it either way, because a recorded `0x200A` is the
    // finding.
    //
    // The other gate is `dRangePriorityToValue` below — with D-Range Priority on, the camera drives
    // Dynamic Range and refuses every write to D190.

    // MARK: D-Range Priority  (D191)

    /// **D191 is D-Range Priority.** Measured on an X-T50 (fw 1.32, 2026-09-17) by reading slot C1
    /// four times and changing only the camera's D RANGE PRIORITY menu item between reads — every
    /// other property in the slot came back byte-identical each time.
    ///
    /// `Auto` is `0x8000` rather than an in-sequence 3: Fuji's high-bit-means-special convention,
    /// the same one behind White Balance (`0x8001`–`0x8007`, `0x8020`) and High ISO NR (`0x8000`).
    /// So write this with `packU16` and read it with `decodeUInt16` — `packI16` clamps `0x8000` down
    /// to `0x7FFF` and would send Weak's neighbour instead.
    ///
    /// Off/Weak/Strong = 0/1/2 matches a published conversion-profile table
    /// (zgrimz/fujifilm-ptp-reference `docs/06-conversion-profile.md#d-range-priority-cell-7--unknown`)
    /// and this app's own EXIF decoder (`FujiMakerNote.dRangePriorityFixedStrengths`, tag `0x1445` →
    /// `1: .weak, 2: .strong`). Read both as weak support, not as measurements. That table is for
    /// **D185 cell 7**, a
    /// different surface — and this codebase already has the case where the two diverge on exactly
    /// this kind of value: `D190` holds `0xFFFF` for DR Auto while cell 6 has no Auto sentinel at
    /// all. The EXIF agreement is thinner still: with Off and Auto on a separate tag, Weak-before-
    /// Strong is the only ordering anyone would pick, so it is a falsification test that passed
    /// rather than a second reading. The measurement is the four slot reads above, and that is
    /// enough on its own.
    ///
    /// Like D190, this property is gated by the slot's ISO — at base ISO the camera refuses every
    /// write to it, including a write of the value it already holds. That is why the codec writes it
    /// only when it differs from what the slot has.
    static let dRangePriorityToValue: [DRangePriority: Int] = [
        .off: 0x0000, .weak: 0x0001, .strong: 0x0002, .auto: 0x8000
    ]
    static let valueToDRangePriority: [Int: DRangePriority] =
        Dictionary(uniqueKeysWithValues: dRangePriorityToValue.map { ($1, $0) })

    /// What **D190** holds for DR Auto: `0xFFFF`, read back as −1 through `decodeInt16`.
    ///
    /// Measured on an X-T50 (fw 1.32, 2026-09-07) by setting slot C1's Dynamic Range to AUTO in the
    /// camera's IQ menu and reading the property — the only way to establish a value set on this
    /// body, which refuses `GetDevicePropDesc` for every preset property. Every other value in that
    /// report matched C1's recipe; DR was the single thing changed.
    ///
    /// Note this is a *sentinel*, not a percentage — keep it out of `drToPercent`/`percentToDR`, or
    /// −1 starts round-tripping as a dynamic range of −1%.
    ///
    /// The `0xD185` conversion profile is a separate surface and does **not** get this value: its
    /// cell 6 has only ever been observed holding 100/200/400, in captures from four bodies plus
    /// X RAW Studio's own writes. See `FujiRawConvProfile.autoCeiling`.
    static let drAutoSlotValue = -1

    // MARK: Grain  (flat enum with ASYMMETRIC read/write sets — X-T50 hardware-verified)
    //
    // Established on the X-T50 by a menu sweep + the D195 write probe (2026-08-01, docs
    // `fuji-recipe-ptp-protocol.md`):
    //   WRITE set (what SetDevicePropValue accepts): 1=Off, 2=WeakSmall, 3=StrongSmall,
    //     4=WeakLarge, 5=StrongLarge — the published write set too (zgrimz/fujifilm-ptp-reference
    //     `docs/03-encodings.md#0xd195-grain-effect`). 0 and 6–8 are rejected (0x201C).
    //   READ set (what the property reports): 2–5 as above, but Off reads as **6 (size Small
    //     remembered) or 7 (size Large remembered)** — the camera normalizes a write of 1 into
    //     6/7, keeping the size the slot last had. Fuji menus remember grain size while Off.
    // So writes use 1 for Off, decode accepts 1/6/7 as Off, and read-back verification must
    // compare grain SEMANTICALLY (both sides decoded), never byte-for-byte: a written 1 reads back
    // as 6 or 7, and a byte comparison would call a correct Off write unverified.
    //
    // NOTE: the 0x0000/0x0002/0x0102 "packed" grain values in some published tables are a UI
    // representation, NOT a wire encoding (zgrimz/fujifilm-ptp-reference `docs/errata.md`). Don't
    // write those to D195.

    static func grainToFlat(_ g: GrainEffect) -> Int {
        switch (g.strength, g.size ?? .small) {
        case (.off, _): return 1
        case (.weak, .small): return 2
        case (.strong, .small): return 3
        case (.weak, .large): return 4
        case (.strong, .large): return 5
        }
    }
    /// Nil for values outside the verified set, so an unknown encoding surfaces as "grain not read"
    /// instead of silently decoding as Off.
    static func flatToGrain(_ v: Int) -> GrainEffect? {
        switch v {
        case 1, 6, 7: return .off   // 1 = write-side Off; 6/7 = read-side Off (Small/Large remembered)
        case 2: return GrainEffect(strength: .weak, size: .small)
        case 3: return GrainEffect(strength: .strong, size: .small)
        case 4: return GrainEffect(strength: .weak, size: .large)
        case 5: return GrainEffect(strength: .strong, size: .large)
        default: return nil
        }
    }

    // MARK: Three-level effects  (preset is 1-indexed: 1=Off 2=Weak 3=Strong)

    static func effectToValue(_ e: EffectStrength) -> Int {
        switch e { case .off: return 1; case .weak: return 2; case .strong: return 3 }
    }
    /// Nil outside the verified 1/2/3 set, so an unrecognized strength surfaces as "not read"
    /// rather than as Off — the posture `flatToGrain` already takes, for the same reason. On a body
    /// nobody has tested, a fourth value is a finding; mapping it to Off would hide it.
    static func valueToEffectIfKnown(_ v: Int) -> EffectStrength? {
        switch v { case 1: return .off; case 2: return .weak; case 3: return .strong; default: return nil }
    }

    // MARK: High ISO NR  (proprietary non-linear lookup)

    static let nrEncode: [Int: UInt16] = [
        -4: 0x8000, -3: 0x7000, -2: 0x4000, -1: 0x3000,
         0: 0x2000,  1: 0x1000,  2: 0x0000,  3: 0x6000, 4: 0x5000
    ]
    static let nrDecode: [UInt16: Int] =
        Dictionary(uniqueKeysWithValues: nrEncode.map { ($1, $0) })

    // MARK: Tone (×10 signed, 0x8000 / -32768 = sentinel → 0)

    static let toneSentinel = -32768
    static func decodeTone(_ raw: Int) -> Double { raw == toneSentinel ? 0 : Double(raw) / 10 }
}

// MARK: - 2-byte value packing + PTP string

extension FujiEncoding {
    /// Pack a value as little-endian uint16 (the data phase of SetDevicePropValue for most fields).
    static func packU16(_ value: Int) -> Data {
        var d = Data(); d.appendLE(UInt16(truncatingIfNeeded: value)); return d
    }
    /// Pack a signed value as little-endian int16.
    static func packI16(_ value: Int) -> Data {
        var d = Data(); d.appendLE(UInt16(bitPattern: Int16(clamping: value))); return d
    }
    /// Decode a 2-byte property value as signed int16 LE. Not every property reads signed; which do
    /// is in zgrimz/fujifilm-ptp-reference `docs/03-encodings.md`, "Read signed or unsigned?".
    static func decodeInt16(_ data: Data) -> Int? {
        guard let raw = data.readLE(UInt16.self, at: 0) else { return nil }
        return Int(Int16(bitPattern: raw))
    }
    /// The unsigned 16-bit view (used for WB mode, D-Range Priority and the NR lookup).
    static func decodeUInt16(_ data: Data) -> UInt16? { data.readLE(UInt16.self, at: 0) }

    /// Pack a PTP wide string: 1 byte length (chars incl. null), then UCS-2LE incl. trailing null.
    ///
    /// Framing confirmed on an X-T50 (2026-09-07): a 25-character slot name containing
    /// quotes, a backslash and a backtick was written to `0xD18D`, shown correctly on the camera's
    /// own menu, and read back through `parsePTPString` identical. A wrong length byte or byte
    /// order would have truncated or garbled that, so this exercises both directions at the
    /// boundary. Still only the one body — other models share the code, not the evidence.
    ///
    /// An empty string packs as `01 00 00`, a count of one and the NUL: the bytes an unnamed X-T50
    /// bank answers for `0xD18D`, so writing a bank's empty name puts back what the camera gave.
    /// Over direct USB an X-T50 (fw 1.32, 2026-10-19) takes this form and the standard one-byte
    /// empty string `00` alike. Through ImageCaptureCore on iOS 27.0.1 the one-byte form was
    /// answered OK and left the old name (zgrimz/fujifilm-ptp-reference `docs/03-encodings.md`).
    /// `parsePTPString` reads both forms as "". DeviceInfo strings keep PIMA's one-byte empty
    /// form, which the DeviceInfo encoder writes itself.
    ///
    /// The count is one byte and includes the NUL, so a string longer than 254 UTF-16 units is cut
    /// to its first 254 rather than sent with a count that disagrees with its characters. A push's
    /// name read-back then reports the cut name as a mismatch.
    static func packPTPString(_ value: String) -> Data {
        let scalars = Array(value.utf16.prefix(Int(UInt8.max) - 1))
        var d = Data()
        d.append(UInt8(scalars.count + 1))   // +1 for null terminator
        for u in scalars { d.appendLE(u) }
        d.appendLE(UInt16(0))                            // null terminator
        return d
    }
    static func parsePTPString(_ data: Data) -> String? {
        guard let count = data.first, count >= 1 else { return data.isEmpty ? nil : "" }
        var chars: [UInt16] = []
        var offset = 1
        for _ in 0..<(Int(count)) {
            guard let u = data.readLE(UInt16.self, at: offset) else { break }
            if u == 0 { break }
            chars.append(u)
            offset += 2
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}
