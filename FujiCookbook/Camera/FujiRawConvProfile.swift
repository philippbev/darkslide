import Foundation

/// Codec for the Fuji **`0xD185` RawConvProfile** blob — the per-conversion parameter block the
/// camera's X-Processor reads when converting an uploaded RAF to JPEG (the X RAW Studio
/// flow). This is a *different* representation from the per-slot preset properties handled by
/// `FujiPresetCodec`: here every parameter is a 4-byte field packed into one contiguous blob.
///
/// **Patch-based, never rebuilt.** Like the slot push, we read the camera's current
/// blob, overwrite only the recipe fields we understand, and leave every other byte untouched — so
/// a conversion never clobbers parameters this app version doesn't model.
///
/// ## Where the layout comes from
///
/// The field map and base offset are checked against captured `0xD185` data: the X-H1 (601 B read),
/// X-Pro3 (621 B read / 629 B host write), the development X-T50, and an owner-harvested GFX100S
/// profile (621 B read). Published profiles from an unconfirmed X100F-like body also exercise the
/// map (zgrimz/fujifilm-ptp-reference `docs/06-conversion-profile.md#layout`). These profiles share
/// a base; body-specific host padding remains a separate question.
/// Two implementation rules, with their evidence in the record's `docs/06-conversion-profile.md`:
///
/// 1. **The parameter table has a fixed absolute base, `0x1FD`.** In every capture Dynamic Range
///    sits at byte 533 and film simulation at 541, whatever the blob's length (601/621/625/629) —
///    only the *tail* is truncated on bodies with fewer features. Deriving the base from the blob's
///    tail (`count − numParams*4`) agrees for camera **reads**, because the camera's `numParams`
///    counts cells from `0x1FD`, and lands one cell late for **host writes**, because X RAW Studio
///    writes `numParams = 29` for a 30-cell blob — which is the whole of the "0x1FD vs 0x201"
///    question. `resolveLayout` therefore tries the canonical base first and keeps the tail-derived
///    value (and its neighbours) as fallbacks, all still validated semantically.
///
/// 2. **Index 11 is `whiteBalanceSource`, not Smooth Skin** (which is index 24). It is the switch that
///    decides whether the conversion uses the RAF's as-shot white balance (1) or the WB mode in
///    index 12 (2). Cells sit at `0x1FD + 4k`, i.e. ≡ 1 (mod 4), so a u32 read at a multiple of
///    four returns the next cell's low byte shifted up — as-shot reads as 256 (1 ≪ 8) and Daylight
///    as 512 (2 ≪ 8). Writing the real cells makes every WB mode and Kelvin work on any body.
enum FujiRawConvProfile {

    /// Field *indices* into the parameter table (offsets are computed from these — see `offset`).
    ///
    /// This is the record's numbering, from base `0x1FD` (zgrimz/fujifilm-ptp-reference
    /// `docs/06-conversion-profile.md#parameter-table`), with positions verified against captured
    /// profiles. A published table differs in three places, each with an entry in the record's
    /// `docs/errata.md`: it puts Exposure Bias at 4, which is Image Quality; it puts Smooth Skin at
    /// 11, which is the white balance source; and it omits cells 22, 23, 24 and 26 (Color Space,
    /// the warm–cool toning axis, Smooth Skin, the magenta–green toning axis). Numbered from base
    /// `0x201` instead, the same table starts one cell later: index *k* there is index *k+1* here,
    /// the identical byte.
    enum Field: Int, CaseIterable {
        case exposureBias      = 5   // (index 4 is ImageQuality, not Exposure Bias)
        case dynamicRange      = 6   // stored as percentage 100/200/400
        case filmSimulation    = 8   // enum byte
        case grain             = 9   // flat enum, same as D195 (see FujiEncoding)
        case colorChrome       = 10  // 1-indexed (1=Off,2=Weak,3=Strong)
        case whiteBalanceSource = 11 // 1 = use the RAF's as-shot WB, 2 = use `whiteBalance` below
        case whiteBalance      = 12  // WB mode value (0 = sentinel / as-shot)
        case wbShiftR          = 13
        case wbShiftB          = 14
        case colorTemperature  = 15  // Kelvin
        case highlightTone     = 16  // ×10 signed
        case shadowTone        = 17  // ×10 signed
        case color             = 18  // ×10 signed
        case sharpness         = 19  // ×10 signed
        case noiseReduction    = 20  // non-linear lookup
        case colorSpace        = 22
        case monochromaticColorWC = 23 // warm–cool toning, ×10, the value of `0xD193`
        case smoothSkin        = 24  // 1-indexed; cell 11, where a published table puts it, is `whiteBalanceSource`
        case colorChromeFXBlue = 25  // 1-indexed
        case monochromaticColorMG = 26 // magenta–green toning, ×10, the value of `0xD194`
        case clarity           = 27  // ×10 signed
    }

