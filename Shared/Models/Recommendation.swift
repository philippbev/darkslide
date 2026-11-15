import Foundation
import SwiftData

/// A saved set of recipe recommendations from the removed Ideas feature.
///
/// Nothing creates or shows these any more. The model stays in ``SharedModelStore/modelTypes`` only
/// so the store and its CloudKit schema keep the shape existing installs already have: dropping an
/// entity is a migration, and rows an older build saved should not stop the store from opening.
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
    /// The model id that produced this set (provenance).
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
