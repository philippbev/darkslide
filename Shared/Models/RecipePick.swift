import Foundation

/// Part of the removed Ideas feature, kept for ``Recommendation``'s stored data. One recommended
/// library recipe: the recipe's stable identity, the shooting situation it covers in
/// this set, and the model's one-line reason it earns a slot. Codable so a whole recommendation persists
/// verbatim (see ``Recommendation``); referencing by `Recipe.uuid` (like ``Chapter``) means a result
/// degrades gracefully if the recipe is later deleted.
struct RecipePick: Codable, Identifiable {
    var id = UUID()
    var recipeUUID: UUID
    var reason: String?
    /// Short label for the situation this recipe covers in the set, e.g. "Overcast & rain".
    var role: String?
    /// True when the user pinned this recipe and the model was required to keep it.
    var isAnchor: Bool = false

    init(id: UUID = UUID(), recipeUUID: UUID, reason: String? = nil,
         role: String? = nil, isAnchor: Bool = false) {
        self.id = id
        self.recipeUUID = recipeUUID
        self.reason = reason
        self.role = role
        self.isAnchor = isAnchor
    }

    private enum CodingKeys: String, CodingKey { case id, recipeUUID, reason, role, isAnchor }

    /// Decoded leniently so recommendations saved before `role`/`isAnchor` existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        recipeUUID = try container.decode(UUID.self, forKey: .recipeUUID)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        isAnchor = try container.decodeIfPresent(Bool.self, forKey: .isAnchor) ?? false
    }
}