    /// Each parameter occupies 4 bytes; the table sits at a fixed offset near the end of the blob.
    static let fieldSize = 4

    /// Byte offset of field index 0 in every `0xD185` blob seen from any body, read or written.
    /// (Numbered from `0x201` instead, the table starts one cell later: index *k* there is *k+1*
    /// here.)
    static let canonicalBase = 0x1FD

    /// The host write length used by this implementation. Captured X RAW Studio writes include
    /// this length, but their appended cells are not uniformly zero; see `hostWriteForm`.
    static let hostWriteLength = 629

    // MARK: - Layout resolution

    /// Where field index 0 sits in a particular blob, once validated. Resolve this **once** per blob
    /// and thread it through `decode` / `patch` / `fieldReport`, so every access to a given blob
    /// agrees on the same base.
    struct Layout: Equatable {
        /// Byte offset of field index 0.
        let base: Int
        /// The blob's declared parameter count (header bytes [0..1], LE u16).
        let numParams: Int
    }

    static func numParams(in blob: Data) -> Int? {
        blob.readLE(UInt16.self, at: 0).map(Int.init)
    }

    /// The base implied by reading the parameter table as the blob's tail: `count − numParams*4`.
    /// Correct for camera reads (601/23, 621/28, 625/29 all give `0x1FD`), one cell late for host
    /// writes (629/29 gives `0x201`) — so it's a fallback, not the primary answer.
    static func tailBase(of blob: Data) -> Int? {
        guard let n = numParams(in: blob) else { return nil }
        return blob.count - n * fieldSize
    }

    /// The camera's own identifier for the profile dialect: a wide-char string in the header
    /// (length in byte 2, UCS-2LE from byte 3). The codes observed per body are in the record's
    /// profile table (zgrimz/fujifilm-ptp-reference `docs/06-conversion-profile.md`). Recorded in
    /// diagnostics because it's useful evidence from an unfamiliar body. These identifiers do not select a processor
    /// generation or encoding policy in the app; those relationships require separate evidence.
    static func iopCode(in blob: Data) -> String? {
        guard let count = blob.readLE(UInt8.self, at: 2), count > 0 else { return nil }
        var chars: [UInt16] = []
        for i in 0..<Int(count) {
            guard let u = blob.readLE(UInt16.self, at: 3 + i * 2) else { break }
            if u == 0 { break }
            chars.append(u)
        }
        guard !chars.isEmpty else { return nil }
        return String(utf16CodeUnits: chars, count: chars.count)
    }

    /// How plausible a candidate base looks once the blob is decoded at it.
    private struct Candidate {
        let base: Int
        let dr: Int?
        let sim: Int?
        /// Count of plausibility signals satisfied (0…5).
        let score: Int
        /// Both strong signals present — the bar for using this base at all.
        let valid: Bool

        var summary: String {
            let drText = dr.map(String.init) ?? "n/a"
            let simText = sim.flatMap { FujiEncoding.byteToFilmSim[$0]?.displayName } ?? sim.map { "?\($0)" } ?? "n/a"
            return String(format: "base 0x%X: DR=%@ sim=%@ score=%d %@",
                          base, drText, simText, score, valid ? "OK" : "rejected")
        }
    }

    /// Score one candidate base, or nil when the fields we validate against aren't addressable there.
    ///
    /// The two **strong** signals are Dynamic Range (must be exactly 100/200/400) and film
    /// simulation (must be a known enum byte). Both are dense, narrow domains sitting in adjacent
    /// cells, so a 4-byte misalignment cannot satisfy them together. The 1-indexed effect fields
    /// are weaker (1…3 is easy to hit by chance) and only break ties — `whiteBalanceSource` is
    /// deliberately not among them, since its domain is 1…2 and it would score on almost anything.
    ///
    /// Bounds are checked **per field**, not against the whole `Field` enum: shorter-table bodies
    /// (the X-H1's 601/23 read stops after ColorSpace) legitimately lack the later cells, and
    /// requiring all of them would reject those bodies outright. Fields past the end simply don't
    /// score, and `offset(of:in:layout:)` already skips them on read and write.
    private static func evaluate(_ blob: Data, base: Int) -> Candidate? {
        guard base >= 0 else { return nil }

        func cell(_ field: Field) -> Int? {
            let off = base + field.rawValue * fieldSize
            guard off >= 0, off + fieldSize <= blob.count,
                  let raw = blob.readLE(UInt32.self, at: off) else { return nil }
            return Int(Int32(bitPattern: raw))
        }
        func isEffect(_ field: Field) -> Bool {
            guard let v = cell(field) else { return false }
            return (1...3).contains(v)
        }

        let dr = cell(.dynamicRange)
        let sim = cell(.filmSimulation)
        let drOK = dr.map { FujiEncoding.percentToDR[$0] != nil } ?? false
        let simOK = sim.map { FujiEncoding.byteToFilmSim[$0] != nil } ?? false

        let score = [drOK, simOK, isEffect(.colorChrome), isEffect(.smoothSkin),
                     isEffect(.colorChromeFXBlue)].filter { $0 }.count
        return Candidate(base: base, dr: dr, sim: sim, score: score, valid: drOK && simOK)
    }

