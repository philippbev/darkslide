import Foundation

/// Fuji sensor generation. Recipe fields and film lists are set per registry entry, not derived
/// from this; it groups bodies in the camera lists and is one of the checks `PhotoRecipeReader`
/// makes before trusting a model.
///
/// The GFX line gets its own case rather than being filed under the nearest X-Trans generation:
/// its sensors are medium-format Bayer, not X-Trans at all, and a field named `sensorGeneration`
/// that answered "X-Trans IV" for a GFX100S would be a fact nobody could trust later. Which
/// *features* a GFX body has follows its `processor`.
///
/// The two oldest X-Trans generations are listed so their bodies can be in the registry — read-only,
/// with no bank protocol and no USB conversion — and judged by the Works With check like any other.
enum SensorGeneration: String, Codable, Hashable {
    case xTransI
    case xTransII
    case xTransIII
    case xTransIV
    case xTransV
    case gfx
    case other
}

/// The image processor. Film simulations follow the processor, not the sensor: the X-T30 III and
/// X-M5 pair an X-Trans 4 sensor with X-Processor 5 and ship REALA ACE. Keyed here so a body's film
/// list is a fact about its processor rather than a per-entry guess; `sensorGeneration` names the
/// sensor line, and no film list is derived from it. That rule holds from X-Processor Pro on: the EXR
/// processors (EXR Processor Pro on X-Trans I, EXR Processor II on X-Trans II) share one case,
/// because nothing here tells them apart and their bodies' film lists are per entry.
enum ProcessorGeneration: String, Codable, Hashable {
    case exrProcessor
    case xProcessorPro
    case xProcessor4
    case xProcessor5
}

/// A numeric parameter's valid range and step for a given camera. Values are clamped to it before
/// anything is written.
struct NumericRange: Equatable, Hashable {
    let min: Double
    let max: Double
    let step: Double

    func clamp(_ value: Double) -> Double {
        let stepped = (value / step).rounded() * step
        return Swift.min(max, Swift.max(min, stepped))
    }

    /// All discrete values, useful for pickers.
    var values: [Double] {
        guard step > 0, max >= min else { return [min] }
        var result: [Double] = []
        var v = min
        while v <= max + 0.0001 {
            result.append((v / step).rounded() * step)
            v += step
        }
        return result
    }
}

/// What the registry publishes about writing recipes to this body.
///
/// Three states, because two different facts both read as "read-only": a body whose bank path
/// failed when somebody tried it, and a body nobody has tried. Whether the app writes is decided
/// from this and from the identification (`WriteDecision`), never from this alone.
/// ``VerificationLevel`` says how firm the evidence for `.readWrite` is.
enum WriteSupport: Equatable, Hashable {
    case readWrite
    /// A recorded failure of the bank path on this body, in the words the user sees.
    case blocked(reason: String)
    /// No record of the bank path on this body either way.
    case untested

    var allowsWrite: Bool {
        if case .readWrite = self { return true }
        return false
    }

    /// The recorded reason writes are blocked; nil for `.readWrite` and `.untested`.
    var blockReason: String? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }
}

/// How firmly this body's write path is known to work.
///
/// Orthogonal to ``WriteSupport``, which says whether the app writes at all. This says how much to
/// trust it when it does. Of the writable bodies, one has been driven on hardware here, two more by
/// their owners through this app, and the others stand on published records or on shared
/// architecture.
///
/// The four levels are kept apart in the compatibility report and the Camera Test, where the
/// difference is the point. The user-facing surfaces split them only in two: a body somebody has
/// written to and reported, and a body nobody has (``ConnectedCamera/capabilityBadge``,
/// ``pushCaveat``).
enum VerificationLevel: Equatable, Hashable {
    /// Driven end-to-end on hardware: read, push, read back, confirmed on the camera's own screen.
    case hardware
    /// An **owner** ran the app's own guided write pass on this body and sent the report: pushed,
    /// power-cycled, read back, and compared against the camera's own menu. Everything `.hardware`
    /// means except the part that makes `.hardware` worth more — nobody here can re-drive it when a
    /// new question comes up.
    ///
    /// Its own case because the report and the Camera Test distinguish it: a published record of
    /// USB behaviour is not somebody writing to their own camera through this app and reporting
    /// what happened.
    case ownerReport
    /// Reported working by someone else, with no report through this app behind it: a published
    /// record with raw values, a second-hand community report, or a detailed report not yet merged
    /// upstream. The evidence for each body is in zgrimz/fujifilm-ptp-reference
    /// `docs/07-cameras.md#summary`.
    case community
    /// Enabled because it shares its processor and PTP protocol with a body that was verified. A
    /// reasonable inference, and still an inference.
    case inferred

