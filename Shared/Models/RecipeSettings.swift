import Foundation

/// The camera-parameter payload of a recipe — a "superset" model that can represent recipes
/// across supported camera generations.
///
/// Every field is **optional**: `nil` means "not set / not part of this recipe". Which fields
/// are *applicable* and their valid ranges are decided per camera by `CameraModel`, so fields that
/// exist on some bodies and not others are represented gracefully.
///
/// This is the app's own model, deliberately decoupled from any camera's internal byte encoding.
/// `CodingKeys` are the stable, documented JSON field names.
struct RecipeSettings: Codable, Equatable, Hashable {
    var filmSimulation: FilmSimulation?

    /// Monochromatic Color, monochrome sims only. Warm–Cool and (newer bodies) Magenta–Green axes.
    var monochromaticColorWC: Int?
    var monochromaticColorMG: Int?

    var grain: GrainEffect?
    var colorChromeEffect: EffectStrength?
    var colorChromeFXBlue: EffectStrength?

    var whiteBalance: WhiteBalance?

    var dynamicRange: DynamicRange?
    var dRangePriority: DRangePriority?

    // Numeric settings hold the camera menu's values. Each body's range and step come from its
    // `CameraModel` (`range(for:)`). The tones are `Double` because some bodies step them in halves.
    var highlightTone: Double?
    var shadowTone: Double?
    /// Saturation. Not applicable to monochrome simulations.
    var color: Int?
    var sharpness: Int?
    var highISONR: Int?
    var clarity: Int?
    /// In EV. A shooting suggestion rather than a bank setting: it is in no body's field set, so a
    /// push never writes it.
    var exposureBias: Double?
    /// Noise Reduction, the name bodies up to the X-T3 give High ISO NR (Fujifilm X-T3 manual,
    /// image quality settings). The camera setting is `highISONR` (`0xD1A1` in
    /// zgrimz/fujifilm-ptp-reference `docs/02-properties.md`), so a push never writes this field,
    /// and a value arriving without a `highISONR` becomes one: both initialisers fold it, which is
    /// why it is `private(set)`. It stays only beside a `highISONR` — a recipe that listed both
    /// names — where neither value is dropped.
    private(set) var noiseReduction: Int?

    init(filmSimulation: FilmSimulation? = nil,
         monochromaticColorWC: Int? = nil,
         monochromaticColorMG: Int? = nil,
         grain: GrainEffect? = nil,
         colorChromeEffect: EffectStrength? = nil,
         colorChromeFXBlue: EffectStrength? = nil,
         whiteBalance: WhiteBalance? = nil,
         dynamicRange: DynamicRange? = nil,
         dRangePriority: DRangePriority? = nil,
         highlightTone: Double? = nil,
         shadowTone: Double? = nil,
         color: Int? = nil,
         sharpness: Int? = nil,
         highISONR: Int? = nil,
         clarity: Int? = nil,
         exposureBias: Double? = nil,
         noiseReduction: Int? = nil) {
        self.filmSimulation = filmSimulation
        self.monochromaticColorWC = monochromaticColorWC
        self.monochromaticColorMG = monochromaticColorMG
        self.grain = grain
        self.colorChromeEffect = colorChromeEffect
        self.colorChromeFXBlue = colorChromeFXBlue
        self.whiteBalance = whiteBalance
        self.dynamicRange = dynamicRange
        self.dRangePriority = dRangePriority
        self.highlightTone = highlightTone
        self.shadowTone = shadowTone
        self.color = color
        self.sharpness = sharpness
        self.highISONR = highISONR
        self.clarity = clarity
        self.exposureBias = exposureBias
        self.noiseReduction = noiseReduction
        foldLegacyNoiseReduction()
    }

    /// See ``noiseReduction``.
    private mutating func foldLegacyNoiseReduction() {
        guard highISONR == nil, let legacy = noiseReduction else { return }
        highISONR = legacy
        noiseReduction = nil
    }