    /// Candidate bases in preference order: the canonical `0x1FD` first (the same byte in every
    /// capture from every body), then the tail-derived value and its ±1-cell neighbours — kept so a
    /// body that genuinely lays its table out somewhere else is *recovered* rather than refused.
    private static func candidateBases(_ blob: Data) -> [Int] {
        var bases = [canonicalBase]
        if let tail = tailBase(of: blob) {
            for candidate in [tail, tail + fieldSize, tail - fieldSize] where !bases.contains(candidate) {
                bases.append(candidate)
            }
        }
        return bases
    }

    /// The blob's validated layout, or nil when no candidate base decodes plausibly — in which case
    /// the caller **must** abort the conversion rather than risk misaligned field writes.
    static func resolveLayout(_ blob: Data) -> Layout? {
        guard let n = numParams(in: blob), n > 0 else { return nil }
        let scored = candidateBases(blob).compactMap { evaluate(blob, base: $0) }.filter(\.valid)
        // Highest score wins; `max(by:)` keeps the earlier (more-preferred) candidate on a tie
        // because it only replaces the incumbent on a strict improvement.
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
        return Layout(base: best.base, numParams: n)
    }

    /// Diagnostic for the mismatch error: the blob's shape, then what each candidate base decoded
    /// to. That makes the error message itself the evidence needed to characterise an unknown body,
    /// instead of a bare "doesn't match".
    static func layoutDiagnostic(_ blob: Data) -> String {
        guard let n = numParams(in: blob), let tail = tailBase(of: blob) else {
            return "\(blob.count) bytes / unreadable header"
        }
        var lines = [String(format: "%d bytes / %d params / IOPCode %@ → canonical base 0x%X, tail base 0x%X",
                            blob.count, n, iopCode(in: blob) ?? "—", canonicalBase, tail)]
        let candidates = candidateBases(blob).compactMap { evaluate(blob, base: $0) }
        if candidates.isEmpty {
            lines.append("no candidate base is addressable within \(blob.count) bytes")
        } else {
            lines.append(contentsOf: candidates.map { "  " + $0.summary })
        }
        return lines.joined(separator: "\n")
    }

    /// Short one-line shape summary (no per-candidate detail) — for the Property Report header.
    static func layoutDescription(_ blob: Data) -> String {
        guard let n = numParams(in: blob) else { return "\(blob.count) bytes / unreadable header" }
        let verdict: String
        if let resolved = resolveLayout(blob) {
            verdict = resolved.base == canonicalBase
                ? String(format: "base 0x%X, validated", resolved.base)
                : String(format: "base 0x%X, validated (canonical 0x%X rejected)", resolved.base, canonicalBase)
        } else {
            verdict = "UNVALIDATED — no candidate base decodes plausibly"
        }
        return String(format: "%d bytes / %d params / IOPCode %@ (%@)",
                      blob.count, n, iopCode(in: blob) ?? "—", verdict)
    }

    /// Byte offset of a field's 4-byte cell under `layout`, or nil if it falls outside this blob.
    static func offset(of field: Field, in blob: Data, layout: Layout) -> Int? {
        let off = layout.base + field.rawValue * fieldSize
        guard off >= 0, off + fieldSize <= blob.count else { return nil }
        return off
    }

    // MARK: Raw cell access

    private static func readI32(_ blob: Data, _ field: Field, _ layout: Layout) -> Int? {
        guard let off = offset(of: field, in: blob, layout: layout),
              let raw = blob.readLE(UInt32.self, at: off) else { return nil }
        return Int(Int32(bitPattern: raw))
    }

    private static func readU32(_ blob: Data, _ field: Field, _ layout: Layout) -> UInt32? {
        guard let off = offset(of: field, in: blob, layout: layout) else { return nil }
        return blob.readLE(UInt32.self, at: off)
    }

    private static func write(_ blob: inout Data, _ field: Field, _ value: Int, _ layout: Layout) {
        guard let off = offset(of: field, in: blob, layout: layout) else { return }
        blob.writeLE(UInt32(bitPattern: Int32(clamping: value)), at: off)
    }

    // MARK: Decode (read what a blob represents — used for previews and the round-trip check)

