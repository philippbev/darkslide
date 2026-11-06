import Foundation

/// Translates between the camera's per-slot preset properties (`0xD18E…0xD1A4`) and the app's
/// `RecipeSettings`, using `FujiEncoding`'s value encodings (see `docs/fuji-recipe-ptp-protocol.md`
/// and zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md`).
///
/// `encode` is patch-friendly: it carries through the raw bytes of fields the app doesn't edit
/// (image size/quality, color space, etc.) from the slot's own read, and omits conditional
/// properties when they must not be written — so a push never clobbers what it doesn't understand.
/// A property the slot didn't answer for is omitted for the same reason: see `Slot`.
enum FujiPresetCodec {

    typealias Props = [UInt16: Data]

    /// What the destination slot answered when it was read, immediately before a push.
    ///
    /// Two cases rather than one dictionary, because an empty dictionary is ambiguous. A Fuji body
    /// can answer `0x2001 OK` to `GetDevicePropValue` with no data phase: `readProperty` returns nil
    /// *without throwing*, so a property of an occupied slot goes missing from the read looking
    /// exactly like a property of an empty one, and a push that treats the two alike writes a
    /// hardcoded default over whatever the slot really holds — a film simulation reset to PROVIA
    /// being the worst case — with a read-back that agrees with the value it just invented. The
    /// caller has to say which of the two it means.
    enum Slot {
        /// The bytes this slot answered with. Only these are carried through: a property missing
        /// here is a property the push does not write, so the slot keeps whatever it holds.
        case holds(Props)
        /// A slot established from nothing, so `seedValues` fills what the recipe does not: the Demo
        /// Camera's synthetic banks. A hardware push always passes `.holds`.
        case empty
    }

    /// The values that establish a *new* slot entry, keyed by the property each one seeds.
    ///
    /// Written only into a `.empty` slot, and never as a stand-in for bytes the camera didn't send.
    /// Also the exact set a push reports as skipped when the base read missed them — see
    /// `SlotWriter.performSlotWrite`, which subtracts the encode set from these keys.
    ///
    /// Dynamic Range seeds **Auto**, not DR100. A recipe that names no DR has expressed no
    /// opinion, and DR100 is an opinion — always base DR, never protecting highlights — imposed on
    /// a slot the user is about to shoot with. Auto is the absence of one.
    ///
    /// Film Simulation stays PROVIA, and the asymmetry is the point: a slot must hold *some* film
    /// simulation — there is no "unset" value for it — so the seed is unavoidable, and the push says
    /// out loud that it wrote PROVIA. Dynamic Range has a real "no opinion" value, so it uses it.
    ///
    /// Every value here was measured on an X-T50; housekeeping values are body-specific. A
    /// GFX100S holds `D18E = 14` (X-T50: 7) and `D18F = 2` (seed: 4) in
    /// every one of its six banks (fw 2.13; zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#gfx100s`).
    ///
    /// Used to construct synthetic demo banks. Hardware writes must supply a readable bank;
    /// missing camera properties never establish an empty bank and never authorize these seeds.
    static let seedValues: [FujiPTP.PresetProp: Int] = [
        .imageSize: 7, .imageQuality: 4, .dynamicRange: FujiEncoding.drAutoSlotValue,
        .dRangePriority: 0, .filmSimulation: 1,
        .smoothSkin: 1, .highISONR: 0x4000, .lensModulationOptimizer: 1, .colorSpace: 1,
    ]

    /// Optional per-body exclusions for bank housekeeping properties. Live properties are
    /// excluded by the bank namespace itself, never by a body-specific exception.
    static func unwritableProperties(on model: CameraModel) -> Set<FujiPTP.PresetProp> { [] }

    // MARK: Decode (import)