    /// What the push screen tells the user before a write to a trusted entry; a body granted on its
    /// walk gets `WritePermission.Grounds.pushCaveat` instead. Only `.inferred` carries one: nobody
    /// has reported a write to that body anywhere, and a shared processor has failed to predict the
    /// bank path before (the X-Pro3). For the other levels somebody has, and the push's own backup
    /// and read-back cover what remains.
    var pushCaveat: String? {
        guard self == .inferred else { return nil }
        return "Writing is on because this camera shares its processor and protocol with cameras that have been tested. Darkslide records exactly what the slot held before it writes, and tells you exactly what landed."
    }

    /// What the Camera Test tells a tester about the evidence their report adds to. Nil for
    /// `.hardware`, which a tester's report can't move.
    var testerNote: String? {
        switch self {
        case .hardware:
            return nil
        case .ownerReport:
            return "This camera was checked end to end by one of its owners — written to, switched off and on, and compared against the camera's own menu — but it hasn't been tested on hardware here. Darkslide records exactly what the slot held before it writes, and tells you exactly what landed."
        case .community:
            return "This camera is listed as working by other owners, but no report from Darkslide has confirmed it and it hasn't been tested on hardware here. Darkslide records exactly what the slot held before it writes, and tells you exactly what landed."
        case .inferred:
            return "This camera hasn't been tested on hardware — it's enabled because it shares its processor and protocol with bodies that were. Darkslide records exactly what the slot held before it writes, and tells you exactly what landed."
        }
    }

    /// The word the compatibility report carries, so two testers' reports are comparable.
    var reportLabel: String {
        switch self {
        case .hardware: return "hardware"
        case .ownerReport: return "owner-report"
        case .community: return "community"
        case .inferred: return "inferred"
        }
    }
}

/// Product-level capabilities of a camera model: which fields exist, their ranges, slot count, and
/// slot-naming support. Property codes and their byte encodings live in the camera layer
/// (`FujiPTP`, `FujiEncoding`, `FujiPresetCodec`).
struct CameraModel: Identifiable, Hashable {
    /// Stable identifier used in JSON `authoredForModel` and for registry lookup, e.g. "X100V".
    let id: String
    let displayName: String
    let sensorGeneration: SensorGeneration
    let processor: ProcessorGeneration

    /// Whether the registry expects this body to expose the USB slot protocol (`0xD18C` selector /
    /// `0xD18D` name).
    ///
    /// Its own axis, deliberately separate from ``writeSupport``: that says whether the app may
    /// *write* a slot, this says whether the registry expects slots to be reachable over USB. On a
    /// `.blocked` entry, `false` means the app never writes `0xD18C` to the body: it does not probe
    /// a camera with an operation the record shows refused, and it does not then present that
    /// refusal to the user as a failure. On an `.untested` entry it is an expectation the connect
    /// checks against what the selector answers (`SlotReader.refresh`); a body that answers a bank
    /// number is walked. On some bodies the expectation is measured, on others inferred; the
    /// registry says which.
    ///
    /// An owner's X-T20 at fw 2.01 answers a direct read with `0x200A DeviceProp Not Supported`
    /// (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#x-t20`).
    let supportsSlotProtocol: Bool

    /// Number of custom slots (C1 … C{slotCount}). Varies by body. Only meaningful where
    /// ``supportsSlotProtocol`` — a body without it has no slots to count, and the registry's
    /// assumption is kept rather than zeroed so a report can say what was assumed.
    let slotCount: Int

    /// What Fujifilm's own manual says the body has (2026-09-16 sweep of every model's
    /// EDIT/SAVE CUSTOM SETTING page); nil where the sweep found no entry or didn't cover the
    /// body. **Not** the walk's ceiling —
    /// that is ``slotCount``, and it is deliberately left at the registry's assumption even where
    /// this is lower, because the connect walk stops at the first refused select and can only ever
    /// find fewer banks than it tries. This number is what the walk's result is *read against*:
    /// a refusal exactly here is the manual confirmed, a refusal short of it is a finding, and a
    /// walk that runs past it is the USB protocol exposing banks the menu does not — which a lowered
    /// ``slotCount`` would have hidden forever.
    let documentedSlotCount: Int?

    let supportedFields: Set<RecipeField>
    let supportedFilmSimulations: [FilmSimulation]
    /// The modes the body's WHITE BALANCE menu lists [Published: Fujifilm manuals]: the presets
    /// and Auto on every body, Kelvin and Underwater on all but the X-M1, and Auto (White Priority)
    /// and Auto (Ambience Priority) only where a manual prints them — the X-T4 and later, not the
    /// X-Pro3 or X100V. A measured custom white balance is a per-camera reading, not a recipe
    /// value, so it is not a mode here.
    let supportedWhiteBalanceModes: Set<WhiteBalanceMode>
    let ranges: [RecipeField: NumericRange]