    /// Convenience overload that resolves the layout itself. Returns an empty `RecipeSettings` when
    /// the blob's layout can't be validated — callers that need to distinguish that case (the cook
    /// flow) resolve the layout first and check for nil.
    static func decode(_ blob: Data) -> RecipeSettings {
        guard let layout = resolveLayout(blob) else { return RecipeSettings() }
        return decode(blob, layout: layout)
    }

    /// A profile value this decoder can't name. No `unsupportedFields` to put it in — see the note
    /// at the Color Chrome reads — so the log is the whole surfacing, and it is deliberately enough:
    /// it reaches `current.log` and therefore the report a tester shares.
    private static func logUnknown(_ field: Field, _ value: Int) {
        AppLog.error(.kitchen, "Profile: \(field) holds \(value) (0x\(String(value, radix: 16, uppercase: true))), which this app doesn't recognize — the field is left unread")
    }

    static func decode(_ blob: Data, layout: Layout) -> RecipeSettings {
        var s = RecipeSettings()

        if let v = readI32(blob, .filmSimulation, layout) { s.filmSimulation = FujiEncoding.byteToFilmSim[v] }
        if let v = readI32(blob, .dynamicRange, layout) { s.dynamicRange = FujiEncoding.percentToDR[v] }
        if let v = readI32(blob, .grain, layout) { s.grain = FujiEncoding.flatToGrain(v) }
        // Same failable lookups the preset codec uses, for the same reason: answering `.off` for an
        // unknown value would be indistinguishable from a body genuinely set to Off. There is no
        // `unsupportedFields` sink on this path — the Kitchen has nowhere to surface one — so a miss
        // is logged and nothing more. The log reaches the problem report, which is enough to show
        // that a body's profile dialect differs.
        if let v = readI32(blob, .colorChrome, layout) {
            s.colorChromeEffect = FujiEncoding.valueToEffectIfKnown(v)
            if s.colorChromeEffect == nil { logUnknown(.colorChrome, v) }
        }
        if let v = readI32(blob, .colorChromeFXBlue, layout) {
            s.colorChromeFXBlue = FujiEncoding.valueToEffectIfKnown(v)
            if s.colorChromeFXBlue == nil { logUnknown(.colorChromeFXBlue, v) }
        }

        let isMono = s.filmSimulation?.isMonochrome ?? false
        // Two questions, and Sepia separates them: it is monochrome, so Color does not apply, and
        // its toning is fixed, so the two toning cells do not either. The push codec draws the
        // same line (X-T50, 2026-09-20); the two wire paths must not disagree about one recipe.
        let hasToning = s.filmSimulation?.hasMonochromaticColor ?? false

        // WB mode: field 12 carries a real mode only when field 11 (whiteBalanceSource) says the profile
        // specifies one; otherwise 12 is the as-shot sentinel 0 and the RAF's embedded WB is used.
        // The R/B fine-tune shifts are surfaced either way, so they round-trip and show in previews.
        let wbModeRaw = readI32(blob, .whiteBalance, layout) ?? 0
        // `?? .auto` stays here, unlike the preset codec's: 0 is the documented as-shot sentinel on
        // this path, not an unknown mode, and the RAF's embedded WB is what applies. Only a
        // *non-zero* value we can't name is a finding.
        let wbMode = FujiEncoding.valueToWBMode[wbModeRaw] ?? .auto
        if wbModeRaw != 0, FujiEncoding.valueToWBMode[wbModeRaw] == nil { logUnknown(.whiteBalance, wbModeRaw) }
        let shiftR = readI32(blob, .wbShiftR, layout) ?? 0
        let shiftB = readI32(blob, .wbShiftB, layout) ?? 0
        let ct = readI32(blob, .colorTemperature, layout)
        s.whiteBalance = WhiteBalance(mode: wbMode, shiftRed: shiftR, shiftBlue: shiftB,
                                      kelvin: (wbMode == .kelvin ? ct.flatMap { $0 > 0 ? $0 : nil } : nil))

        if let v = readI32(blob, .highlightTone, layout) { s.highlightTone = FujiEncoding.decodeTone(v) }
        if let v = readI32(blob, .shadowTone, layout) { s.shadowTone = FujiEncoding.decodeTone(v) }
        if !isMono, let v = readI32(blob, .color, layout) { s.color = Int(FujiEncoding.decodeTone(v).rounded()) }
        if let v = readI32(blob, .sharpness, layout) { s.sharpness = Int(FujiEncoding.decodeTone(v).rounded()) }
        if let v = readI32(blob, .clarity, layout) { s.clarity = Int(FujiEncoding.decodeTone(v).rounded()) }
        if hasToning {
            if let v = readI32(blob, .monochromaticColorWC, layout) {
                s.monochromaticColorWC = Int(FujiEncoding.decodeTone(v).rounded())
            }
            if let v = readI32(blob, .monochromaticColorMG, layout) {
                s.monochromaticColorMG = Int(FujiEncoding.decodeTone(v).rounded())
            }
        }
        if let raw = readU32(blob, .noiseReduction, layout) {
            s.highISONR = FujiEncoding.nrDecode[UInt16(truncatingIfNeeded: raw)]
        }

        return s
    }