    static func decode(_ props: Props, name: String?, model: CameraModel) -> DecodedProfile {
        func i(_ p: FujiPTP.PresetProp) -> Int? { props[p.rawValue].flatMap(FujiEncoding.decodeInt16) }
        func u(_ p: FujiPTP.PresetProp) -> UInt16? { props[p.rawValue].flatMap(FujiEncoding.decodeUInt16) }

        var s = RecipeSettings()

        // Every lookup below can miss on a body whose encodings differ from ours. Each miss is
        // recorded rather than coerced: the field stays unset, and the divergence carries the raw
        // value out to the log, the compatibility report and the recipe's preserved fields.
        var divergences: [DecodeDivergence] = []
        /// `value` is the *unsigned* view, because WB modes and the NR lookup are bit patterns.
        func note(_ p: FujiPTP.PresetProp, _ value: Int) {
            divergences.append(DecodeDivergence(code: p.rawValue, property: p.debugName,
                                                field: p.recipeField,
                                                value: Int(UInt16(truncatingIfNeeded: value)),
                                                kind: .unrecognized))
        }
        /// Values the app knows and a recipe cannot carry, by field display name. Kept apart from
        /// `unsupportedFields`, which means "this app could not read it" everywhere it is shown.
        var cameraOnly: [String: String] = [:]

        if let v = i(.filmSimulation) {
            s.filmSimulation = FujiEncoding.byteToFilmSim[v]
            if s.filmSimulation == nil { note(.filmSimulation, v) }
        } else if let raw = props[FujiPTP.PresetProp.filmSimulation.rawValue] {
            // Present but not two bytes. The slot counts as occupied — occupancy is D192's mere
            // presence — so the nil sim is recorded; a nil that nothing explains is the worst kind.
            note(.filmSimulation, raw.count)
        }
        if let v = i(.dynamicRange) {
            // Auto first: it's a sentinel (0xFFFF → −1), not a percentage, so it isn't in
            // `percentToDR` and would otherwise fall straight through to `note` — a slot set to DR
            // AUTO on the camera decoding as a recipe with no dynamic range at all.
            s.dynamicRange = v == FujiEncoding.drAutoSlotValue ? .auto : FujiEncoding.percentToDR[v]
            if s.dynamicRange == nil { note(.dynamicRange, v) }
        }
        // D191 D-Range Priority. Read **unsigned**, like White Balance and High ISO NR, because
        // Auto is the high-bit sentinel 0x8000 — signed it would arrive as −32768 and miss the
        // table. A value outside the table is filed as a divergence rather than decoded to Off: an
        // Off nobody chose is a confidently wrong answer, which is what `note` exists to prevent.
        if let raw = u(.dRangePriority) {
            s.dRangePriority = FujiEncoding.valueToDRangePriority[Int(raw)]
            if s.dRangePriority == nil { note(.dRangePriority, Int(raw)) }
        }
        if let v = i(.grain) {
            s.grain = FujiEncoding.flatToGrain(v)
            if s.grain == nil { note(.grain, v) }
        }
        // Failable on purpose: answering `.off` for an unknown value would be indistinguishable
        // from a body that really is set to Off.
        if let v = i(.colorChrome) {
            s.colorChromeEffect = FujiEncoding.valueToEffectIfKnown(v)
            if s.colorChromeEffect == nil { note(.colorChrome, v) }
        }
        if let v = i(.colorChromeFXBlue) {
            s.colorChromeFXBlue = FujiEncoding.valueToEffectIfKnown(v)
            if s.colorChromeFXBlue == nil { note(.colorChromeFXBlue, v) }
        }

        // Two different questions, and Sepia separates them: it is monochrome, so Color does not
        // apply (read below), and its toning is fixed, so these two do not either. Bytes in them on
        // a Sepia bank are whatever the slot last held under another simulation, and reading them
        // would invent a value the camera never let anyone set (X-T50, 2026-09-20).
        let isMono = s.filmSimulation?.isMonochrome ?? false
        if s.filmSimulation?.hasMonochromaticColor ?? false {
            if let v = i(.monochromaticWC) { s.monochromaticColorWC = Int(FujiEncoding.decodeTone(v).rounded()) }
            if let v = i(.monochromaticMG) { s.monochromaticColorMG = Int(FujiEncoding.decodeTone(v).rounded()) }
        }

        // White balance (mode read as uint16; shifts/temp as int16).
        //
        // An unlisted mode leaves `whiteBalance` nil rather than reporting Auto: every other miss
        // produces a *missing* value, which reads as "not read"; Auto would be a specific,
        // plausible, wrong one, on the field a recipe is most often judged by.
        if let wbRaw = u(.whiteBalance) {
            if let mode = FujiEncoding.valueToWBMode[Int(wbRaw)] {
                let shiftR = i(.wbShiftR) ?? 0
                let shiftB = i(.wbShiftB) ?? 0
                let ct = i(.colorTemp)
                s.whiteBalance = WhiteBalance(mode: mode, shiftRed: shiftR, shiftBlue: shiftB,
                                              kelvin: (mode == .kelvin ? (ct.flatMap { $0 > 0 ? $0 : nil }) : nil))
            } else if let label = FujiEncoding.customWhiteBalanceLabel(Int(wbRaw)) {
                // Custom 1–3: a white balance measured and stored on this camera. Known, and still
                // not a recipe value — a recipe naming it would name a measurement the destination
                // body doesn't have. The field stays unset, the slot says what it holds, and a push
                // of the imported recipe writes Auto like any recipe without a white balance.
                divergences.append(DecodeDivergence(code: FujiPTP.PresetProp.whiteBalance.rawValue,
                                                    property: FujiPTP.PresetProp.whiteBalance.debugName,
                                                    field: .whiteBalance, value: Int(wbRaw),
                                                    kind: .cameraOnly(label: label)))
                cameraOnly[RecipeField.whiteBalance.displayName] = label
            } else {
                note(.whiteBalance, Int(wbRaw))
            }
        }

        if let v = i(.highlightTone) { s.highlightTone = FujiEncoding.decodeTone(v) }
        if let v = i(.shadowTone) { s.shadowTone = FujiEncoding.decodeTone(v) }
        if !isMono, let v = i(.color) { s.color = Int(FujiEncoding.decodeTone(v).rounded()) }
        if let v = i(.sharpness) { s.sharpness = Int(FujiEncoding.decodeTone(v).rounded()) }
        if let v = i(.clarity) { s.clarity = Int(FujiEncoding.decodeTone(v).rounded()) }
        if let raw = u(.highISONR) {
            s.highISONR = FujiEncoding.nrDecode[raw]
            if s.highISONR == nil { note(.highISONR, Int(raw)) }
        }

        // The numeric fields decode from *any* two bytes, so they can never be "unrecognized" — the
        // way a divergent scale shows up is a value the model's own range says is impossible. These
        // are kept, not dropped: a tone of -50 is still the most likely reading of what the camera
        // holds, and clamping already happens on the way back out.
        divergences.append(contentsOf: outOfRangeDivergences(in: s, props: props, model: model))

        // `.unrecognized` only. Those values have nowhere in `RecipeSettings` to live, so preserving
        // them here is the only thing that keeps them — and this map already flows to the recipe's
        // "Preserved Fields" card, `.fujirecipe` export and SwiftData. An out-of-range value *is* in
        // the settings; listing it as "preserved" would be a second, contradictory account of one
        // number.
        let preserved = Dictionary(
            divergences.filter { $0.kind == .unrecognized }
                .map { ("\($0.property) (\(PTPHex.code($0.code)))", JSONValue.string($0.summary)) },
            uniquingKeysWith: { first, _ in first })

        return DecodedProfile(settings: s, name: name, unsupportedFields: preserved,
                              rawProperties: props, divergences: divergences,
                              cameraOnlyFields: cameraOnly)
    }

