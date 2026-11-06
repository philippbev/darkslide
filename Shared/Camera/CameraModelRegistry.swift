import Foundation

/// The camera models the app knows: what each body's menus offer, so a recipe can be encoded and
/// judged for it, and how firmly its writes have been confirmed. Not the write gate: that is
/// `WriteDecision`, from an entry's state and what the body answers at connect.
///
/// Each entry declares which recipe fields exist, their ranges, slot count, and slot-naming
/// support, and what is recorded about its bank path (`WriteSupport`). An entry is `.readWrite`
/// when its slot protocol is verified on hardware, by an owner's report or a published or
/// community report, or when it shares its processor with such a body, and `WriteDecision` grants
/// it on that word. It is `.untested` when nothing recorded settles its bank path either way, and
/// the connect's slot read decides. It is `.blocked` when a recorded failure stands against it —
/// firmware that doesn't expose the bank path, or a published test that found it failing — and
/// then also carries `supportsSlotProtocol: false`: the app never sends it a `0xD18C` write and
/// explains the body instead of reporting a refusal. Every write is read back before it is
/// trusted.
///
/// RAW conversion is a separate capability, not tied to write support: it produces a temporary
/// object the app deletes and changes nothing on the camera, and the 0xD185 wire format is shared
/// across processor generations (zgrimz/fujifilm-ptp-reference `docs/06-conversion-profile.md#layout`), so it
/// is enabled wherever the body is known to expose it. `FujiRawConvProfile.resolveLayout` is the
/// real guard — an unrecognised profile aborts the conversion before anything is written. The
/// bundled "Demo Camera" is `.readWrite` because its transport round-trips the app's own encoding,
/// so push can be exercised end-to-end in the Simulator with no hardware.
///
/// Each entry's comment says what its fields, film list and ranges rest on. Where that is specs
/// rather than a manual or a hardware report, it says `VERIFY`.
final class CameraModelRegistry {
    static let shared = CameraModelRegistry()

    let models: [CameraModel]
    private let byID: [String: CameraModel]

    private init() {
        let models = CameraModelRegistry.buildModels()
        self.models = models
        self.byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
    }

    func model(withID id: String) -> CameraModel? { byID[id] }

    /// Resolve a camera's reported product name to a registry entry, with a confidence.
    ///
    /// Exact first (normalized id equality), then the alias table, then a **word-boundary** search
    /// for the longest id the name contains. The boundary matters because "X-T30 II" is a prefix
    /// of "X-T30 III": an id only counts when what follows it is a space, punctuation or the end —
    /// so "X-T5 TETHER" still guesses X-T5, and "X-T30 III" guesses nothing.
    func identify(productName name: String) -> ModelIdentification {
        Self.identify(name, in: models, aliases: Self.aliases)
    }

    /// The model regardless of confidence — for read-only consumers (a photo's EXIF, a picker
    /// default) that only want a best guess at which body a recipe was authored for. Anything that
    /// decides what may be *written* goes through `identify`.
    func model(matchingProductName name: String) -> CameraModel? {
        identify(productName: name).model
    }

    /// Known spellings of a body's name that differ from its registry id, normalized → id. Empty
    /// until a tester's report shows a body naming itself differently from what the registry
    /// expects; the spaceless forms (`X-T30II`) are derived automatically and don't belong here.
    static let aliases: [String: String] = [:]

    static func identify(_ name: String, in models: [CameraModel], aliases: [String: String]) -> ModelIdentification {
        let normalized = normalize(name)
        guard !normalized.isEmpty else { return .unknown }
        if let exact = models.first(where: { normalize($0.id) == normalized }) { return .exact(exact) }
        if let id = aliases[normalized], let model = models.first(where: { $0.id == id }) {
            return .alias(model, alias: name)
        }
        // A spaceless spelling of an id ("X-T30II") is an alias the registry can derive itself.
        let spaceless = normalized.replacingOccurrences(of: " ", with: "")
        if let model = models.first(where: { normalize($0.id).replacingOccurrences(of: " ", with: "") == spaceless && normalize($0.id) != normalized }) {
            return .alias(model, alias: name)
        }
        let contained = models.filter { containsAtWordBoundary(normalized, normalize($0.id)) }
        if let longest = contained.max(by: { $0.id.count < $1.id.count }) {
            return .heuristic(longest, matched: longest.id)
        }
        return .unknown
    }

    /// Tokens Fujifilm appends to a name to mean *a newer body*: "X-T30 II", "X-T30 III". An id
    /// followed by one of these is not that id with a suffix, it is a different camera: "X-T30 III"
    /// is not "X-T30 II" plus noise.
    private static let generationSuffixes: Set<String> = ["II", "III", "IV", "V", "VI", "VII"]