    // MARK: Patch (apply a recipe onto the camera's current blob, preserving everything else)

    /// What a develop decided to put in the dynamic-range cell, and why.
    ///
    /// Separate from `patch` so the value written and the explanation shown can't drift: the caller
    /// reports whichever case it gets, and `patch` writes `percent`. Every case is a real outcome —
    /// there is no "we didn't get to it".
    enum DynamicRangeResolution: Equatable {
        /// The recipe named a DR the RAW can carry; it was written as asked.
        case applied(Int)
        /// The recipe named a DR higher than the file was shot at, so it was capped to the as-shot DR.
        case cappedToAsShot(recipe: Int, asShot: Int)
        /// The recipe says DR Auto, so the develop picked a DR for it — `picked`, on a frame shot at
        /// `asShot`. See `autoCeiling` for why this is not simply the as-shot value.
        case autoResolved(picked: Int, asShot: Int)
        /// The recipe sets no dynamic range at all; the cell keeps the RAF's own sentinel.
        case untouched

        /// The percentage to write, or nil to leave the cell alone.
        var percent: Int? {
            switch self {
            case .applied(let p), .autoResolved(let p, _): return p
            case .cappedToAsShot(_, let asShot): return asShot
            case .untouched: return nil
            }
        }
    }

    /// The highest DR the camera's own Auto will select. DR400 is manual-only — it needs ISO 640+ and
    /// the user to choose it — so no frame's DR400 was ever an Auto decision.
    ///
    /// **Measured, 2026-09-07**: three high-contrast frames shot with Dynamic Range set to AUTO on
    /// an X-T50 at ISO 640+ never resolved above DR200.
    ///
    /// A develop has to pick a number, and the sentinel that works on D190 does not work here.
    /// `probeConversionDynamicRange` wrote `FujiEncoding.drAutoSlotValue` (−1) into cell 6 on an
    /// X-T50 (fw 1.32): the camera *stored* it — it read back as −1 — and then developed the frame
    /// **at DR100**, not Auto and not the frame's own DR200. So −1 is not a sentinel on this
    /// surface; it is an out-of-range value the converter floors. The same probe's controls all
    /// behaved (100→DR100, 200→DR200, 400→DR400), so the negative result is trustworthy.
    ///
    /// This is what makes DR Auto resolvable at all. The tempting answer is "keep the frame's as-shot
    /// DR", and it is wrong in the case that prompted this: a frame shot at DR400 under a *different*
    /// recipe (`DynamicRangeSetting: Manual` in its EXIF) would hand that recipe's manual DR400 to a
    /// DR-Auto develop, which renders visibly flatter than the recipe's author intended. Capping at
    /// 200 reproduces what X RAW Studio writes for the same recipe on the same file — verified
    /// against a USB capture of Fuji's own converter, 2026-09-07.
    static let autoCeiling = 200

    /// Resolve the recipe's dynamic range against the DR this RAF was actually shot at.
    ///
    /// Don't force a DR *higher* than the RAF was shot at. DR400 on a DR100/200 capture greens the
    /// conversion on the X-T50 (confirmed on hardware) — there's no exposure headroom to lift,
    /// mirroring the in-camera RAW converter refusing DR400 for such a file. Lowering is safe and is
    /// what Fuji's own converter does: the same capture shows X RAW Studio writing DR200 onto this
    /// DR400 frame and getting a clean full-resolution JPEG back.
    static func resolveDynamicRange(_ settings: RecipeSettings, base: Data,
                                    layout: Layout) -> DynamicRangeResolution {
        guard let dr = settings.dynamicRange else { return .untouched }
        let asShot = readI32(base, .dynamicRange, layout)

        // DR Auto has no wire value (see `FujiEncoding.drToPercent`) — resolve it rather than skipping
        // the write, so the cell is set deliberately and can be explained.
        guard let pct = FujiEncoding.drToPercent[dr] else {
            guard let asShot else { return .untouched }
            return .autoResolved(picked: Swift.min(autoCeiling, asShot), asShot: asShot)
        }
        guard let asShot, asShot < pct else { return .applied(pct) }
        return .cappedToAsShot(recipe: pct, asShot: asShot)
    }

