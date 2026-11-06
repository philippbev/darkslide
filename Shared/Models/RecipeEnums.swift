import Foundation

// MARK: - Display protocol

/// A recipe-parameter enum that knows how to present itself in the UI.
/// All raw values are **stable JSON strings**: documented, and not tied to one camera model's
/// internal encoding.
protocol RecipeOption: RawRepresentable, CaseIterable, Codable, Hashable, Identifiable where RawValue == String {
    var displayName: String { get }
}

extension RecipeOption {
    var id: String { rawValue }
}

// MARK: - Film simulation

/// Base film simulation. Monochrome variants (ACROS / MONOCHROME with filters, SEPIA) are
/// represented as distinct cases so a recipe round-trips exactly. `isMonochrome` drives the
/// editor (monochrome sims hide Color and expose Monochromatic Color, because a monochrome
/// simulation rejects color writes).
enum FilmSimulation: String, RecipeOption {
    case provia = "PROVIA"
    case velvia = "VELVIA"
    case astia = "ASTIA"
    case classicChrome = "CLASSIC_CHROME"
    case proNegHi = "PRO_NEG_HI"
    case proNegStd = "PRO_NEG_STD"
    case classicNeg = "CLASSIC_NEG"
    case nostalgicNeg = "NOSTALGIC_NEG"
    case eterna = "ETERNA"
    case eternaBleachBypass = "ETERNA_BLEACH_BYPASS"
    case realaAce = "REALA_ACE"
    case acros = "ACROS"
    case acrosYe = "ACROS_Ye"
    case acrosR = "ACROS_R"
    case acrosG = "ACROS_G"
    case monochrome = "MONOCHROME"
    case monochromeYe = "MONOCHROME_Ye"
    case monochromeR = "MONOCHROME_R"
    case monochromeG = "MONOCHROME_G"
    case sepia = "SEPIA"

    var displayName: String {
        switch self {
        case .provia: return "PROVIA / Standard"
        case .velvia: return "Velvia / Vivid"
        case .astia: return "ASTIA / Soft"
        case .classicChrome: return "Classic Chrome"
        case .proNegHi: return "PRO Neg. Hi"
        case .proNegStd: return "PRO Neg. Std"
        case .classicNeg: return "Classic Neg."
        case .nostalgicNeg: return "Nostalgic Neg."
        case .eterna: return "ETERNA / Cinema"
        case .eternaBleachBypass: return "ETERNA Bleach Bypass"
        case .realaAce: return "REALA ACE"
        case .acros: return "ACROS"
        case .acrosYe: return "ACROS + Ye Filter"
        case .acrosR: return "ACROS + R Filter"
        case .acrosG: return "ACROS + G Filter"
        case .monochrome: return "Monochrome"
        case .monochromeYe: return "Monochrome + Ye Filter"
        case .monochromeR: return "Monochrome + R Filter"
        case .monochromeG: return "Monochrome + G Filter"
        case .sepia: return "Sepia"
        }
    }

    /// Monochrome family: Color (saturation) is not applicable.
    ///
    /// This answers one question, not two. Sepia is in this family and still has no adjustable
    /// toning — see ``hasMonochromaticColor``, which is the narrower set.
    var isMonochrome: Bool {
        switch self {
        case .acros, .acrosYe, .acrosR, .acrosG,
             .monochrome, .monochromeYe, .monochromeR, .monochromeG, .sepia:
            return true
        default:
            return false
        }
    }

    /// Whether this simulation exposes the Monochromatic Color warm–cool and magenta–green axes.
    ///
    /// The monochrome family minus Sepia. Sepia is already toned: a Sepia bank's menu on an X-T50
    /// offers neither Color nor Monochromatic Color (observed 2026-09-20), and the body refuses
    /// every tested toning write (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md`). ``isMonochrome`` alone would have
    /// the app offering a toning control the body doesn't show, and the push writing
    /// `0xD193`/`0xD194` values the camera refuses.
    ///
    /// Written as the family minus Sepia rather than as a second case list, so a monochrome
    /// variant added to ``isMonochrome`` gets its toning here without a second edit.
    var hasMonochromaticColor: Bool { isMonochrome && self != .sepia }
}

// MARK: - Generic three-level effect strength

