import Foundation
import SwiftData

/// A saved set of AI recipe recommendations, so the user can refer back to past results without
/// re-sending the query. Picks reference library recipes by their stable `Recipe.uuid` (the same
/// pattern as ``Chapter``), so a result degrades gracefully when a recommended recipe is later
/// deleted — the row simply shows as missing.
///
/// Defaults on every attribute satisfy CloudKit's optional-or-defaulted rule; `init` sets real values.
@Model
final class Recommendation {
    var uuid: UUID = UUID()
    /// The user's shooting brief, verbatim. Empty when the pinned recipes were the whole request.
    var prompt: String = ""
    /// The model's short name for the set, e.g. "Kyoto in Autumn".
    var title: String = ""
    /// The model's 1–2 sentence overview of how the set works together.
    var summary: String?
    /// The model id that produced this set (provenance, shown in the result view). Resolved for
    /// display through ``AIModelCatalog``, which searches every provider.
    var modelID: String = ""
    var createdAt: Date = Date()
    /// Encoded `[RecipePick]`.
    var picksData: Data = Data()

    /// How many slots this request asked to fill (C1–C`slotTarget`).
    var slotTarget: Int = Chapter.maxSlots
    /// Situations the plans called for that the library couldn't cover, in the model's words.
    var gaps: [String] = []
    /// The chapter this request was launched from, if any — lets the result write back to it.
    /// A plain uuid (not a relationship) so deleting the chapter just makes the offer disappear.
    var sourceChapterUUID: UUID?

    init(prompt: String, title: String, summary: String?, modelID: String,
         picks: [RecipePick], slotTarget: Int = Chapter.maxSlots, gaps: [String] = [],
         sourceChapterUUID: UUID? = nil, createdAt: Date = Date()) {
        self.uuid = UUID()
        self.prompt = prompt
        self.title = title
        self.summary = summary
        self.modelID = modelID
        self.createdAt = createdAt
        self.picksData = (try? JSONEncoder().encode(picks)) ?? Data()
        self.slotTarget = slotTarget
        self.gaps = gaps
        self.sourceChapterUUID = sourceChapterUUID
    }

    var picks: [RecipePick] {
        (try? JSONDecoder().decode([RecipePick].self, from: picksData)) ?? []
    }
}

extension Recommendation {
    /// The picks the user pinned before asking, in slot order.
    var anchoredPicks: [RecipePick] { picks.filter(\.isAnchor) }

    /// The picks the model added to complement them.
    var addedPicks: [RecipePick] { picks.filter { !$0.isAnchor } }

    /// True when this set was built around recipes the user chose first.
    var wasBuiltAroundAnchors: Bool { picks.contains(where: \.isAnchor) }
}