    /// One cell's raw stored value, uninterpreted. For diagnostics and probes only — anything that
    /// means something should decode it through `decode`.
    static func rawCell(_ blob: Data, _ field: Field, _ layout: Layout) -> Int? {
        readI32(blob, field, layout)
    }

    /// Put one raw value into one cell, bypassing every encoding rule `patch` applies.
    ///
    /// **Probes only** — the conversion-side counterpart to
    /// `CameraDiagnostics.probeWriteValues`, which maps a slot property's writable set by
    /// writing candidates and reading back. Deliberately not reachable through `patch`: a recipe
    /// value must always go through the encoder that knows what the field means, and a seam that
    /// took arbitrary integers would eventually be used as a shortcut past it.
    static func probeWriting(base: Data, layout: Layout, field: Field, rawValue: Int) -> Data {
        var blob = base
        write(&blob, field, rawValue, layout)
        return blob
    }

    /// Returns a copy of `base` with **only the fields the recipe explicitly sets** overwritten.
    /// Everything the recipe leaves `nil` keeps the base profile's bytes — which, after the RAF is
    /// uploaded, carry that photo's as-shot/EXIF sentinels, so the camera uses the RAF's own values
    /// for every parameter the recipe leaves alone
    /// (zgrimz/fujifilm-ptp-reference `docs/05-raw-conversion.md`, step 4). Writing defaults into
    /// unset fields corrupts the conversion (e.g. a global color cast). Values are assumed already
    /// clamped to the model (callers use `RecipeCompatibility`).
    ///
    /// `layout` must come from `resolveLayout(base)` — patching at an unvalidated base would shift
    /// every write by a cell.
    static func patch(base: Data, with settings: RecipeSettings, model: CameraModel, layout: Layout) -> Data {
        patchPlan(base: base, with: settings, model: model, layout: layout).profile
    }

    /// `patch`'s profile, with the fields it wrote. A field the recipe sets is listed even when its
    /// bytes already equal the as-shot profile: a later comparison version may need to reset a
    /// previous version back to exactly that value.
    static func patchPlan(base: Data, with settings: RecipeSettings, model: CameraModel, layout: Layout)
        -> (profile: Data, fields: Set<Field>) {
        var blob = base
        var fields: Set<Field> = []
        let isMono = settings.filmSimulation?.isMonochrome ?? false
        func put(_ field: Field, _ value: Int) {
            guard offset(of: field, in: blob, layout: layout) != nil else { return }
            write(&blob, field, value, layout)
            fields.insert(field)
        }

        if let sim = settings.filmSimulation, let byte = FujiEncoding.filmSimToByte[sim] {
            put(.filmSimulation, byte)
        }
        if let pct = resolveDynamicRange(settings, base: base, layout: layout).percent {
            put(.dynamicRange, pct)
        }
        if let grain = settings.grain {
            put(.grain, FujiEncoding.grainToFlat(grain))
        }
        if model.supports(.colorChromeEffect), let cc = settings.colorChromeEffect {
            put(.colorChrome, FujiEncoding.effectToValue(cc))
        }
        if model.supports(.colorChromeFXBlue), let ccb = settings.colorChromeFXBlue {
            put(.colorChromeFXBlue, FujiEncoding.effectToValue(ccb))
        }

        // White balance. Two cells, both hardware-verified: `whiteBalanceSource` (11) selects the
        // source — 1 = the RAF's as-shot WB, 2 = the mode in `whiteBalance` (12) — and 12 takes the
        // ordinary Fuji WB enum. A mode we have no wire value for (the Custom slots) leaves both
        // untouched, so the conversion falls back to the photo's own WB rather than to something
        // invented. The R/B fine-tune shifts are stored DIRECTLY (R+4 → 4, B−5 → −5; no inversion
        // or scaling) and are applied whether or not the mode is overridden, matching X RAW Studio.
        if let wb = settings.whiteBalance {
            put(.wbShiftR, wb.shiftRed)
            put(.wbShiftB, wb.shiftBlue)
            if let modeValue = FujiEncoding.wbModeToValue[wb.mode] {
                put(.whiteBalanceSource, 2)
                put(.whiteBalance, modeValue)
                if wb.mode == .kelvin, let k = wb.kelvin, k > 0 {
                    put(.colorTemperature, k)
                }
            }
        }

        if let hl = settings.highlightTone { put(.highlightTone, Int((hl * 10).rounded())) }
        if let sh = settings.shadowTone { put(.shadowTone, Int((sh * 10).rounded())) }
        if !isMono, let color = settings.color { put(.color, color * 10) }
        if let sharp = settings.sharpness { put(.sharpness, sharp * 10) }
        if model.supports(.clarity), let clarity = settings.clarity { put(.clarity, clarity * 10) }
        // The same axes a push writes, by the same rule (`FujiPresetCodec.toningValuesToWrite`), so
        // a bank and a develop never disagree about one recipe's toning. Each cell takes its bank
        // property's value unchanged, as X RAW Studio copies them.
        let toning = FujiPresetCodec.toningValuesToWrite(settings, model: model)
        if let wc = toning.warmCool { put(.monochromaticColorWC, wc * 10) }
        if let mg = toning.magentaGreen { put(.monochromaticColorMG, mg * 10) }
        if let nr = settings.highISONR, let enc = FujiEncoding.nrEncode[nr] {
            put(.noiseReduction, Int(enc))
        }

        return (blob, fields)
    }

