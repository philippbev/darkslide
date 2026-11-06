import Foundation

/// How the user chose to handle an incoming recipe that looks like one already in the inventory.
/// Shared by JSON import and camera import.
enum DuplicateResolution: String, CaseIterable, Identifiable {
    case skip
    case keepBoth
    case overwrite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skip: return "Skip"
        case .keepBoth: return "Keep Both"
        case .overwrite: return "Overwrite"
        }
    }
}

/// A detected potential duplicate: the incoming recipe and the existing inventory item it matches.
struct DuplicateMatch: Identifiable {
    let id = UUID()
    let incoming: PortableRecipe
    let existing: Recipe
    /// Why we think it's a duplicate, for display.
    let reason: Reason

    enum Reason {
        case sameName
        case identicalSettings
        case sameNameAndSettings

        var description: String {
            switch self {
            case .sameName: return "Same name as an existing recipe"
            case .identicalSettings: return "Identical settings to an existing recipe"
            case .sameNameAndSettings: return "Same name and identical settings"
            }
        }
    }
}

/// Detects likely duplicates so the importer can prompt the user.
enum DuplicateResolver {

    /// Returns the best matching existing recipe for `incoming`, or nil if it looks new.
    static func match(for incoming: PortableRecipe, in existing: [Recipe]) -> DuplicateMatch? {
        let incomingKey = RecipeImporter.nameKey(incoming.name)

        var nameOnly: Recipe?
        for candidate in existing {
            let sameName = RecipeImporter.nameKey(candidate.name) == incomingKey
            let sameSettings = candidate.settings == incoming.settings
            switch (sameName, sameSettings) {
            case (true, true):
                return DuplicateMatch(incoming: incoming, existing: candidate, reason: .sameNameAndSettings)
            case (false, true):
                return DuplicateMatch(incoming: incoming, existing: candidate, reason: .identicalSettings)
            case (true, false):
                if nameOnly == nil { nameOnly = candidate }
            case (false, false):
                continue
            }
        }
        if let nameOnly {
            return DuplicateMatch(incoming: incoming, existing: nameOnly, reason: .sameName)
        }
        return nil
    }
}