enum EffectStrength: String, RecipeOption {
    case off = "OFF"
    case weak = "WEAK"
    case strong = "STRONG"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .weak: return "Weak"
        case .strong: return "Strong"
        }
    }
}

// MARK: - Grain

enum GrainStrength: String, RecipeOption {
    case off = "OFF"
    case weak = "WEAK"
    case strong = "STRONG"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .weak: return "Weak"
        case .strong: return "Strong"
        }
    }
}

enum GrainSize: String, RecipeOption {
    case small = "SMALL"
    case large = "LARGE"

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .large: return "Large"
        }
    }
}

/// Grain effect. `size` is nil on bodies with strength-only grain, and when the stored size isn't
/// one this version models.
struct GrainEffect: Codable, Equatable, Hashable {
    var strength: GrainStrength
    var size: GrainSize?

    static let off = GrainEffect(strength: .off, size: nil)

    /// Spelled out (rather than synthesized) so `StoredGrain` can inspect the stored keys itself
    /// to tell "no grain was stored" from "grain is Off" — see `RecipeSettings.init(from:)`.
    enum CodingKeys: String, CodingKey { case strength, size }

    init(strength: GrainStrength, size: GrainSize?) {
        self.strength = strength
        self.size = size
    }
}

// MARK: - White balance

enum WhiteBalanceMode: String, RecipeOption {
    case auto = "AUTO"
    case autoWhitePriority = "AUTO_WHITE_PRIORITY"
    case autoAmbiencePriority = "AUTO_AMBIENCE_PRIORITY"
    case daylight = "DAYLIGHT"
    case shade = "SHADE"
    case fluorescent1 = "FLUORESCENT_1"
    case fluorescent2 = "FLUORESCENT_2"
    case fluorescent3 = "FLUORESCENT_3"
    case incandescent = "INCANDESCENT"
    case underwater = "UNDERWATER"
    case kelvin = "KELVIN"

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .autoWhitePriority: return "Auto (White Priority)"
        case .autoAmbiencePriority: return "Auto (Ambience Priority)"
        case .daylight: return "Daylight"
        case .shade: return "Shade"
        case .fluorescent1: return "Fluorescent 1"
        case .fluorescent2: return "Fluorescent 2"
        case .fluorescent3: return "Fluorescent 3"
        case .incandescent: return "Incandescent"
        case .underwater: return "Underwater"
        case .kelvin: return "Color Temperature (K)"
        }
    }

    /// Whether a Kelvin value applies: only in Color Temperature mode. Writers select that mode
    /// before writing Kelvin (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md`).
    var usesKelvin: Bool { self == .kelvin }
}

/// White balance + R/B fine-shift (+ Kelvin when in Color Temperature mode).
struct WhiteBalance: Codable, Equatable, Hashable {
    var mode: WhiteBalanceMode
    var shiftRed: Int      // Red–Cyan axis
    var shiftBlue: Int     // Blue–Amber axis
    var kelvin: Int?       // only meaningful when mode == .kelvin

    static let auto = WhiteBalance(mode: .auto, shiftRed: 0, shiftBlue: 0, kelvin: nil)

    /// Spelled out for the same reason as `GrainEffect.CodingKeys`.
    enum CodingKeys: String, CodingKey { case mode, shiftRed, shiftBlue, kelvin }

    init(mode: WhiteBalanceMode, shiftRed: Int, shiftBlue: Int, kelvin: Int?) {
        self.mode = mode
        self.shiftRed = shiftRed
        self.shiftBlue = shiftBlue
        self.kelvin = kelvin
    }
}

// MARK: - Dynamic range

enum DynamicRange: String, RecipeOption {
    case auto = "DR_AUTO"
    case dr100 = "DR100"
    case dr200 = "DR200"
    case dr400 = "DR400"

    var displayName: String {
        switch self {
        case .auto: return "DR Auto"
        case .dr100: return "DR100"
        case .dr200: return "DR200"
        case .dr400: return "DR400"
        }
    }
}

enum DRangePriority: String, RecipeOption {
    case off = "OFF"
    case auto = "AUTO"
    case weak = "WEAK"
    case strong = "STRONG"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .auto: return "Auto"
        case .weak: return "Weak"
        case .strong: return "Strong"
        }
    }
}