    /// The app's host form: extend the patched profile to 629 bytes with zeros and rewrite the
    /// parameter count to the host convention. This is not established as X RAW Studio's form for
    /// every body: the PTP record has a first X-T30 write with nonzero appended cells, and the
    /// `xt5_*` capture is from an unidentified X100F-like profile. Changing the padding needs a
    /// controlled hardware comparison first.
    ///
    /// The count is one less than the table's cell count, giving 29 for a 629-byte blob. Appended
    /// cells follow the original table and never move existing fields addressed by `canonicalBase`.
    ///
    /// (The header's IOPCode length byte is left alone. X RAW Studio also bumps it by one — it
    /// counts the string's NUL — but the camera accepts writes without that, and rewriting a length
    /// prefix we don't otherwise touch is the riskier of the two options.)
    static func hostWriteForm(_ patched: Data) -> Data {
        var blob = patched
        if blob.count < hostWriteLength {
            blob.append(Data(count: hostWriteLength - blob.count))
        }
        let cells = (blob.count - canonicalBase) / fieldSize
        if cells > 1 { blob.writeLE(UInt16(clamping: cells - 1), at: 0) }
        return blob
    }

    // MARK: Write verification

    /// Fields the camera didn't take, comparing what we wrote against what it reports afterwards.
    ///
    /// Only cells the patch actually *changed* are checked — a field we left at the base value tells
    /// us nothing about whether the write landed, and including it would turn every untouched
    /// sentinel into noise. A field that isn't readable back is reported rather than assumed good.
    ///
    /// **Grain is compared by decoded meaning, never byte-for-byte.** The camera normalises Off
    /// (written as 1, read back as 6/7 — see `FujiEncoding`), so byte-comparing it would report every
    /// Off-grain recipe as a mismatch. Any other field the camera turns out to normalise should be
    /// added here rather than being allowed to fail a develop.
    static func verificationMismatches(base: Data, expected: Data, actual: Data,
                                       layout: Layout) -> [String] {
        let changed = Set(Field.allCases.filter {
            readI32(base, $0, layout) != readI32(expected, $0, layout)
        })
        return verificationMismatches(expected: expected, actual: actual, fields: changed, layout: layout)
    }