    /// Uppercase, the make stripped, whitespace collapsed to single spaces. Hyphens are kept, so
    /// "X-T30 III" and "X-T30 II" stay distinguishable.
    static func normalize(_ name: String) -> String {
        name.uppercased()
            .replacingOccurrences(of: "FUJIFILM", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// `needle` occurs in `haystack` with a non-alphanumeric (or edge) on both sides.
    private static func containsAtWordBoundary(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var from = haystack.startIndex
        while from < haystack.endIndex, let range = haystack.range(of: needle, range: from..<haystack.endIndex) {
            let before = range.lowerBound == haystack.startIndex ? nil : haystack[haystack.index(before: range.lowerBound)]
            let after = range.upperBound == haystack.endIndex ? nil : haystack[range.upperBound]
            let isBoundary: (Character?) -> Bool = { c in c.map { !$0.isLetter && !$0.isNumber } ?? true }
            if isBoundary(before) && isBoundary(after) {
                // "X-T30 III" contains "X-T30" at a clean boundary and still isn't one.
                let rest = haystack[range.upperBound...].split(whereSeparator: \.isWhitespace)
                let nextToken = rest.first.map(String.init) ?? ""
                if !generationSuffixes.contains(nextToken) { return true }
            }
            from = haystack.index(after: range.lowerBound)
        }
        return false
    }

    /// The synthetic model used by the demo/mock transport.
    var demoModel: CameraModel {
        // `buildModels` always appends the demo entry, so the lookup can't fail.
        byID[CameraModelRegistry.demoModelID]!
    }

    static let demoModelID = "DEMO"

    /// The id of a provisional model (`provisionalModel(productName:)`). A placeholder, and never
    /// persisted or compared: `ModelIdentification.registryModel` is nil for an unlisted body, so two
    /// different unlisted cameras can't be taken for one another by it.
    static let unlistedModelID = "UNLISTED"

    /// Field knowledge for a body no entry matches: the newest generation's, so the codec has a film
    /// list, ranges and white-balance modes to encode with. A body with fewer fields refuses the
    /// writes for the ones it lacks, and the push reports each refusal by name. Nothing here is
    /// inferred from what the walk read: the walk proves the bank path, not the feature set.
    /// `.inferred` and `.untested`, because the record holds nothing on the body either way.
    func provisionalModel(productName: String) -> CameraModel {
        Self.make(id: Self.unlistedModelID, name: productName, gen: .xTransV, processor: .xProcessor5,
                  fields: Self.fieldsV, sims: Self.sims(for: .xProcessor5),
                  whiteBalanceModes: Self.whiteBalanceModesWithAutoPriorities,
                  ranges: Self.rangesToningEighteen,
                  supportsNaming: true,
                  writeSupport: .untested)
    }

    // MARK: - Model data

    private static func buildModels() -> [CameraModel] {
        var result: [CameraModel] = []

        // X-Trans I and II — EXR processors, before the bank protocol and before X RAW Studio's USB
        // conversion: the app expects no bank protocol on them and has no Kitchen for them. No
        // published record shows `0xD18C` on any of them, and Fujifilm's X RAW Studio list starts
        // at the X-Trans III bodies (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md`). They are
        // here so a recipe can be judged against them: the Works With card and the Library's
        // camera filter read these entries like any other.
        //
        // `.untested`, not `.blocked`: the record holds no USB observation of any of them, for or
        // against, so there is no failure to quote. `slotProtocol: false` records the expectation
        // that `0xD18C` is absent; nothing has measured it, so the connect still reads the selector,
        // and `WriteDecision` grants writes to one whose slots answer.
        //
        // Fields and film lists are from Fujifilm's manuals, body by body [Published: Fujifilm
        // manuals]: no Grain Effect, Color Chrome, D-Range Priority, Clarity or Monochromatic Color
        // on any of them; ten film simulations on X-Trans I and the X100S, eleven from the X-T1 on,
        // five on the X-M1. The X-T1 and X-E2 gained Classic Chrome at firmware 3.00 [Published:
        // Fujifilm firmware notes]; the X100S never did. Numeric ranges are deliberately unset: the
        // manuals print the controls without their values and the commonly repeated ±2 is
        // unverified, so no clamp is claimed, the editor falls back to its Generic ranges, and the
        // Works With card says "range not verified" where it would have checked one. Each body's
        // manual is linked in `docs/supported-cameras.md#sources-for-older-bodies`.
        // Bank counts are the manuals' EDIT/SAVE CUSTOM SETTING pages: seven, except one on the
        // X-M1, three on the X100S, and none found for the X100T. White balance is AUTO, the
        // presets, Kelvin and Underwater on all of them, without the White and Ambience priorities;
        // the X-M1 has neither Kelvin nor Underwater [Published: Fujifilm manuals].
        for (id, name, sims, banks) in [("X-Pro1", "FUJIFILM X-Pro1", simsXTransI, 7),
                                        ("X-E1", "FUJIFILM X-E1", simsXTransI, 7),
                                        ("X-M1", "FUJIFILM X-M1", simsXM1, 1)] as [(String, String, [FilmSimulation], Int?)] {
            result.append(make(id: id, name: name, gen: .xTransI, processor: .exrProcessor,
                               fields: fieldsXTransLegacy, sims: sims,
                               whiteBalanceModes: id == "X-M1" ? whiteBalanceModesBase : whiteBalanceModesWithKelvin,
                               ranges: [:],
                               grainSize: false, slotProtocol: false,
                               documentedSlotCount: banks,
                               writeSupport: .untested))
        }
        for (id, name, sims, banks) in [("X100S", "FUJIFILM X100S", simsXTransI, 3),
                                        ("X-T1", "FUJIFILM X-T1", simsXTransII, 7),
                                        ("X-E2", "FUJIFILM X-E2", simsXTransII, 7),
                                        ("X-E2S", "FUJIFILM X-E2S", simsXTransII, 7),
                                        ("X-T10", "FUJIFILM X-T10", simsXTransII, 7),
                                        ("X70", "FUJIFILM X70", simsXTransII, 7),
                                        ("X100T", "FUJIFILM X100T", simsXTransII, nil)] as [(String, String, [FilmSimulation], Int?)] {
            result.append(make(id: id, name: name, gen: .xTransII, processor: .exrProcessor,
                               fields: fieldsXTransLegacy, sims: sims, ranges: [:],
                               grainSize: false, slotProtocol: false,
                               documentedSlotCount: banks,
                               writeSupport: .untested))
        }

        // X-Trans III — no direct bank protocol (0xD18C…) is expected. An owner's **X-T20** report
        // settles it for that body on hardware (fw 2.01;
        // zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#x-t20`): `GetDeviceInfo` lists 168
        // properties and 0xD18C/0xD18D are not among them, and every one of the 26 bank reads
        // answers 0x200A. That measured refusal is why the X-T20 alone is `.blocked`.
        // `supportsSlotProtocol: false` is what stops the app writing 0xD18C at a body that has no
        // such property — see `CameraModel`. A published tool reaches an X100F's banks through the
        // settings-backup object instead (zgrimz/fujifilm-ptp-reference
        // `docs/04-custom-slots.md#how-many-banks`), a path the app doesn't implement.
        //
        // The X-Pro2, X-T2, X100F and X-E3 are `.untested`: same generation and processor, and no
        // USB observation of their banks in the record either way, so the group's `slotProtocol:
        // false` is an expectation on them, not a measurement. The read-only sweep reads 0xD18C
        // without writing it, and flags a body that answers against expectation. The X-E3's
        // fields and film list are the group's [Published: Fujifilm manual, X-E3 image
        // quality setting page, linked in `docs/supported-cameras.md#sources-for-older-bodies`].
        // White balance is AUTO alone, without the White and Ambience priorities, on the X-T2, X-T20
        // and X-E3 [Published: Fujifilm manuals]; the X-Pro2 and X100F manuals were not checked and
        // take the same default, which claims nothing beyond it.
        //
        // The Kitchen is on, by generation, the way the X-T3 and X-T30 have it. The X-T20 report
        // shows the conversion signature the GFX100S showed before its harvest: `0xD183` answers a
        // writable UINT16 descriptor enumerating [0, 1], `0xD185` answers 0x2002 until a RAF has
        // been uploaded, and every operation conversion uses is advertised. Fujifilm added USB
        // conversion with X RAW Studio in X-T20 firmware 2.00 and supports it on the X-Pro2, X-T2
        // and X-E3; conversions on an X100F have been published, one with a 601-byte profile read —
        // the X-H1's 601-byte / 23-param shape, which `FujiRawConvProfile` already resolves
        // (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#summary`). Nothing has been developed
        // through this app on any of the four, so the first develop is a tester's, with
        // `resolveLayout` as the guard. An X-T20 below firmware 2.00 has no USB conversion; the
        // registry doesn't read firmware, so on such a body the develop fails before a profile is
        // written.
        for (id, name) in [("X-Pro2", "FUJIFILM X-Pro2"), ("X-T2", "FUJIFILM X-T2"),
                           ("X100F", "FUJIFILM X100F"), ("X-T20", "FUJIFILM X-T20"),
                           ("X-E3", "FUJIFILM X-E3")] {
            result.append(make(id: id, name: name, gen: .xTransIII, processor: .xProcessorPro,
                               fields: fieldsIII, sims: simsIII, ranges: rangesClassicTone,
                               grainSize: false,
                               rawConversion: true, slotProtocol: false,
                               // The X-E3's manual lists seven banks; the other four were not in
                               // the manual sweep and stay unrecorded.
                               documentedSlotCount: id == "X-E3" ? 7 : nil,
                               writeSupport: id == "X-T20"
                                   ? .blocked(reason: "\(name) doesn't expose custom slots through the bank protocol Fuji Cookbook uses, so its slots aren't read or written. You can still develop RAW files with it in the Kitchen, and recipes authored for it can be pushed to other bodies.")
                                   : .untested))
        }

        // X-H1 — X-Trans III and X-Processor Pro like the group above, with two things the others
        // lack: ETERNA, which debuted on it, and D-Range Priority [Published: Fujifilm manual, X-H1
        // image quality setting page, linked in `docs/supported-cameras.md#sources-for-older-bodies`].
        // Grain is strength only, tones are whole-step, white balance is AUTO alone, and there is no
        // Color Chrome or Monochromatic Color. The slot protocol is the group's inference, so like
        // the X-Pro2 it is `.untested`: the record holds no USB observation of its banks either way
        // (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#summary`). Fujifilm's X RAW Studio
        // supports it, and the published X-H1 `0xD185` profile is the 601-byte shape
        // `FujiRawConvProfile` already resolves (same chapter).
        result.append(make(id: "X-H1", name: "FUJIFILM X-H1", gen: .xTransIII, processor: .xProcessorPro,
                           fields: fieldsXH1, sims: simsXH1, ranges: rangesClassicTone,
                           grainSize: false,
                           rawConversion: true, slotProtocol: false,
                           documentedSlotCount: 7,
                           writeSupport: .untested))

        // X-Trans IV (early: X-T3 / X-T30 — no Clarity, Color Chrome FX Blue, Classic Neg, Bleach
        // Bypass, and grain strength only). Neither has a working direct bank path: an X-T3 at
        // fw 5.11 fails every select, and an X-T30 at fw 2.01 fails the first
        // (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#x-t3-and-x-t30`), which is why both
        // are `.blocked` rather than `.untested`. A published tool
        // reaches the X-T3's banks by patching its settings-backup object instead
        // (`docs/04-custom-slots.md#how-many-banks`), a path the app doesn't implement.
        //
        // RAW conversion is a different capability and these bodies have it: the record has
        // conversions on both (same chapter), and published 0xD185 profiles show the same wire
        // format across every processor generation (`docs/06-conversion-profile.md#layout`). So the
        // Kitchen is enabled here even though the slots stay read-only.
        //
        // Monochromatic Color here is the warm–cool axis alone, at −9…+9: Fujifilm's manuals for
        // both bodies print that single table (zgrimz/fujifilm-ptp-reference `docs/03-encodings.md`).
        // Every later body with the control has the magenta–green axis as well. Grain is strength
        // only on both — their manuals' GRAIN EFFECT is Strong / Weak / Off — the one X-Processor 4
        // group without a size control (`CameraModel.hasGrainSizeControl`). White balance is AUTO
        // alone on both, without the White and Ambience priorities [Published: Fujifilm manuals].
        for (id, name) in [("X-T3", "FUJIFILM X-T3"), ("X-T30", "FUJIFILM X-T30")] {
            // Sims are the explicit early-firmware list rather than `sims(for: .xProcessor4)`:
            // these two shipped without Classic Neg and Bleach Bypass and never gained them.
            result.append(make(id: id, name: name, gen: .xTransIV, processor: .xProcessor4,
                               fields: fieldsIVEarly, sims: simsIVEarly, ranges: rangesWholeStepWithToning,
                               magentaGreenAxis: false,
                               grainSize: false,
                               rawConversion: true, slotProtocol: false,
                               writeSupport: .blocked(reason: "\(name) doesn't expose custom slots through the bank protocol Fuji Cookbook uses, so its slots aren't read or written. You can still develop RAW files with it in the Kitchen, and recipes authored for it can be pushed to other bodies.")))
        }

        // X-Trans IV (late: full gen-IV feature set). Slot read/write enabled on reports for three
        // of them: an X100V with all seven banks read with names and a film-simulation write
        // verified; an X-S10's published bank reads and write/readback sweeps across every recipe
        // field, body-checked for D-Range Priority and both toning axes; and an X-T30 II at fw 2.04
        // reading C1–C7 and taking property and name writes, in a report not yet merged upstream
        // (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#summary`). The X-T4 and X-E4 are the
        // same X-Processor 4 architecture on the X RAW Studio list, untested on hardware but
        // protected by the read-back verification every write goes through.
        // RAW conversion is ON for this generation. Published profiles settle the format question:
        // across three processor generations the parameter table sits at the same absolute base
        // with the same field order — only the tail length differs (zgrimz/fujifilm-ptp-reference
        // `docs/06-conversion-profile.md#layout`) — and hardware-verified conversions on gen-IV
        // bodies have been reported. Conversion also leaves nothing behind on the camera (a
        // temporary object we delete), so the write-safety posture that gates slot pushes doesn't
        // apply. The real guard is `FujiRawConvProfile.resolveLayout`, which validates the profile
        // by decoding it and aborts before writing a byte if it doesn't add up.
        for (id, name) in [("X-T4", "FUJIFILM X-T4"),
                           ("X100V", "FUJIFILM X100V"), ("X-S10", "FUJIFILM X-S10"),
                           ("X-E4", "FUJIFILM X-E4"), ("X-T30 II", "FUJIFILM X-T30 II")] {
            result.append(make(id: id, name: name, gen: .xTransIV, processor: .xProcessor4,
                               fields: fieldsIVLate,
                               // The X100V never received Bleach Bypass — see
                               // `simsIVLateWithoutBleachBypass`.
                               sims: id == "X100V" ? simsIVLateWithoutBleachBypass : sims(for: .xProcessor4),
                               // The X-T4, X-S10, X-E4 and X-T30 II list WHITE PRIORITY and AMBIENCE
                               // PRIORITY beside AUTO; the X100V's manual lists AUTO alone
                               // [Published: Fujifilm manuals, image quality setting pages].
                               whiteBalanceModes: id == "X100V" ? whiteBalanceModesWithKelvin : whiteBalanceModesWithAutoPriorities,
                               // The X-T4 and X100V run Monochromatic Color to ±18 on Community reports
                               // (see `rangesToningEighteen`), and the X-S10 on published readbacks
                               // of −180 and +180 on both axes, checked on the body. The X-E4 and
                               // X-T30 II keep `rangesModern`'s cap until a report shows more; the
                               // X-T30 II report left both toning writes out of its scope. The
                               // X100V's tones are whole-step, unlike the X-T4's — see
                               // `rangesToningEighteenWholeStep`.
                               ranges: id == "X100V" ? rangesToningEighteenWholeStep
                                   : (["X-T4", "X-S10"].contains(id) ? rangesToningEighteen : rangesModern),
                               // Three have a report behind them; the X-T4 and X-E4 are the
                               // architecture inference this comment block describes.
                               verification: ["X100V", "X-S10", "X-T30 II"].contains(id) ? .community : .inferred,
                               supportsNaming: true,
                               rawConversion: true,
                               // The X-S10 recalls banks from its mode dial, which has C1–C4 and no
                               // more; the traditional-dial bodies in this group recall from the
                               // menu and have seven. Manual-derived — `slotCount` stays 7.
                               documentedSlotCount: id == "X-S10" ? 4 : 7,
                               writeSupport: .readWrite))
        }

        // X-Pro3: the one X-Processor 4 body with a report *against* the bank protocol. On an X-Pro3
        // at firmware 2.00, a published test found bank reads, property writes and name writes
        // all failing, without recording the response codes or a cause
        // (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#x-pro3`). That is a failed path, not a body
        // shown to lack banks: X RAW Studio 1.8.0 says it transfers custom settings to an X-Pro3 or
        // newer, so the reason the user sees says only what was observed. Listed writable, the
        // connect walk would select C1 and fail; listed like the X-T3, the read-only sweep reads
        // `0xD18C` without writing it and records what the body answers — the one fact that would
        // un-block it. Conversion stays on: published captures include an X-Pro3 `0xD185` profile
        // (zgrimz/fujifilm-ptp-reference `docs/06-conversion-profile.md#lengths-seen`).
        result.append(make(id: "X-Pro3", name: "FUJIFILM X-Pro3", gen: .xTransIV, processor: .xProcessor4,
                           fields: fieldsIVLate, sims: simsIVLateWithoutBleachBypass,
                           // White balance is AUTO alone, without the priorities [Published: Fujifilm
                           // manual, X-Pro3 image quality setting page] — the default.
                           // ±18 toning on a Community report, whole-step tones per its manual — see
                           // `rangesToningEighteenWholeStep`.
                           ranges: rangesToningEighteenWholeStep,
                           rawConversion: true, slotProtocol: false,
                           writeSupport: .blocked(reason: "A published test found custom-slot reads and writes failing on the FUJIFILM X-Pro3 at firmware 2.00, and the cause isn't known yet, so Fuji Cookbook doesn't read or write its slots. You can still develop RAW files with it in the Kitchen, and recipes authored for it can be pushed to other bodies.")))

        // X-Trans IV sensor, X-Processor 5: the X-T30 III (2025) and X-M5 (2024). Film simulations
        // follow the processor, so both ship REALA ACE and Nostalgic Neg, and both carry the
        // physical Film Simulation dial. The X-T30 III's name contains "X-T30 II"; a registry entry
        // is what makes it exact.
        //
        // Both write, on different evidence. The X-M5 writes on its owner's report (below). The
        // X-T30 III **writes on nobody's report**, on the same footing as the `.inferred` bodies in
        // the two groups around it: a read-only body cannot produce write evidence, because
        // `probeWriteValues` refuses a body the app doesn't write to, so the registry edit has to
        // come before the report (a catch-22, with the GFX100S as the worked example).
        //
        // What the entries rest on, and what they do not. These are X-Processor 5, which is the
        // processor the X-T50 was verified on end to end — so the film list, the encodings and every
        // range but Monochromatic Color's are the verified body's, not a guess. Both toning axes are
        // theirs too (Fujifilm's manuals); only the range stays at `rangesModern`'s −9…+9 cap until
        // one of these bodies shows a wider value (see `rangesModern`).
        // The other guess is `fieldsIVLate`: the X-Trans IV sensor paired with X-Processor 5 is a
        // combination that exists nowhere else in this registry, so which fields these bodies
        // actually expose is inference. That resolves into refusals rather than wrong values — a
        // field the body lacks answers `0x200A` and is recorded — which is why it does not block
        // the write.
        //
        // The X-M5 is that inference carried through a full write pass by an owner in the app's own
        // Camera Test (fw 1.30, 2026-10-31; zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#x-m5`):
        // 19 of 20 properties written and read back, REALA ACE among them, the values and the name
        // surviving a power cycle, 13 menu rows matching, and the restore matching the saved
        // baseline. The read side decodes on the X-T50's tables, across four banks. The one refusal,
        // `0xD191` D-Range Priority, came from a bank whose ISO isn't recorded, so it doesn't test
        // the ISO gate and that field is unsettled, not failed. That is the shape of evidence that
        // holds the GFX100S at `.ownerReport`, and the X-M5 stands there on it.
        //
        // The X-T30 III is still `.inferred`, so its badge says "not yet tested" and the push
        // caveat shows. A write pass from that body is what moves it.
        for (id, name) in [("X-T30 III", "FUJIFILM X-T30 III"), ("X-M5", "FUJIFILM X-M5")] {
            result.append(make(id: id, name: name, gen: .xTransIV, processor: .xProcessor5,
                               fields: fieldsIVLate, sims: sims(for: .xProcessor5),
                               // Both list the White and Ambience priorities [Published: Fujifilm
                               // manuals, X-T30 III and X-M5 image quality setting pages].
                               whiteBalanceModes: whiteBalanceModesWithAutoPriorities,
                               ranges: rangesModern,
                               hasFilmSimulationDial: true,
                               // The X-M5 on its owner's write pass, the X-T30 III on shared
                               // architecture alone — the block above says what each rests on.
                               verification: id == "X-M5" ? .ownerReport : .inferred,
                               supportsNaming: true,
                               rawConversion: true,
                               // The X-M5's mode dial has C1–C4; the X-T30 III recalls from the menu
                               // and has seven. Manual-derived.
                               documentedSlotCount: id == "X-M5" ? 4 : 7,
                               writeSupport: .readWrite))
        }

        // X-Trans V (adds REALA ACE, Nostalgic Neg; Monochromatic Color runs −18…+18 on both axes)
        for (id, name) in [("X-T5", "FUJIFILM X-T5"), ("X-T50", "FUJIFILM X-T50"),
                           ("X-H2", "FUJIFILM X-H2"), ("X-H2S", "FUJIFILM X-H2S"),
                           ("X100VI", "FUJIFILM X100VI"), ("X-S20", "FUJIFILM X-S20"),
                           ("X-E5", "FUJIFILM X-E5")] {
            // X-Trans V family: write + naming enabled. The X-T50 was verified end-to-end on
            // hardware. The X100VI and X-E5 rest on published and community reports; the X-H2
            // (fw 5.20) and X-T5 (fw 4.20) on a published bench — every bank read, written and named,
            // with raw values — and the X-S20 on published bank reads, writes and backup on four
            // banks, with transfers confirmed once Smooth Skin, which the body refuses, became
            // optional (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#summary`). The X-H2S
            // shares the same sensor generation and PTP recipe protocol. Every write is still
            // read-back-verified before being trusted. (X-T50 and X-E5 have the physical Film
            // Simulation dial that overrides a pushed sim — zgrimz/fujifilm-ptp-reference
            // `docs/07-cameras.md#bodies-with-a-physical-film-simulation-dial`.)
            // RAW conversion (Kitchen) is enabled for the whole family: all these bodies are
            // X-Processor 5 with the same blob shape as the verified X-T50, and conversions have been
            // reported on the X100VI, the X-T5 and the X-S20 (same chapter). Only the X-T50 is
            // verified on the development hardware — sanity-check the first developed JPEG on any
            // other body.
            result.append(make(id: id, name: name, gen: .xTransV, processor: .xProcessor5,
                               fields: fieldsV, sims: sims(for: .xProcessor5),
                               // Every one of them lists the White and Ambience priorities
                               // [Published: Fujifilm manuals, image quality setting pages].
                               whiteBalanceModes: whiteBalanceModesWithAutoPriorities,
                               ranges: rangesToningEighteen,
                               hasFilmSimulationDial: id == "X-T50" || id == "X-E5",
                               // Exactly what the comment above says, made machine-readable: the
                               // X-T50 on the development hardware, five more on published or
                               // community reports, and the X-H2S on shared architecture alone. A
                               // published bench is still nobody's write through this app, so the
                               // X-T5 and X-S20 join the X-H2 at `.community`, not above it.
                               verification: id == "X-T50" ? .hardware
                                   : (["X100VI", "X-H2", "X-T5", "X-E5", "X-S20"].contains(id) ? .community : .inferred),
                               supportsNaming: true,
                               rawConversion: true,
                               // The X-S20's mode dial has C1–C4. The X-H2 and X-H2S also recall from
                               // a mode dial, but theirs runs to C7. Manual-derived.
                               documentedSlotCount: id == "X-S20" ? 4 : 7,
                               writeSupport: .readWrite))
        }

        // GFX — medium-format Bayer. The GFX100S is the one body on the line with hardware
        // evidence, from its owner's diagnostic sessions (zgrimz/fujifilm-ptp-reference
        // `docs/07-cameras.md#gfx100s`). The facts the line's entries rest on are recorded there;
        // what follows is why the entries read the way they do.
        //
        // `supportsSlotProtocol` is decided by a read, never by `GetDeviceInfo`. The GFX100S does
        // not advertise 0xD18C–0xD1A5 among its 168 properties and answers every one of them anyway,
        // with values that decode on the X-Trans tables (DR Auto 0xFFFF, grain read values 3 and 6,
        // NR 0x8000 = −4, all matching the camera's own menu). The X-T20 above is the mirror image:
        // not advertised, and genuinely refused. So an advertised list is only ever corroboration.
        //
        // `.ownerReport` is its own level: one owner's full write pass, name first as X RAW Studio
        // does, with the settings and the name persisting across a power cycle and matching the
        // camera's menu. That is above `.community` (published or second-hand reports) and below
        // `.hardware`, which means a body that can be re-driven here on demand when a question
        // comes up; `PushAuditTests.testOnlyTheXT50IsHardwareVerified` is the tripwire that keeps
        // it meaning that. The `.untested` GFX bodies are promoted the same way: one body, one report.
        //
        // **The Kitchen is on for the GFX100S and off for the other GFX bodies.** A property sweep
        // cannot settle conversion support — 0xD185 holds a profile only once the *host* has uploaded
        // a RAF — which is what the profile harvest is for. The GFX100S's harvest is a 28-cell
        // profile that resolves at the canonical base, the X-Pro3's shape
        // (zgrimz/fujifilm-ptp-reference `docs/06-conversion-profile.md#lengths-seen`). Its IOPCode
        // is a dialect code and nothing branches on it. The upload creates **no object** —
        // GetObjectHandles enumerates nothing before or after — so on this body the conversion
        // buffer is not something the card lists. Its owner's develop over USB then matches the
        // camera's own conversion of the same frame statistically (zgrimz/fujifilm-ptp-reference
        // `docs/05-raw-conversion.md#proving-a-conversion-matches-the-cameras-own`).
        //
        // One body, not the line. A harvest answers this for the body that ran it, the same way six
        // banks is a measurement on the GFX100S rather than a property of this entry — and leaving
        // the GFX100 and GFX 50S II off is also what keeps a writable-but-no-Kitchen body in the
        // registry for the harvest step, and its Diagnostic Mode demo, to point at. Their 0xD183
        // descriptors have never been read. The GFX100S's is a writable UINT16 enum [0, 1], the
        // signature of a body that exposes conversion, and it is the only evidence there is about
        // the rest of the line.
        //
        // What one develop does not settle: a develop clamps against `fieldsIVLate` and
        // `simsGFXProcessor4`, which are spec-derived (VERIFY, below), and one recipe on one frame
        // doesn't exercise every cell. `resolveLayout` remains the guard — a profile that doesn't
        // decode aborts the develop before a byte goes out.
        //
        // Fields and film lists are from published specs and firmware release notes (VERIFY).
        // Two places where the GFX line does not follow the X-Trans body of the same processor:
        // Color Chrome Effect *debuted* on the GFX 50S, so the X-Processor Pro entries have it
        // where the X-Trans III group does not; and Nostalgic Neg reached the X-Processor 4 bodies
        // by firmware, where no X-Trans gen-IV body ever got it.

        // X-Processor Pro: no grain size, integer tone steps, no Clarity or Monochromatic Color.
        for (id, name) in [("GFX50S", "FUJIFILM GFX 50S"), ("GFX50R", "FUJIFILM GFX 50R")] {
            result.append(make(id: id, name: name, gen: .gfx, processor: .xProcessorPro,
                               fields: fieldsGFXPro, sims: simsGFXPro, ranges: rangesClassicTone,
                               // White balance is AUTO alone on both [Published: Fujifilm manuals] —
                               // the default.
                               grainSize: false,
                               writeSupport: .untested))
        }

        // X-Processor 4 — **the whole group writes.** The GFX100S is the body with the report; the
        // GFX100 and GFX 50S II are promoted on being *the same entry as it* rather than on
        // anything of their own. That is a different and stronger claim than the architecture
        // inference the `.inferred` X-Trans bodies ship on: those share a processor with the X-T50
        // and nothing else, while these three share this group's every argument —
        // `fieldsIVLate`, `simsGFXProcessor4`, `rangesModern`, X-Processor 4 — and one of them came
        // back from a full end-to-end write pass clean (pushed, power-cycled, name held,
        // menu-confirmed on 13 rows, photo-confirmed, undone). Promoting the siblings is the same
        // move the X-T30 III got, with more behind it.
        //
        // What does *not* carry across is the slot count: six is a measurement on the GFX100S and
        // the other two keep the registry's assumption of seven, which the connect walk corrects at
        // runtime — the same way the six was found in the first place.
        //
        // The other four GFX are `.untested` and are a genuinely different question: the 50S/50R are
        // X-Processor Pro with their own field and film sets, and the 100 II / 100S II are
        // X-Processor 5 with no write report of their own. Their nearest evidence is the GFX100RF
        // below, the line's X-Processor 5 body with a published write record, and for the GFX100 II
        // a published camera dump in tether mode, where `0xD18C` answers a descriptor enumerating
        // 1–6 (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md#how-many-banks`). None has a
        // recorded failure to quote, so none is `.blocked`. A read-only report is what promoted the
        // GFX100S, and it is what would promote these.
        //
        // No film simulation dial anywhere on the line, so nothing confounds a write test here the
        // way it does on the X-T50, X-E5, X-T30 III and X-M5.
        //
        // Monochromatic Color on this group: both axes on all three (Fujifilm's manuals; the
        // GFX100S's write pass read WC +2 / MG −1 back from its own menu, fw 2.13, 2026-09-15 —
        // zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#gfx100s`). The GFX100 gained the magenta–green axis in
        // firmware 4.00; before that it has the warm–cool axis alone at −9…+9. The
        // registry does not read firmware, so the entry describes 4.00 and later. What an older
        // body answers to a `0xD194` write is untested: no GFX100 has shown the bank protocol, and
        // the record only infers that a single-axis body uses `0xD193` alone. If it refuses the
        // write, the push reports the bank as partly applied, with the row and the code named.
        // The GFX100 at 4.00 (WC +12 / MG −14 in Fujifilm X Thailand's
        // firmware tutorial, listed in `docs/supported-cameras.md`) and the GFX100S (menu
        // photographs at −18…+18, zgrimz/fujifilm-ptp-reference
        // `docs/03-encodings.md#menu-range-per-body`) run past ±9 and take `rangesToningEighteen`;
        // the GFX 50S II has no range evidence and keeps `rangesModern`'s cap.
        for (id, name) in [("GFX100", "FUJIFILM GFX 100"), ("GFX100S", "FUJIFILM GFX100S"),
                           ("GFX50S II", "FUJIFILM GFX 50S II")] {
            let isTheReportedBody = id == "GFX100S"
            result.append(make(id: id, name: name, gen: .gfx, processor: .xProcessor4,
                               fields: fieldsIVLate, sims: simsGFXProcessor4,
                               // The GFX100 has the standard AUTO alone, even at firmware 4.00; the
                               // GFX100S and GFX 50S II list the White and Ambience priorities
                               // [Published: Fujifilm manuals, image quality setting pages].
                               whiteBalanceModes: id == "GFX100" ? whiteBalanceModesWithKelvin : whiteBalanceModesWithAutoPriorities,
                               ranges: id == "GFX50S II" ? rangesModern : rangesToningEighteen,
                               verification: isTheReportedBody ? .ownerReport : .inferred,
                               // Goes with `writable`: a push names the bank it writes — see
                               // `testNoWritableBodyHasSlotNamingOff`.
                               supportsNaming: true,
                               // On the GFX100S's own harvested profile; the siblings' Kitchen stays
                               // off. See the block above.
                               rawConversion: isTheReportedBody,
                               // Six, measured: `SetDevicePropValue 0xD18C = 7` answers `0x200A
                               // DeviceProp Not Supported` on this body while 1–6 are accepted
                               // (2026-09-15, fw 2.13). Without this, a session spends four refused
                               // transactions rediscovering that — once per connect and once after
                               // every push. The trade is that the app also stops discovering a
                               // firmware that later allows C7; a report showing a seventh bank is
                               // how that would come back.
                               slotCount: isTheReportedBody ? 6 : 7,
                               // The manual agrees with the measurement on the GFX100S — the only
                               // body where both numbers exist, and the only evidence that the menu
                               // count and the `0xD18C` count are the same thing. The GFX 50S II is
                               // a PSAM-dial body like it (C1–C6); the original GFX100 has no mode
                               // dial and recalls seven from the menu.
                               documentedSlotCount: id == "GFX100" ? 7 : 6,
                               writeSupport: .readWrite))
        }

        // X-Processor 5: REALA ACE, Nostalgic Neg. Monochromatic Color on both axes, with the
        // range at `rangesModern`'s cap — nothing recorded shows either body past ±9.
        for (id, name) in [("GFX100 II", "FUJIFILM GFX100 II"), ("GFX100S II", "FUJIFILM GFX100S II")] {
            result.append(make(id: id, name: name, gen: .gfx, processor: .xProcessor5,
                               fields: fieldsV, sims: sims(for: .xProcessor5),
                               // Both list the White and Ambience priorities [Published: Fujifilm
                               // manuals, GFX100 II and GFX100S II image quality setting pages].
                               whiteBalanceModes: whiteBalanceModesWithAutoPriorities,
                               ranges: rangesModern,
                               // PSAM-dial bodies, C1–C6 per the manual. Untested, so the walk
                               // that would confirm it is the only thing this number affects.
                               documentedSlotCount: 6,
                               writeSupport: .untested))
        }

        // GFX100RF: writable on a published record rather than a report through this app.
        // That record read, wrote and named its seven banks from iOS 26 and macOS 26 through
        // ImageCaptureCore — the framework this app uses — with raw values, and its encodings match
        // the X-T50's (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#gfx100rf`). `.community` is the honest
        // level: more than inference, less than a tester's write pass here. Two of its findings
        // matter to a push. `0xD18C` resets to the body's bank when the bank is changed on the
        // camera; every operation here selects first, so nothing depends on it. And a write of `0`
        // to either Monochromatic Color axis is refused even on a monochrome simulation, where the
        // X-T50 and X-H2 accept it — the app writes explicit zeros, so a neutral-toning recipe will
        // report two refusals there, and `SlotWriteResult.toningZeroRefusalHint` says why. No film
        // simulation dial. Conversion untested over USB, so the Kitchen stays off.
        result.append(make(id: "GFX100RF", name: "FUJIFILM GFX100RF", gen: .gfx, processor: .xProcessor5,
                           fields: fieldsV, sims: sims(for: .xProcessor5),
                           // Lists the White and Ambience priorities [Published: Fujifilm manual,
                           // GFX100RF image quality setting page].
                           whiteBalanceModes: whiteBalanceModesWithAutoPriorities,
                           ranges: rangesModern,
                           verification: .community,
                           supportsNaming: true,
                           documentedSlotCount: 7,
                           writeSupport: .readWrite))

        // Demo camera — gen-V feature set, write-verified against the mock transport.
        result.append(CameraModel(
            id: demoModelID,
            displayName: "Demo Camera (no hardware)",
            sensorGeneration: .xTransV,
            processor: .xProcessor5,
            supportsSlotProtocol: true,
            slotCount: 7,
            documentedSlotCount: nil,
            supportedFields: fieldsV,
            supportedFilmSimulations: simsV,
            // Every mode, so a demo push never warns about a white balance a real body might refuse.
            supportedWhiteBalanceModes: Set(WhiteBalanceMode.allCases),
            ranges: rangesToningEighteen,
            hasMagentaGreenAxis: true,
            hasGrainSizeControl: true,
            supportsSlotNaming: true,
            // Matches a real body, so what a tester sees here is what hardware does.
            slotNameMaxLength: CameraSlotName.maxLength,
            slotNameAllowedCharacters: slotNameCharacters,
            writeSupport: .readWrite,
            // The mock round-trips our own codec, so its write path really is verified — against
            // the mock. Marking it `.hardware` keeps the unverified-body copy out of the demo,
            // which would otherwise warn about a camera that doesn't exist.
            verification: .hardware,
            supportsRawConversion: true,
            hasFilmSimulationDial: false))

        return result
    }

    private static func make(id: String, name: String, gen: SensorGeneration, processor: ProcessorGeneration,
                             fields: Set<RecipeField>, sims: [FilmSimulation],
                             whiteBalanceModes: Set<WhiteBalanceMode> = whiteBalanceModesWithKelvin,
                             ranges: [RecipeField: NumericRange],
                             magentaGreenAxis: Bool = true,
                             grainSize: Bool = true,
                             hasFilmSimulationDial: Bool = false,
                             verification: VerificationLevel = .inferred,
                             supportsNaming: Bool = false,
                             rawConversion: Bool = false,
                             slotProtocol: Bool = true,
                             slotCount: Int = 7,
                             documentedSlotCount: Int? = nil,
                             writeSupport: WriteSupport) -> CameraModel {
        return CameraModel(
            id: id,
            displayName: name,
            sensorGeneration: gen,
            processor: processor,
            // Defaults to true: a body is assumed to have slots unless an entry says otherwise, so
            // a new entry can never lose the capability by omission. The groups that pass
            // `slotProtocol: false` are the bodies the record shows refusing or failing the bank
            // path (`.blocked`) and the older bodies expected to match them (`.untested`).
            supportsSlotProtocol: slotProtocol,
            // Defaults to 7, which is the registry's assumption rather than a measurement —
            // `SlotReader` probes the real count by walking until a select is refused.
            // An entry overrides it only where that walk has already answered on hardware, so the
            // app stops writing a selector it knows will come back refused.
            slotCount: slotCount,
            // Why this is a second number rather than a lower `slotCount`: see
            // `CameraModel.documentedSlotCount`.
            documentedSlotCount: documentedSlotCount,
            supportedFields: fields,
            supportedFilmSimulations: sims,
            // Defaults to the *smaller* set — the opposite of `slotProtocol`'s default, on purpose.
            // A mode claimed by omission would be a guess encoded as fact; a mode missed shows up
            // as a warning the manual can correct. Only entries whose manual prints the Auto
            // priorities pass the larger set.
            supportedWhiteBalanceModes: whiteBalanceModes,
            ranges: ranges.filter { fields.contains($0.key) },
            // Defaults to true for the reason `slotProtocol` does: an entry cannot lose the axis by
            // omission. Only the X-T3 and X-T30 pass `false`.
            hasMagentaGreenAxis: magentaGreenAxis,
            // Defaults to true for the same reason. The X-Processor Pro groups and the X-T3/X-T30
            // pass `false`.
            hasGrainSizeControl: grainSize,
            // On for every writable body as a product rule: a push names the bank it writes
            // (`testNoWritableBodyHasSlotNamingOff`). Not a persistence switch: property writes
            // persist without a name (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md`).
            // Where it is off the push silently skips the name write, never an error.
            supportsSlotNaming: supportsNaming,
            // 25 and printable ASCII, both round-tripped on an X-T50 (2026-09-07): written, shown
            // correctly on the camera's own menu, and read back unchanged.
            slotNameMaxLength: supportsNaming ? CameraSlotName.maxLength : 0,
            slotNameAllowedCharacters: slotNameCharacters,
            writeSupport: writeSupport,
            // Defaults to `.inferred`, which is the honest answer for a body nobody has plugged in.
            // Read-only entries carry it too and simply never surface it.
            verification: verification,
            // RAW conversion is off by default and opted in per group or per body via
            // `rawConversion` — independent of slot-write support.
            supportsRawConversion: rawConversion,
            hasFilmSimulationDial: hasFilmSimulationDial)
    }

    // MARK: - Field sets

    private static let coreFields: Set<RecipeField> = [
        .filmSimulation, .grain, .whiteBalance, .dynamicRange,
        .highlightTone, .shadowTone, .color, .sharpness, .highISONR
    ]

    private static let fieldsIII: Set<RecipeField> = coreFields

    private static let fieldsIVEarly: Set<RecipeField> = coreFields.union([
        .colorChromeEffect, .dRangePriority, .monochromaticColor
    ])

    private static let fieldsIVLate: Set<RecipeField> = fieldsIVEarly.union([
        .colorChromeFXBlue, .clarity
    ])

    private static let fieldsV: Set<RecipeField> = fieldsIVLate

    /// GFX 50S / 50R: the core nine plus Color Chrome Effect, which Fujifilm introduced on the
    /// GFX 50S itself — so this is `fieldsIII` plus the one field, not the X-Trans III set. No
    /// D-Range Priority, no Clarity, no Monochromatic Color.
    private static let fieldsGFXPro: Set<RecipeField> = fieldsIII.union([.colorChromeEffect])

    /// X-Trans I and II: the core set without Grain Effect — none of them has grain, Color Chrome,
    /// D-Range Priority, Clarity or Monochromatic Color [Published: Fujifilm manuals, X-Pro1
    /// through X100T].
    private static let fieldsXTransLegacy: Set<RecipeField> = coreFields.subtracting([.grain])

    /// X-H1: the X-Trans III set plus D-Range Priority, which debuted there [Published: Fujifilm
    /// manual, X-H1 image quality setting page].
    private static let fieldsXH1: Set<RecipeField> = fieldsIII.union([.dRangePriority])

    // MARK: - Film simulation sets

    private static let simsIII: [FilmSimulation] = [
        .provia, .velvia, .astia, .classicChrome, .proNegHi, .proNegStd,
        .acros, .acrosYe, .acrosR, .acrosG,
        .monochrome, .monochromeYe, .monochromeR, .monochromeG, .sepia
    ]

    private static let simsIVEarly: [FilmSimulation] =
        simsIII.insertingColorSims([.eterna]) // X-T3/X-T30: Eterna yes; Classic Neg / Bleach Bypass no.

    private static let simsIVLate: [FilmSimulation] =
        simsIII.insertingColorSims([.classicChrome, .classicNeg, .eterna, .eternaBleachBypass])

    /// The X100V and X-Pro3: the gen-IV list without ETERNA Bleach Bypass. Fujifilm's specification
    /// pages list 17 film simulations for each — the colour set through Classic Neg. and ETERNA,
    /// then the monochrome group — and Bleach Bypass is not among them [Published: Fujifilm, X100V
    /// and X-Pro3 specifications]. The protocol record keeps no per-body film list, so this cites
    /// Fujifilm directly, as the GFX lists below do.
    private static let simsIVLateWithoutBleachBypass: [FilmSimulation] =
        simsIII.insertingColorSims([.classicNeg, .eterna])

    private static let simsV: [FilmSimulation] =
        simsIVLate.insertingColorSims([.nostalgicNeg, .realaAce])

    /// GFX 50S / 50R: the X-Trans III list plus Classic Neg. and ETERNA, which Fujifilm's firmware
    /// release of 2020-06-30 adds to both — GFX 50S 4.00 and GFX 50R 2.00 [Published: Fujifilm,
    /// firmware announcement 2020-06-30]. No Bleach Bypass, no Nostalgic Neg. The registry does
    /// not read firmware, so the entry describes a body on that firmware or later, as the GFX100
    /// entry does for 4.00. The same 17 as `simsIVLateWithoutBleachBypass`, kept apart because the
    /// evidence is a different document.
    private static let simsGFXPro: [FilmSimulation] = simsIII.insertingColorSims([.classicNeg, .eterna])

    /// GFX 100 / 100S / 50S II: the full gen-IV list plus Nostalgic Neg, which reached these
    /// bodies by firmware — where no X-Trans X-Processor 4 body ever got it, so this can't come
    /// from `sims(for:)`. REALA ACE is X-Processor 5 only and stays out. VERIFY.
    private static let simsGFXProcessor4: [FilmSimulation] =
        simsIVLate.insertingColorSims([.nostalgicNeg])

    /// X-Trans I (X-Pro1, X-E1) and the X100S: ten simulations, before Classic Chrome and ACROS
    /// [Published: Fujifilm manuals, X-Pro1, X-E1 and X100S].
    private static let simsXTransI: [FilmSimulation] = [
        .provia, .velvia, .astia, .proNegHi, .proNegStd,
        .monochrome, .monochromeYe, .monochromeR, .monochromeG, .sepia
    ]

    /// X-M1: five — no PRO Neg pair and no filtered monochromes [Published: Fujifilm manual, X-M1].
    private static let simsXM1: [FilmSimulation] = [.provia, .velvia, .astia, .monochrome, .sepia]

    /// X-Trans II from the X-T1 on: the X-Trans I ten plus Classic Chrome, which the X-T1 and X-E2
    /// gained at firmware 3.00 and the later bodies shipped with [Published: Fujifilm manuals and
    /// firmware notes]. The X100S never received it and keeps `simsXTransI`.
    private static let simsXTransII: [FilmSimulation] = simsXTransI.insertingColorSims([.classicChrome])

    /// X-H1: the X-Trans III list plus ETERNA, which debuted there [Published: Fujifilm manual,
    /// X-H1 image quality setting page]. The same sixteen as `simsIVEarly`, kept apart because the
    /// evidence is a different manual.
    private static let simsXH1: [FilmSimulation] = simsIII.insertingColorSims([.eterna])

    /// The film list a processor generation ships with. Four X-Processor 4 bodies pass their own
    /// list instead: the X-T3 and X-T30 (`simsIVEarly`), and the X100V and X-Pro3
    /// (`simsIVLateWithoutBleachBypass`). The EXR list is the X-Trans II one; the X-Trans I bodies,
    /// the X100S and the X-M1 pass `simsXTransI` or `simsXM1`.
    private static func sims(for processor: ProcessorGeneration) -> [FilmSimulation] {
        switch processor {
        case .exrProcessor: return simsXTransII
        case .xProcessorPro: return simsIII
        case .xProcessor4: return simsIVLate
        case .xProcessor5: return simsV
        }
    }

    // MARK: - White balance modes

    /// AUTO and the presets every body's WHITE BALANCE menu lists [Published: Fujifilm manuals].
    /// A measured custom white balance is a per-camera reading, not a recipe value.
    private static let whiteBalanceModesBase: Set<WhiteBalanceMode> = [
        .auto, .daylight, .shade, .fluorescent1, .fluorescent2, .fluorescent3, .incandescent
    ]

    /// The base plus Color Temperature and Underwater: every body but the X-M1.
    private static let whiteBalanceModesWithKelvin: Set<WhiteBalanceMode> =
        whiteBalanceModesBase.union([.kelvin, .underwater])

    /// `whiteBalanceModesWithKelvin` plus AUTO WHITE PRIORITY and AMBIENCE PRIORITY, which the
    /// manuals print from the X-T4 on and on the GFX100S and later GFX bodies — not on the X-Pro3,
    /// X100V, GFX100 or anything older.
    private static let whiteBalanceModesWithAutoPriorities: Set<WhiteBalanceMode> =
        whiteBalanceModesWithKelvin.union([.autoWhitePriority, .autoAmbiencePriority])

    // MARK: - Ranges

    /// Classic tone with integer steps (X-Trans III).
    private static let rangesClassicTone: [RecipeField: NumericRange] = [
        .highlightTone: NumericRange(min: -2, max: 4, step: 1),
        .shadowTone: NumericRange(min: -2, max: 4, step: 1),
        .color: NumericRange(min: -4, max: 4, step: 1),
        .sharpness: NumericRange(min: -4, max: 4, step: 1),
        .highISONR: NumericRange(min: -4, max: 4, step: 1)
    ]

    /// `rangesClassicTone` plus the single warm–cool toning axis at −9…+9: the X-T3 and X-T30.
    /// Their manuals print HIGHLIGHT TONE and SHADOW TONE as +4…−2 in whole steps, and the same
    /// pages print the one −9…+9 B & W ADJ. table [Published: Fujifilm manuals, X-T3 and X-T30
    /// image quality setting pages]; the half-step list in zgrimz/fujifilm-ptp-reference
    /// `docs/07-cameras.md` (processor generations) leaves both out. No Clarity, but `make` filters
    /// by the body's fields anyway.
    private static let rangesWholeStepWithToning: [RecipeField: NumericRange] = rangesClassicTone.merging(
        [.monochromaticColor: NumericRange(min: -9, max: 9, step: 1)]) { $1 }

    /// Modern tone with half-steps + Clarity + Monochromatic Color: the X-Trans IV and GFX bodies
    /// without toning-range evidence of their own, and the base of `rangesToningEighteen`.
    private static let rangesModern: [RecipeField: NumericRange] = [
        .highlightTone: NumericRange(min: -2, max: 4, step: 0.5),
        .shadowTone: NumericRange(min: -2, max: 4, step: 0.5),
        .color: NumericRange(min: -4, max: 4, step: 1),
        .sharpness: NumericRange(min: -4, max: 4, step: 1),
        .highISONR: NumericRange(min: -4, max: 4, step: 1),
        .clarity: NumericRange(min: -5, max: 5, step: 1),
        // Monochromatic Color, ×10 on the wire, one range for both axes. On every body in this
        // table — X-E4, X-T30 II, X-T30 III, X-M5, GFX 50S II, GFX100 II, GFX100S II, GFX100RF —
        // −9…+9 is an operational cap, not a measurement: their manuals name both axes and print
        // no endpoints (the open question in zgrimz/fujifilm-ptp-reference
        // `docs/open-questions.md`). The X-T3 and X-T30, whose single warm–cool axis prints that
        // table, take `rangesWholeStepWithToning`. A cap set too wide gets a push refused `0x201C`, as `190` is
        // on an X-T50; one set too narrow clamps a value the body could have taken, and the push
        // and the develop say so when they do. Save never clamps toning, so a value read from a
        // bank survives an edit. A write of `180` to a toning axis on a monochrome bank, read
        // back, settles a body. VERIFY.
        .monochromaticColor: NumericRange(min: -9, max: 9, step: 1)
    ]

    /// `rangesModern` with Monochromatic Color at −18…+18 on both axes. Which bodies take it, and
    /// on what: the X-T50, where `±180` is accepted and `190` refused on both axes (fw 1.32,
    /// 2026-10-15), and the X-H2, whose menu runs −18…+18 on a published report (fw 5.20) — the
    /// two with an end stop behind them; the other five X-Trans V bodies as members of the same
    /// group; the X-T4 on Community reports of ±18 on both axes (no bytes, firmware unspecified), and
    /// the X100V and X-Pro3 on the same reports through `rangesToningEighteenWholeStep`; the X-S10,
    /// where a published readback took `−180` and `180` on both axes, checked on the body
    /// (firmware unstated, `190` untried); and the GFX100S, whose menu photographs show −18…+18 on
    /// both axes (fw 2.13). The evidence for each is in zgrimz/fujifilm-ptp-reference
    /// `docs/03-encodings.md#menu-range-per-body`. The record leaves out a second X-T4 report and
    /// the GFX100 past ±9 on both axes at firmware 4.00; `docs/supported-cameras.md` lists both.
    private static let rangesToningEighteen: [RecipeField: NumericRange] = rangesModern.merging(
        [.monochromaticColor: NumericRange(min: -18, max: 18, step: 1)]) { $1 }

    /// `rangesToningEighteen` with HIGHLIGHT TONE and SHADOW TONE in whole steps: the X-Pro3 and
    /// X100V. Their manuals print both as +4…−2 in whole steps [Published: Fujifilm manuals,
    /// X-Pro3 and X100V image quality setting pages]; the half-step list in
    /// zgrimz/fujifilm-ptp-reference `docs/07-cameras.md` (processor generations) leaves both out
    /// while naming the X-T4. Clarity −5…+5 and the ±18 toning axes are the gen-IV ones above.
    private static let rangesToningEighteenWholeStep: [RecipeField: NumericRange] = rangesToningEighteen.merging(
        [.highlightTone: NumericRange(min: -2, max: 4, step: 1),
         .shadowTone: NumericRange(min: -2, max: 4, step: 1)]) { $1 }

    /// White-balance R/B shift range, common across modern bodies (VERIFY per model).
    static let whiteBalanceShiftRange = NumericRange(min: -9, max: 9, step: 1)
    static let kelvinRange = NumericRange(min: 2500, max: 10000, step: 10)

    /// Printable ASCII, per `CameraSlotName` — verified on an X-T50.
    private static let slotNameCharacters = CameraSlotName.allowedCharacters
}

private extension Array where Element == FilmSimulation {
    /// Insert color sims before the first monochrome one, so the picker keeps the monochrome group
    /// at the end.
    func insertingColorSims(_ sims: [FilmSimulation]) -> [FilmSimulation] {
        var ordered = self
        for sim in sims where !ordered.contains(sim) {
            if let monoIndex = ordered.firstIndex(where: { $0.isMonochrome }) {
                ordered.insert(sim, at: monoIndex)
            } else {
                ordered.append(sim)
            }
        }
        return ordered
    }
}