    /// Decoded values that fall outside what this model says is possible.
    ///
    /// Only for properties the body actually answered — a field the app left unset because the slot
    /// never returned it is not a divergence, it is an absence.
    private static func outOfRangeDivergences(in s: RecipeSettings, props: Props,
                                              model: CameraModel) -> [DecodeDivergence] {
        var out: [DecodeDivergence] = []
        func check(_ p: FujiPTP.PresetProp, _ value: Double?) {
            guard let value, let field = p.recipeField, let range = model.range(for: field),
                  let raw = props[p.rawValue].flatMap(FujiEncoding.decodeInt16),
                  value < range.min || value > range.max else { return }
            out.append(DecodeDivergence(code: p.rawValue, property: p.debugName, field: field,
                                        value: Int(UInt16(truncatingIfNeeded: raw)),
                                        kind: .outOfRange(min: range.min, max: range.max)))
        }
        check(.highlightTone, s.highlightTone)
        check(.shadowTone, s.shadowTone)
        check(.color, s.color.map(Double.init))
        check(.sharpness, s.sharpness.map(Double.init))
        check(.clarity, s.clarity.map(Double.init))
        check(.highISONR, s.highISONR.map(Double.init))
        check(.monochromaticWC, s.monochromaticColorWC.map(Double.init))
        check(.monochromaticMG, s.monochromaticColorMG.map(Double.init))
        return out
    }

    // MARK: Encode (restore) — put a slot back the way it was

    /// What a restore could not put back exactly.
    struct RestoreFidelity: Equatable {
        /// Properties whose saved bytes are not legal to write, so the restore round-tripped them
        /// through decode/encode instead. Semantically right, byte-different — and the difference
        /// has to be said out loud rather than discovered in a read-back that reports a mismatch.
        var reEncoded: [String] = []
        /// Properties in the backup that this body refuses to talk about, so nothing is written.
        var notWritable: [String] = []
        /// Inactive DR/tone bytes that differ, or could not be read, while Priority is already on.
        /// Restoring these would require a temporary Off value absent from the saved original.
        var withheldWhilePriorityActive: [String] = []
        /// Saved values the slot exposes now but the saved state hides — a colour temperature under
        /// a non-Kelvin white balance, toning under a colour simulation, Color under a monochrome
        /// one — and which differ from what the slot holds. They are written first, while the camera
        /// still accepts them, and the setting that hides them is restored after. Informational:
        /// nothing is lost, but the order is worth a line in the log and on the confirmation screen.
        var restoredWhileActive: [String] = []
        var isPerfect: Bool {
            reEncoded.isEmpty && notWritable.isEmpty && withheldWhilePriorityActive.isEmpty
        }
        /// Whether the confirmation screen has anything to say: an imperfection, or an order worth
        /// explaining.
        var hasNotes: Bool { !isPerfect || !restoredWhileActive.isEmpty }
    }