    /// Whether Monochromatic Color has its magenta–green axis (`0xD194`) as well as warm–cool.
    /// A per-body fact from Fujifilm's manuals, not a processor rule: every body with the control
    /// has both axes except the X-T3 and X-T30, whose manuals print a single −9…+9 table, and a
    /// GFX100 before firmware 4.00 (zgrimz/fujifilm-ptp-reference `docs/03-encodings.md`).
    /// Meaningless where `.monochromaticColor` is not in ``supportedFields``; every rule asks
    /// `RecipeApplicability.bodyProvides` first.
    let hasMagentaGreenAxis: Bool

    /// Whether the body has a grain *size* control as well as strength (`0xD195` folds both into
    /// one composite; see `FujiEncoding.grainToFlat`). A per-body fact from Fujifilm's manuals, not
    /// a processor rule: the X-Processor Pro bodies have strength only, and so do the X-T3 and
    /// X-T30, X-Processor 4 bodies whose GRAIN EFFECT menu is Strong / Weak / Off alone
    /// [Published: Fujifilm manuals, X-T3 and X-T30 image quality setting pages]. Every later body
    /// with the control has both. `RecipeApplicability.hasGrainSizeControl` reads this.
    let hasGrainSizeControl: Bool

    /// Slot-name writing. When `false` the push silently skips the name write — never an
    /// error.
    let supportsSlotNaming: Bool
    let slotNameMaxLength: Int
    /// Characters the camera permits in a slot name; others are stripped before writing.
    let slotNameAllowedCharacters: CharacterSet

    let writeSupport: WriteSupport

    /// How firmly the write path is known to work on this body. Only meaningful where
    /// `writeSupport` is `.readWrite`; a `.blocked` entry carries its reason instead.
    let verification: VerificationLevel

    /// Whether the app may drive **in-camera RAW conversion** (the Kitchen feature) on this body.
    /// This is its own allowlist gate, separate from `writeSupport`: conversion uses a different,
    /// reverse-engineered PTP path (the `0xD185` profile + object transfer) that must be verified on
    /// each body before it's trusted — `true` for the Demo Camera, which round-trips the app's own
    /// `FujiRawConvProfile` codec. For real bodies it is an opt-in the registry grants a group at a
    /// time on shared architecture (with Fujifilm's own USB conversion support and published
    /// third-party conversions behind the X-Trans III group), or a single body on its own `0xD185`
    /// blob: the X-T50, driven end to end here, and the GFX100S, on its owner's harvested profile
    /// (fw 2.13; zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#gfx100s`).
    let supportsRawConversion: Bool

    /// Bodies with a physical Film Simulation dial (e.g. X-T50, X-E5). When the dial is on a named
    /// simulation it **overrides** a pushed film simulation — the user must set it to "C" (Custom)
    /// before a push, or the base film sim won't take.
    let hasFilmSimulationDial: Bool

    // MARK: Convenience

    static func == (lhs: CameraModel, rhs: CameraModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var allowsWrite: Bool { writeSupport.allowsWrite }

    func supports(_ field: RecipeField) -> Bool { supportedFields.contains(field) }

    func range(for field: RecipeField) -> NumericRange? { ranges[field] }

    func supports(filmSimulation: FilmSimulation) -> Bool {
        supportedFilmSimulations.contains(filmSimulation)
    }

    func supports(whiteBalanceMode mode: WhiteBalanceMode) -> Bool {
        supportedWhiteBalanceModes.contains(mode)
    }

    /// Slot labels "C1" … "C{slotCount}".
    var slotLabels: [String] { (1...max(1, slotCount)).map { "C\($0)" } }

    /// Sanitize + truncate a recipe name to what this camera will actually store.
    ///
    /// The per-model guard at the wire. `CameraSlotName` is the rule recipes are generated against,
    /// so for a body on the current limits this is a no-op; it stays per-model because a body with a
    /// different limit is exactly the thing the registry exists to express, and because a legacy
    /// `cameraName` typed before the limits existed reaches here unclamped.
    ///
    /// It folds accents as `CameraSlotName` does, but leaves spacing alone: a restore sends a name
    /// the camera gave through here, and collapsing its spaces would rename the bank.
    ///
    /// Never returns an empty string, because a push names the bank it writes (the product rule
    /// `testNoWritableBodyHasSlotNamingOff` pins). An empty `0xD18D` would clear the bank's name
    /// instead, and the camera would list it as CUSTOM *n*. A restore of a bank that had no name is
    /// the one write of an empty name, and it doesn't come through here. The name is not what makes
    /// a push persist (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md`).
    func sanitizedSlotName(from name: String) -> String {
        let folded = CameraSlotName.foldingDiacritics(name)
        let filtered = folded.unicodeScalars.filter { slotNameAllowedCharacters.contains($0) }
        var cleaned = String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: .whitespaces)
        if cleaned.count > slotNameMaxLength {
            cleaned = String(cleaned.prefix(slotNameMaxLength)).trimmingCharacters(in: .whitespaces)
        }
        return cleaned.isEmpty ? CameraSlotName.fallbackName : cleaned
    }
}