    /// Decoding is spelled out because SwiftData persists this struct as a *composite attribute*:
    /// it flattens the nested `GrainEffect` / `WhiteBalance` into sibling columns and keeps no
    /// marker for "the nested struct itself was nil". A recipe saved with `grain == nil` (the AI
    /// screenshot scanner of earlier builds and the editor both produce that — see
    /// `RecipeDraft.assembleSettings`) therefore reads back as a *present* grain with every column
    /// null. A synthesized decoder throws on that, on every launch, for as long as such a recipe is
    /// in the library.
    ///
    /// So the presence of the one non-optional discriminator (`strength` / `mode`) is what decides
    /// whether the nested value was really stored. Everything else decodes exactly as a
    /// synthesized decoder would: absent key → nil.
    ///
    /// Enum fields go one step further: a raw value this version doesn't model also reads as nil
    /// (see `decodeIfKnown(_:forKey:)`), so a recipe written by a newer build, arriving over iCloud
    /// sync, in a shared file or after a downgrade, opens with that one setting unset.
    ///
    /// A `noiseReduction` stored without a `highISONR` reads as the latter; see ``noiseReduction``.
    init(from decoder: any Decoder) throws {
        // A throw from here is permanent, not transient: SwiftData stops the app with "Failed to
        // decode a composite attribute" (iOS 27 Simulator, 2026-10-20), and the recipe is already
        // in the store, so it happens again every time the recipe is fetched. An enum value this
        // version doesn't model never throws; a value of the wrong type still does. The log line is
        // the only record of which field failed. The key name is one of `CodingKeys`, a
        // compile-time constant; no stored value reaches the log.
        do {
            try self.init(decoding: decoder)
        } catch let error as DecodingError {
            let field = Self.failedKey(from: error)
            AppLog.error(.data, "A stored recipe wouldn't decode — field \(field)")
            throw error
        }
    }

    /// The key a `DecodingError` names, or a coarse label when it names none. Only ever a
    /// `CodingKeys` case, so this can't carry a stored value out of the store.
    private static func failedKey(from error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return key.stringValue
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return context.codingPath.last?.stringValue ?? "unknown"
        case .dataCorrupted(let context):
            return context.codingPath.last?.stringValue ?? "data_corrupted"
        @unknown default: return "unknown"
        }
    }

    private init(decoding decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filmSimulation = try container.decodeIfKnown(FilmSimulation.self, forKey: .filmSimulation)
        monochromaticColorWC = try container.decodeIfPresent(Int.self, forKey: .monochromaticColorWC)
        monochromaticColorMG = try container.decodeIfPresent(Int.self, forKey: .monochromaticColorMG)
        grain = try container.decodeIfPresent(StoredGrain.self, forKey: .grain)?.value
        colorChromeEffect = try container.decodeIfKnown(EffectStrength.self, forKey: .colorChromeEffect)
        colorChromeFXBlue = try container.decodeIfKnown(EffectStrength.self, forKey: .colorChromeFXBlue)
        whiteBalance = try container.decodeIfPresent(StoredWhiteBalance.self, forKey: .whiteBalance)?.value
        dynamicRange = try container.decodeIfKnown(DynamicRange.self, forKey: .dynamicRange)
        dRangePriority = try container.decodeIfKnown(DRangePriority.self, forKey: .dRangePriority)
        highlightTone = try container.decodeIfPresent(Double.self, forKey: .highlightTone)
        shadowTone = try container.decodeIfPresent(Double.self, forKey: .shadowTone)
        color = try container.decodeIfPresent(Int.self, forKey: .color)
        sharpness = try container.decodeIfPresent(Int.self, forKey: .sharpness)
        highISONR = try container.decodeIfPresent(Int.self, forKey: .highISONR)
        clarity = try container.decodeIfPresent(Int.self, forKey: .clarity)
        exposureBias = try container.decodeIfPresent(Double.self, forKey: .exposureBias)
        noiseReduction = try container.decodeIfPresent(Int.self, forKey: .noiseReduction)
        foldLegacyNoiseReduction()
    }

    /// A neutral starting point for a new recipe.
    static let neutral = RecipeSettings(
        filmSimulation: .provia,
        grain: .off,
        colorChromeEffect: .off,
        colorChromeFXBlue: .off,
        whiteBalance: .auto,
        dynamicRange: .auto,
        highlightTone: 0,
        shadowTone: 0,
        color: 0,
        sharpness: 0,
        highISONR: 0,
        clarity: 0,
        exposureBias: 0
    )
}