    /// Rebuild the write list from a slot's own saved bytes, respecting the priority interlock.
    ///
    /// This is deliberately **not** `encode(decode(saved))`: routing a restore through
    /// `RecipeSettings` would drop every property the recipe model doesn't carry — the housekeeping
    /// run especially — and quietly narrow a backup into a recipe. A restore's whole claim is that
    /// it puts back what was there, so it works in bytes and touches `RecipeSettings` only where it
    /// has no choice.
    ///
    /// Grain Off reads back as 6/7 (size remembered), which cannot be written directly. The X-T50
    /// and GFX100S get the demonstrated size-then-Off sequence (`exactGrainRestore`); other bodies
    /// get the semantic Off write, listed in `RestoreFidelity.reEncoded` when its bytes differ.
    ///
    /// `current` is what the slot holds *now*, if the caller has read it. `D191` D-Range Priority
    /// is refused at base ISO even when the write changes nothing — measured on an X-T50 (fw 1.32,
    /// 2026-09-17) — and it is a recipe field, so that refusal decides the outcome: replayed
    /// unconditionally, every undo at base ISO would come out "Partly written" over a bank that is
    /// already exactly right. A D191 the bank already holds is not sent; a D191 that genuinely
    /// differs still is, and if the camera refuses that one it should be reported — the undo
    /// really could not put it back.
    ///
    /// `current` also decides the order for the values the saved state hides. A push over this slot
    /// may have changed a value that is dormant in the backup — a Kelvin recipe over an Auto bank
    /// rewrites `D19C`, a toned ACROS recipe over a colour bank rewrites `D193`/`D194`, a colour
    /// recipe over an ACROS bank rewrites `D19F` — and the conditional-write rules, decided from
    /// the saved bytes, would never send it back. While the slot's current state still exposes it
    /// the write is accepted (the push proved that), so the saved value goes first and the mode
    /// that hides it after: the same idea as recovering inactive DR values before turning Priority
    /// back on. Without `current`, nothing establishes what the slot exposes and the rules stand.
    /// Measured on an X-T50 (fw 1.32, 2026-10-19): a Kelvin push over an Auto bank storing 5300 K,
    /// then Undo — `D19C` 5300 accepted first with the bank still on Kelvin, `D199` Auto after, and
    /// the final read matched all 23 original properties.
    static func encodeRestore(from saved: Props, model: CameraModel, current: Props? = nil)
        -> (writes: [(code: UInt16, bytes: Data)], fidelity: RestoreFidelity) {
        typealias P = FujiPTP.PresetProp
        var out: [(UInt16, Data)] = []
        var fidelity = RestoreFidelity()

        // The conditional write rules `encode` obeys, decided from the saved bytes rather than from
        // a `RecipeSettings`. Restoring every saved property unconditionally would send, for any
        // colour, non-Kelvin slot, three the camera is documented to refuse — mono toning on a
        // colour simulation, and a colour temperature with white balance set to anything but
        // Kelvin — and their `0x201C` would score a restore that put everything back as
        // `partiallyApplied`. Skipping them loses nothing: the slot's own values for those
        // properties are already whatever they were, and writing is the only part that fails.
        // `hasMonochromaticColor`, not `isMonochrome`: Sepia is monochrome and its toning is fixed —
        // the camera greys the control (X-T50, 2026-09-20) and refuses every write to either axis,
        // `0` included, with 0x201C (X-T50 fw 1.32, 2026-10-15), so skipping it loses nothing.
        let savedSimulation = saved[P.filmSimulation.rawValue]
            .flatMap(FujiEncoding.decodeInt16)
            .flatMap { FujiEncoding.byteToFilmSim[$0] }
        let hasToning = savedSimulation?.hasMonochromaticColor ?? false
        // Unsigned: the Fuji WB modes that matter here have the high bit set (Kelvin is 0x8007).
        let isKelvin = saved[P.whiteBalance.rawValue]
            .flatMap(FujiEncoding.decodeUInt16)
            .map { Int($0) == FujiEncoding.wbColorTempValue } ?? false

        let savedPriority = saved[P.dRangePriority.rawValue].flatMap(FujiEncoding.decodeUInt16)
        let currentPriority = current?[P.dRangePriority.rawValue].flatMap(FujiEncoding.decodeUInt16)
        let priorityWillBeOn = savedPriority.map { $0 != 0 } ?? false
        let priorityLocked: Set<P> = [.dynamicRange, .highlightTone, .shadowTone]

        // Turning Priority off must precede DR and the tones, exactly as for a recipe push.
        // Turning it on comes last, so an already-Off bank can first recover its saved inactive
        // values. If it is already On (or unreadable), do not invent a temporary Off write.
        var order = P.allCases.filter { $0 != .dRangePriority && $0 != .colorTemp }
        // Kelvin can reset the shifts on an X-S10. Restore follows the same dependency order
        // as a recipe push, including when both shifts are nonzero in the saved bank.
        if let index = order.firstIndex(of: .whiteBalance) { order.insert(.colorTemp, at: index + 1) }
        if priorityWillBeOn {
            order.append(.dRangePriority)
        } else if let index = order.firstIndex(of: .dynamicRange) {
            order.insert(.dRangePriority, at: index)
        }
        let withheld = unwritableProperties(on: model)

        // The dormant values first, while the slot's current state still accepts them. Color and
        // toning depend on the simulation, Kelvin on the white balance; everything else keeps its
        // place below, so Kelvin still precedes both shifts.
        var restoredFirst: Set<P> = []
        if let current {
            let currentSimulation = current[P.filmSimulation.rawValue]
                .flatMap(FujiEncoding.decodeInt16)
                .flatMap { FujiEncoding.byteToFilmSim[$0] }
            let currentIsKelvin = current[P.whiteBalance.rawValue]
                .flatMap(FujiEncoding.decodeUInt16)
                .map { Int($0) == FujiEncoding.wbColorTempValue } ?? false
            func restoreFirst(_ p: P) {
                guard let bytes = saved[p.rawValue], !withheld.contains(p),
                      current[p.rawValue] != bytes else { return }
                out.append((p.rawValue, bytes))
                restoredFirst.insert(p)
                fidelity.restoredWhileActive.append(p.debugName)
            }
            if let currentSimulation, let savedSimulation {
                if !currentSimulation.isMonochrome, savedSimulation.isMonochrome { restoreFirst(.color) }
                if currentSimulation.hasMonochromaticColor, !savedSimulation.hasMonochromaticColor {
                    restoreFirst(.monochromaticWC)
                    restoreFirst(.monochromaticMG)
                }
            }
            if currentIsKelvin, !isKelvin { restoreFirst(.colorTemp) }
        }

        for p in order {
            guard let bytes = saved[p.rawValue] else { continue }

            // A property this body refuses is not a fidelity problem to report — the saved bytes are
            // fine and the slot already holds them. `RestoreFidelity.notWritable` would tell the
            // user the backup was "saved in a form this app doesn't recognise", which is untrue.
            if withheld.contains(p) { continue }
            if restoredFirst.contains(p) { continue }
            // The no-op suppression `encode` applies to D191, for the same reason: a same-value write
            // is refused at base ISO and would score the restore as partial. See `current` above.
            if p == .dRangePriority, let current, current[p.rawValue] == bytes { continue }
            // X-T50 fw 1.32 refuses D19F after restoring ACROS, even when Color already equals
            // the backup (2026-10-03). Omit only that proven no-op. A different or unread value
            // still needs an attempt and an honest outcome; the final restore check compares
            // every original property, including this inactive Color value.
            if p == .color, savedSimulation?.isMonochrome == true,
               current?[p.rawValue] == bytes { continue }
            if priorityWillBeOn, currentPriority != 0, priorityLocked.contains(p) {
                if current?[p.rawValue] != bytes { fidelity.withheldWhilePriorityActive.append(p.debugName) }
                continue
            }
            if (p == .monochromaticWC || p == .monochromaticMG), !hasToning { continue }
            if p == .colorTemp, !isKelvin { continue }

            if p == .grain {
                // Round-trip through meaning, because the bytes themselves are not writable.
                guard let raw = FujiEncoding.decodeInt16(bytes),
                      let grain = FujiEncoding.flatToGrain(raw) else {
                    // A grain value our table doesn't contain: writing a guess would be worse than
                    // leaving the slot's own. This is the case a new body most plausibly hits.
                    fidelity.notWritable.append(p.debugName)
                    continue
                }
                let reEncoded = FujiEncoding.packU16(FujiEncoding.grainToFlat(grain))
                if let sequence = exactGrainRestore(raw: raw, model: model) {
                    out.append(contentsOf: sequence.map { (p.rawValue, FujiEncoding.packU16($0)) })
                } else {
                    if reEncoded != bytes { fidelity.reEncoded.append(p.debugName) }
                    out.append((p.rawValue, reEncoded))
                }
                continue
            }

            out.append((p.rawValue, bytes))
        }
        return (out, fidelity)
    }