    static func verificationMismatches(expected: Data, actual: Data, fields: Set<Field>,
                                       layout: Layout) -> [String] {
        var mismatches: [String] = []
        for field in fields.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let wrote = readI32(expected, field, layout) else { continue }
            guard let read = readI32(actual, field, layout) else {
                mismatches.append("\(field): couldn't be read back")
                continue
            }
            if read == wrote { continue }
            if field == .grain, FujiEncoding.flatToGrain(wrote) == FujiEncoding.flatToGrain(read) { continue }
            mismatches.append("\(field): wrote \(wrote), camera has \(read)")
        }
        return mismatches
    }

    /// A human-readable cell-by-cell comparison of the base vs. patched profile, for diagnosing
    /// hardware color issues. Shows which D185 cells the patch changed and to what.
    ///
    /// Every cell the camera's read holds is listed, named or not: a cell the patch never touches
    /// still reaches the conversion with whatever the camera put there, and the cells this file has
    /// no name for are exactly the ones a render can't otherwise be traced to.
    static func fieldReport(base: Data, patched: Data, settings: RecipeSettings, layout: Layout) -> String {
        var lines: [String] = []
        lines.append(String(format: "D185 length=%d  numParams=%d  base=0x%X  IOPCode=%@",
                            base.count, layout.numParams, layout.base, iopCode(in: base) ?? "—"))
        if let wb = settings.whiteBalance {
            lines.append("recipe WB: mode=\(wb.mode.rawValue) shiftR=\(wb.shiftRed) shiftB=\(wb.shiftBlue) K=\(wb.kelvin.map(String.init) ?? "-")")
        } else {
            lines.append("recipe WB: (not set — base preserved)")
        }
        let cellCount = Swift.max(0, (base.count - layout.base) / fieldSize)
        for index in 0..<cellCount {
            let b = readCell(base, index, layout)
            let p = readCell(patched, index, layout)
            let mark = (b != p) ? "  <- changed" : ""
            let name = Field(rawValue: index).map { String(describing: $0) } ?? "unnamed"
            lines.append(String(format: "[%2d] %-19@ base=%@  patched=%@%@",
                                index, name,
                                b.map(String.init) ?? "n/a", p.map(String.init) ?? "n/a", mark))
        }
        return lines.joined(separator: "\n")
    }

    /// Cell `index` as a signed value, by position alone — `fieldReport`'s way to show cells `Field`
    /// has no case for.
    private static func readCell(_ blob: Data, _ index: Int, _ layout: Layout) -> Int? {
        let off = layout.base + index * fieldSize
        guard off >= 0, off + fieldSize <= blob.count,
              let raw = blob.readLE(UInt32.self, at: off) else { return nil }
        return Int(Int32(bitPattern: raw))
    }

    /// First `limit` bytes as wrapped hex — the raw evidence to attach when a layout is rejected.
    static func hexDump(_ blob: Data, limit: Int = 64, bytesPerLine: Int = 16) -> String {
        let slice = blob.prefix(limit)
        return stride(from: 0, to: slice.count, by: bytesPerLine).map { start in
            let end = Swift.min(start + bytesPerLine, slice.count)
            let row = slice[slice.startIndex.advanced(by: start)..<slice.startIndex.advanced(by: end)]
            return String(format: "%04X  ", start) + PTPHex.bytes(row)
        }.joined(separator: "\n")
    }

    // MARK: Demo helpers

    /// A synthetic, correctly-sized base blob for the in-app Demo Camera so the Kitchen flow can run
    /// the *real* `patch`/`decode` path with no hardware (mirrors how the slot demo exercises the
    /// real preset codec). Uses the X-T50's hardware-verified 625-byte / 29-param shape and its
    /// IOPCode (zgrimz/fujifilm-ptp-reference `docs/06-conversion-profile.md`) — the demo must match
    /// real hardware, or a layout regression stays invisible in the simulator.
    static func demoBaseProfile() -> Data { demoProfile(cells: 29, iopCode: "FF189504") }

    /// A **short-table** demo blob matching the X-H1's 601-byte / 23-param capture, whose table stops
    /// after ColorSpace (no Smooth Skin, Color Chrome FX Blue, Monochromatic Color, or Clarity). The
    /// truncated shape is otherwise only reachable on hardware we don't have, and it is the case the
    /// per-field bounds checks in `evaluate`/`offset` exist for.
    static func demoShortBaseProfile() -> Data { demoProfile(cells: 23, iopCode: "FF129506") }

    /// The **GFX** shape: the GFX100S's harvested 621-byte / 28-param profile (2026-09-17, fw 2.13),
    /// which is also the X-Pro3's capture shape. 28 cells is the first table that holds every field
    /// this enum knows — Clarity is index 27, the last cell — so it is the one shape where nothing
    /// is out of bounds and nothing is spare. The registry opens the GFX100S's Kitchen on this layout
    /// resolving, and `demoBaseProfile`'s 625/29 is not what that body produces.
    static func demoGFXBaseProfile() -> Data { demoProfile(cells: 28, iopCode: "FF149502") }

    /// Build a demo blob with `cells` parameter cells at `canonicalBase`, seeded with neutral values
    /// so a freshly-read demo profile decodes sensibly — and so `resolveLayout`'s plausibility check
    /// has real values to validate against.
    private static func demoProfile(cells: Int, iopCode: String) -> Data {
        var blob = Data(count: canonicalBase + cells * fieldSize)
        blob.writeLE(UInt16(clamping: cells), at: 0)
        blob.writeLE(UInt8(clamping: iopCode.utf16.count), at: 2)
        for (i, unit) in iopCode.utf16.enumerated() { blob.writeLE(unit, at: 3 + i * 2) }

        let layout = Layout(base: canonicalBase, numParams: cells)
        write(&blob, .filmSimulation, FujiEncoding.filmSimToByte[.provia]!, layout)
        write(&blob, .dynamicRange, 100, layout)
        write(&blob, .grain, FujiEncoding.grainToFlat(.off), layout)
        write(&blob, .colorChrome, FujiEncoding.effectToValue(.off), layout)
        write(&blob, .smoothSkin, FujiEncoding.effectToValue(.off), layout)
        write(&blob, .colorChromeFXBlue, FujiEncoding.effectToValue(.off), layout)
        // As-shot white balance, exactly as a camera-produced profile reports it before a patch.
        write(&blob, .whiteBalanceSource, 1, layout)
        write(&blob, .whiteBalance, 0, layout)
        write(&blob, .colorSpace, 1, layout)
        write(&blob, .noiseReduction, Int(FujiEncoding.nrEncode[0]!), layout)
        return blob
    }
}