// MARK: - Nested-value decoding

/// Decodes a stored `GrainEffect`, yielding nil when the composite carried no data at all.
///
/// `strength` is the discriminator: a real grain always has one (even "Off"), so its absence means
/// the recipe simply has no grain setting rather than a grain of Off. A strength this version
/// doesn't model means the same: a size alone states no grain, so the recipe has no grain setting.
/// A size this version doesn't model reads like an absent one, and the grain keeps its strength.
private struct StoredGrain: Decodable {
    let value: GrainEffect?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: GrainEffect.CodingKeys.self)
        guard let strength = try container.decodeIfKnown(GrainStrength.self, forKey: .strength) else {
            value = nil
            return
        }
        value = GrainEffect(strength: strength,
                            size: try container.decodeIfKnown(GrainSize.self, forKey: .size))
    }
}

/// The `WhiteBalance` counterpart of `StoredGrain`, discriminated on `mode`. A mode this version
/// doesn't model (the retired `CUSTOM_1`…`CUSTOM_3`, or a newer build's) means no white balance:
/// the shifts and Kelvin only mean something under a mode.
private struct StoredWhiteBalance: Decodable {
    let value: WhiteBalance?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: WhiteBalance.CodingKeys.self)
        guard let mode = try container.decodeIfKnown(WhiteBalanceMode.self, forKey: .mode) else {
            value = nil
            return
        }
        value = WhiteBalance(mode: mode,
                             shiftRed: try container.decodeIfPresent(Int.self, forKey: .shiftRed) ?? 0,
                             shiftBlue: try container.decodeIfPresent(Int.self, forKey: .shiftBlue) ?? 0,
                             kelvin: try container.decodeIfPresent(Int.self, forKey: .kelvin))
    }
}

// MARK: - Enum decoding

/// A stored enum by raw value, read through the single-value path the enum itself decodes with —
/// the one SwiftData's composite decoder supports. That decoder doesn't hand an enum-typed key back
/// as a `String`, so reading the key as one passes every JSON test and crashes at launch.
private enum StoredEnum<Value: RawRepresentable<String>>: Decodable {
    case known(Value)
    /// A raw value this version doesn't model: a newer build's, or one this version retired.
    case unknown

    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Value(rawValue: rawValue).map { .known($0) } ?? .unknown
    }
}

private extension KeyedDecodingContainer {
    /// The enum stored under `key`, or nil when the key is absent or holds a raw value this version
    /// doesn't model. Only a value of the wrong type throws.
    ///
    /// An unknown value comes from a newer build or names a retired case. Once a newer build's value
    /// is in someone's library, no change to an older build can make it readable, so reading it as
    /// unset is what keeps the rest of the recipe. The dropped value is logged by field name only:
    /// the value itself is the user's.
    func decodeIfKnown<Value: RawRepresentable<String>>(_ type: Value.Type, forKey key: Key) throws -> Value? {
        switch try decodeIfPresent(StoredEnum<Value>.self, forKey: key) {
        case .known(let value):
            return value
        case .unknown:
            AppLog.error(.data, "A recipe value this version doesn't model reads as not set — field \(key.stringValue)")
            return nil
        case nil:
            return nil
        }
    }
}