    /// Only these bodies have demonstrated reconstruction of Off's remembered size. Other
    /// bodies retain semantic-only restoration until equivalent evidence is available.
    static func exactGrainRestore(raw: Int, model: CameraModel) -> [Int]? {
        guard ["X-T50", "GFX100S"].contains(model.id) else { return nil }
        switch raw {
        case 6: return [2, 1]
        case 7: return [5, 1]
        default: return nil
        }
    }

    /// The six fields `encode` supplies a default for when the recipe sets none: film simulation,
    /// dynamic range, grain, D-Range Priority and the two Color Chrome effects.
    static let defaultedFields: [FujiPTP.PresetProp] = [
        .filmSimulation, .dynamicRange, .grain, .dRangePriority, .colorChrome, .colorChromeFXBlue
    ]

    /// Which of those defaults `encode` will **not** write, because the bank never reported the
    /// property — `emitDefault`'s one refusal, which exists so an unanswered read is not a licence
    /// to overwrite what the app could not see.
    ///
    /// The push has to say this out loud. Every other way a recipe field can fail to reach the
    /// camera puts a row on the results screen — refused, mismatched, never attempted, not supported
    /// on this model — but a default that was never sent leaves no row at all, so the push would
    /// report "Written and verified" over a look the bank does not hold. This is the list that stops
    /// that being silent, and `DRangePriorityTests` pins it against `encode`'s own output so the two
    /// cannot drift.
    ///
    /// Only fields the recipe leaves unset can appear here: a value the recipe carries is written
    /// whatever the read did.
    static func defaultsNotWrittenForSilentRead(_ settings: RecipeSettings, model: CameraModel,
                                                slot: Slot) -> [FujiPTP.PresetProp] {
        guard case .holds(let base) = slot else { return [] }   // an empty slot is seeded, not skipped
        return defaultedFields.filter { prop in
            guard base[prop.rawValue] == nil else { return false }
            guard let field = prop.recipeField, model.supports(field) else { return false }
            switch prop {
            case .filmSimulation:     return settings.filmSimulation == nil
            case .dynamicRange:       return settings.dynamicRange == nil && (settings.dRangePriority ?? .off) == .off
            case .grain:              return settings.grain == nil
            case .dRangePriority:     return settings.dRangePriority == nil
            case .colorChrome:        return settings.colorChromeEffect == nil
            case .colorChromeFXBlue:  return settings.colorChromeFXBlue == nil
            default:                  return false
            }
        }
    }

    /// The authored toning axes a push actually attempts. Explicit zero is a real value, written
    /// wherever the body has the axis (`CameraModel.hasMagentaGreenAxis`). A body with the
    /// warm–cool axis alone — the X-T3 and X-T30, neither with the bank protocol — would still receive a
    /// nonzero MG with the compatibility warning, but not a zero.
    static func toningValuesToWrite(_ settings: RecipeSettings, model: CameraModel)
        -> (warmCool: Int?, magentaGreen: Int?) {
        guard RecipeApplicability.monochromaticColorWC(settings, on: model).applies else {
            return (nil, nil)
        }
        let mg = settings.monochromaticColorMG.flatMap { value in
            value != 0 || RecipeApplicability.monochromaticColorMG(settings, on: model).applies
                ? value : nil
        }
        return (settings.monochromaticColorWC, mg)
    }

    // MARK: Encode (push) — ordered (code, bytes) list in write order

