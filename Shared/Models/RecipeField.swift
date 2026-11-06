import Foundation

/// An identifier for every editable recipe parameter.
///
/// Used to drive (a) which fields the editor shows for a given camera, (b) per-model "this body
/// will ignore X" flags, and (c) the pre-push warning that lists unsupported fields and how
/// they'll be handled.
enum RecipeField: String, CaseIterable, Codable, Hashable, Identifiable {
    case filmSimulation
    case monochromaticColor
    case grain
    case colorChromeEffect
    case colorChromeFXBlue
    case whiteBalance
    case dynamicRange
    case dRangePriority
    case highlightTone
    case shadowTone
    case color
    case sharpness
    case highISONR
    case clarity
    case exposureBias
    case noiseReduction

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .filmSimulation: return "Film Simulation"
        case .monochromaticColor: return "Monochromatic Color"
        case .grain: return "Grain Effect"
        case .colorChromeEffect: return "Color Chrome Effect"
        case .colorChromeFXBlue: return "Color Chrome FX Blue"
        case .whiteBalance: return "White Balance"
        case .dynamicRange: return "Dynamic Range"
        case .dRangePriority: return "D-Range Priority"
        case .highlightTone: return "Highlight Tone"
        case .shadowTone: return "Shadow Tone"
        case .color: return "Color"
        case .sharpness: return "Sharpness"
        case .highISONR: return "High ISO NR"
        case .clarity: return "Clarity"
        case .exposureBias: return "Exposure Bias"
        case .noiseReduction: return "Noise Reduction"
        }
    }
}
