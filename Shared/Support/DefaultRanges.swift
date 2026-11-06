import Foundation

/// Each numeric field's range across every supported body: what the editor offers under Generic
/// (no camera selected), and the bounds of the Share Extension's editor and the AI recipe schema.
enum DefaultRanges {
    static func range(for field: RecipeField) -> NumericRange {
        switch field {
        case .highlightTone, .shadowTone: return NumericRange(min: -2, max: 4, step: 0.5)
        case .color, .sharpness, .highISONR: return NumericRange(min: -4, max: 4, step: 1)
        case .clarity: return NumericRange(min: -5, max: 5, step: 1)
        case .monochromaticColor: return NumericRange(min: -18, max: 18, step: 1)
        default: return NumericRange(min: -4, max: 4, step: 1)
        }
    }
}