    static func encode(_ settings: RecipeSettings, model: CameraModel, slot: Slot) -> [(code: UInt16, bytes: Data)] {
        typealias P = FujiPTP.PresetProp
        let base: Props
        let isSeeding: Bool
        switch slot {
        case .holds(let props): (base, isSeeding) = (props, false)
        case .empty: (base, isSeeding) = ([:], true)
        }
        var out: [(UInt16, Data)] = []
        // One guard, in the one funnel: `passthrough` emits through here too, so a withheld
        // property is withheld on a seeded slot as well as an occupied one.
        let withheld = unwritableProperties(on: model)
        func emit(_ p: P, _ bytes: Data) {
            guard !withheld.contains(p) else { return }
            out.append((p.rawValue, bytes))
        }
        /// Write a value the recipe never asked for, because a recipe describes a whole look and a
        /// field it leaves out would otherwise inherit the destination bank's — so one recipe
        /// produces two looks on two cameras and the push calls both "written and verified".
        ///
        /// Skipped when the slot never reported the property. An unanswered read is not a licence to
        /// overwrite what the app could not see: the bank may hold anything, the backup would not know
        /// what it replaced, and a body that went silent on one property has already shown it cannot
        /// be trusted about that one. A value the recipe *does* carry is written either way.
        func emitDefault(_ p: P, _ bytes: Data) {
            if isSeeding || base[p.rawValue] != nil { emit(p, bytes) }
        }
        /// Carry through the camera's existing bytes for fields the app doesn't edit,
        /// or seed them on a slot that has no entry yet. An occupied slot that didn't answer for the
        /// property gets **nothing** written.
        func passthrough(_ p: P) {
            if let bytes = base[p.rawValue] {
                emit(p, bytes)
            } else if isSeeding, let seed = seedValues[p] {
                emit(p, FujiEncoding.packU16(seed))
            }
        }

        let isMono = settings.filmSimulation?.isMonochrome ?? false

        // D18E/D18F: image size/quality — preserved from camera.
        passthrough(.imageSize)
        passthrough(.imageQuality)

        // D191 D-Range Priority, **written before D190 and not after it** — a deliberate break from
        // the order X RAW Studio writes in, and the only one in this sequence
        // (docs/fuji-recipe-ptp-protocol.md §"Write order"). The two are one
        // control on the camera: with D-Range Priority on, the body drives Dynamic Range and refuses
        // every write to D190. So a recipe that turns D-Range Priority off and sets a dynamic range
        // has to turn it off *first*, or its own D190 write is refused by the state it is in the
        // middle of clearing.
        //
        // Written only when it differs from what the slot holds. D191 is ISO-gated like D190 (see
        // `FujiEncoding.dRangePriorityToValue`), so at base ISO the camera refuses even a write of
        // the value already there, and as a recipe field that refusal would demote an otherwise
        // clean push to `partiallyApplied` — so the no-op is not sent.
        let slotDRP = base[P.dRangePriority.rawValue]
            .flatMap(FujiEncoding.decodeUInt16)
            .flatMap { FujiEncoding.valueToDRangePriority[Int($0)] }
        // What the slot will hold once this push lands: the recipe's priority, or Off when the
        // recipe leaves it unset — a recipe's default, like the other `defaultedFields`. A recipe
        // that holds a priority and a dynamic range keeps the priority, and D190 is skipped below.
        // When an unset priority turns a bank's priority off, `SlotWriter` says so in the push's
        // advisories; `RecipeCompatibility.analyze` deliberately does not warn in advance.
        let wantsDRP = settings.dRangePriority ?? .off
        if model.supports(.dRangePriority),
           let value = FujiEncoding.dRangePriorityToValue[wantsDRP], wantsDRP != slotDRP {
            let bytes = FujiEncoding.packU16(value)
            if settings.dRangePriority != nil { emit(.dRangePriority, bytes) }
            else { emitDefault(.dRangePriority, bytes) }
        }

        // Whether the **bank** ends up with the priority on, which is what decides the three
        // properties it drives. A body with no D-Range Priority control has nowhere to put the
        // recipe's, so nothing is driving anything and all three are written normally. Keyed off
        // `wantsDRP` alone, a recipe carrying a priority would lose its Dynamic Range and both tones
        // on every body without the control, with no advisory, because
        // `RecipeApplicability.priorityOverrides` gates the notice on this same support check.
        let priorityWillBeOn = model.supports(.dRangePriority) && wantsDRP != .off

        // D190 DynamicRange: a raw percentage, or the Auto sentinel — written, not passed through,
        // or a DR-Auto recipe would rewrite the slot's own dynamic range, verify it against itself,
        // and report "Written and verified" over whatever the slot was carrying.
        //
        // Skipped entirely when D-Range Priority will be on afterwards: the camera would refuse it,
        // and a recipe holding both is a contradiction the editor does not let anyone author.
        // The priority takes Highlight and Shadow Tone with it — see the tone block below.
        //
        // Otherwise **always written**, defaulting to Auto. A recipe is a description of a look, and
        // a field it leaves out must not mean "whatever this bank already has" — or the same recipe
        // pushed to two banks produces two looks, and the push reports "written and verified" over
        // the difference. Auto is the neutral: the camera deciding, which is what a recipe with no
        // opinion about dynamic range means.
        let writeDR = settings.dynamicRange != nil ? emit : emitDefault
        switch settings.dynamicRange ?? .auto {
        case _ where priorityWillBeOn:
            break
        case .auto:
            writeDR(.dynamicRange, FujiEncoding.packI16(FujiEncoding.drAutoSlotValue))
        case let dr where FujiEncoding.drToPercent[dr] != nil:
            writeDR(.dynamicRange, FujiEncoding.packU16(FujiEncoding.drToPercent[dr]!))
        default:
            break
        }

        // D192 FilmSimulation — always written, defaulting to PROVIA/Standard, which is what an
        // empty slot is seeded with. Passing the slot's own D192 through would let a recipe with no
        // film simulation inherit the bank's and render as a hybrid nobody authored. PROVIA is a
        // look rather than an absence, so unlike the effects below it keeps its advisory: a recipe
        // that arrives without one (an import, an AI scan) is a case where nobody chose, and
        // `RecipeCompatibility` says which way it went.
        if let sim = settings.filmSimulation {
            if model.supports(filmSimulation: sim), let byte = FujiEncoding.filmSimToByte[sim] {
                emit(.filmSimulation, FujiEncoding.packU16(byte))
            } else {
                // The body hasn't got the simulation the recipe asked for. Keep the bank's own
                // rather than substituting a second look nobody chose — `analyze` warns about it,
                // and "we couldn't do what you asked, so we did something else" is worse than
                // leaving the slot alone.
                passthrough(.filmSimulation)
            }
        } else {
            emitDefault(.filmSimulation, FujiEncoding.packU16(FujiEncoding.filmSimToByte[.provia]!))
        }

        // Explicit zero clears a previous tint; nil leaves that axis alone. Sepia and colour
        // simulations have no adjustable toning. A nonzero MG goes out even to a single-axis
        // body, with the warning.
        let toning = toningValuesToWrite(settings, model: model)
        if let wc = toning.warmCool { emit(.monochromaticWC, FujiEncoding.packI16(wc * 10)) }
        if let mg = toning.magentaGreen { emit(.monochromaticMG, FujiEncoding.packI16(mg * 10)) }

        // D195 Grain (write set 1–5, Off=1; see FujiEncoding — the READ-side bytes can be 6/7,
        // which the camera REJECTS as writes, so passing the base bytes through is not an option).
        // Written even when the recipe doesn't set it, as Off: omitting it would leave the bank's
        // own grain in place, so a clean recipe pushed over a bank set to Strong/Large comes out
        // grainy and the push calls it verified. Off is a legal *write* (1) even though the
        // read-side bytes aren't.
        if let grain = settings.grain {
            emit(.grain, FujiEncoding.packU16(FujiEncoding.grainToFlat(grain)))
        } else {
            emitDefault(.grain, FujiEncoding.packU16(
                FujiEncoding.grainToFlat(GrainEffect(strength: .off, size: .small))))
        }

        // D196/D197 Color Chrome effects (1-indexed) — gated by model support.
        if model.supports(.colorChromeEffect) {
            let bytes = FujiEncoding.packU16(FujiEncoding.effectToValue(settings.colorChromeEffect ?? .off))
            if settings.colorChromeEffect != nil { emit(.colorChrome, bytes) }
            else { emitDefault(.colorChrome, bytes) }
        }
        if model.supports(.colorChromeFXBlue) {
            let bytes = FujiEncoding.packU16(FujiEncoding.effectToValue(settings.colorChromeFXBlue ?? .off))
            if settings.colorChromeFXBlue != nil { emit(.colorChromeFXBlue, bytes) }
            else { emitDefault(.colorChromeFXBlue, bytes) }
        }

        // D198 SmoothSkin — not modeled; preserve.
        passthrough(.smoothSkin)

        // D199 WhiteBalance, then D19C ColorTemp (must follow WB), then D19A/B shifts.
        let wb = settings.whiteBalance ?? .auto
        emit(.whiteBalance, FujiEncoding.packU16(FujiEncoding.wbModeToValue[wb.mode]!))
        if wb.mode == .kelvin, let k = wb.kelvin, k > 0 {
            emit(.colorTemp, FujiEncoding.packU16(k))
        }
        emit(.wbShiftR, FujiEncoding.packI16(wb.shiftRed))
        emit(.wbShiftB, FujiEncoding.packI16(wb.shiftBlue))

        // D19D/D19E tone — skipped under an active D-Range Priority, exactly as D190 is. The
        // priority *is* a highlight-and-shadow curve, so the camera drives both and refuses every
        // write to them: measured on an X-T50 (fw 1.32, 2026-09-18) with a bank at ISO 500 and the
        // priority Strong, where a recipe setting every field had these two refused `0x201C` and
        // everything else — grain, both Color Chrome effects, white balance, Color, Sharpness,
        // High ISO NR, Clarity — written. That is the whole boundary; it is these two and D190
        // (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md#the-d-range-priority-interlock`).
        if !priorityWillBeOn {
            emit(.highlightTone, FujiEncoding.packI16(Int((((settings.highlightTone ?? 0)) * 10).rounded())))
            emit(.shadowTone, FujiEncoding.packI16(Int((((settings.shadowTone ?? 0)) * 10).rounded())))
        }

        // D19F Color — non-monochrome only.
        if !isMono {
            emit(.color, FujiEncoding.packI16((settings.color ?? 0) * 10))
        }

        // D1A0 Sharpness.
        emit(.sharpness, FujiEncoding.packI16((settings.sharpness ?? 0) * 10))

        // D1A1 High ISO NR (proprietary lookup) — preserve raw if value not in table.
        if let nr = settings.highISONR, let enc = FujiEncoding.nrEncode[nr] {
            emit(.highISONR, FujiEncoding.packU16(Int(enc)))
        } else {
            passthrough(.highISONR)
        }

        // D1A2 Clarity — gated by model support.
        if model.supports(.clarity) {
            emit(.clarity, FujiEncoding.packI16((settings.clarity ?? 0) * 10))
        }

        // D1A3/D1A4: Lens Modulation Optimizer and color space — preserved.
        passthrough(.lensModulationOptimizer)
        passthrough(.colorSpace)

        return out
    }

    /// `D190` Dynamic Range and the two tones, in the bytes they would carry if this recipe's
    /// D-Range Priority were off — which is exactly the set ``encode`` withholds while it is on.
    ///
    /// `encode` drops all three whenever the bank will end up with the priority on, because the body
    /// drives them and refuses every write to them while it is. That is right for exactly as long as
    /// the `D191` write lands. It is ISO-gated (see `SlotWriteResult.dRangePriorityRefusalHint`), so
    /// at base ISO the camera refuses it, the bank keeps whatever priority it already had, and the
    /// premise of the suppression is false. Measured on a GFX100S (fw 2.13, 2026-09-18): a recipe
    /// carrying Strong plus a dynamic range and both tones, pushed to a bank at base ISO, had `D191`
    /// refused `0x201C`; with the other three unsent, the bank held the new recipe's film
    /// simulation, grain, white balance, colour and sharpness over the **previous** recipe's dynamic
    /// range and tones — a look nobody authored.
    ///
    /// So the three are kept rather than dropped, and `performSlotWrite` sends them when, and only
    /// when, the `D191` write comes back refused. Both ways out are honest: either they land,
    /// because the bank's own priority was off and nothing was driving them, and the recipe arrives
    /// whole apart from the priority it asked for — or the camera refuses them too, because the
    /// bank's priority really is on, and they are counted and named instead of silently absent.
    ///
    /// Empty unless the recipe's priority is on *and* the model has the control, which is the same
    /// pair of conditions `encode` suppresses on. `DRangePriorityTests` asserts the two agree.
    static func dRangePriorityWithheld(_ settings: RecipeSettings, model: CameraModel,
                                       slot: Slot) -> [(code: UInt16, bytes: Data)] {
        typealias P = FujiPTP.PresetProp
        guard model.supports(.dRangePriority), (settings.dRangePriority ?? .off) != .off else { return [] }

        let base: Props
        let isSeeding: Bool
        switch slot {
        case .holds(let props): (base, isSeeding) = (props, false)
        case .empty: (base, isSeeding) = ([:], true)
        }
        let withheld = unwritableProperties(on: model)
        var out: [(UInt16, Data)] = []
        func emit(_ p: P, _ bytes: Data) {
            guard !withheld.contains(p) else { return }
            out.append((p.rawValue, bytes))
        }
        func emitDefault(_ p: P, _ bytes: Data) {
            if isSeeding || base[p.rawValue] != nil { emit(p, bytes) }
        }

        // The same expressions as `encode`'s D190 and D19D/D19E blocks with the priority taken out
        // of the condition, including the emit/emitDefault split: a slot that never answered for
        // D190 is still not written a dynamic range it never reported.
        let writeDR = settings.dynamicRange != nil ? emit : emitDefault
        switch settings.dynamicRange ?? .auto {
        case .auto:
            writeDR(.dynamicRange, FujiEncoding.packI16(FujiEncoding.drAutoSlotValue))
        case let dr where FujiEncoding.drToPercent[dr] != nil:
            writeDR(.dynamicRange, FujiEncoding.packU16(FujiEncoding.drToPercent[dr]!))
        default:
            break
        }
        emit(.highlightTone, FujiEncoding.packI16(Int((((settings.highlightTone ?? 0)) * 10).rounded())))
        emit(.shadowTone, FujiEncoding.packI16(Int((((settings.shadowTone ?? 0)) * 10).rounded())))
        return out
    }
}

extension FujiPTP.PresetProp {
    /// The user-facing recipe field this preset property belongs to, or nil for housekeeping
    /// properties (image size/quality, Lens Modulation Optimizer, color space, …) that are passed through
    /// on writes but never surfaced as recipe fields.
    var recipeField: RecipeField? {
        switch self {
        case .filmSimulation: return .filmSimulation
        case .dynamicRange: return .dynamicRange
        case .grain: return .grain
        case .colorChrome: return .colorChromeEffect
        case .colorChromeFXBlue: return .colorChromeFXBlue
        case .whiteBalance, .wbShiftR, .wbShiftB, .colorTemp: return .whiteBalance
        case .highlightTone: return .highlightTone
        case .shadowTone: return .shadowTone
        case .color: return .color
        case .sharpness: return .sharpness
        case .highISONR: return .highISONR
        case .clarity: return .clarity
        case .monochromaticWC, .monochromaticMG: return .monochromaticColor
        case .dRangePriority: return .dRangePriority
        default: return nil
        }
    }

    /// Name for the property report — the recipe field where there is one, else the housekeeping
    /// property's own name (so every row in the report is identifiable, not just the editable ones).
    var debugName: String {
        switch self {
        case .imageSize: return "Image Size"
        case .imageQuality: return "Image Quality"
        case .monochromaticWC: return "Monochromatic WC"
        case .monochromaticMG: return "Monochromatic MG"
        case .wbShiftR: return "WB Shift Red"
        case .wbShiftB: return "WB Shift Blue"
        case .colorTemp: return "Color Temp (K)"
        case .smoothSkin: return "Smooth Skin"
        case .lensModulationOptimizer: return "Lens Modulation Optimizer"
        case .colorSpace: return "Color Space"
        default: return recipeField?.displayName ?? PTPHex.code(rawValue)
        }
    }
}
