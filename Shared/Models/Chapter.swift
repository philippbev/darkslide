import Foundation
import SwiftData

/// An ordered collection of up to seven recipes that maps onto the camera's custom slots
/// (C1–C{maxSlots}). A Chapter is the unit the user can **save** and **push as a whole** to the
/// camera in one session — recipe[0] → C1, recipe[1] → C2, and so on.
///
/// Recipes are referenced by their stable `Recipe.uuid` (not a SwiftData relationship) so the
/// ordering is explicit and a Chapter degrades gracefully if a referenced recipe is later deleted
/// (the slot is simply shown as missing and skipped on push).
@Model
final class Chapter {
    /// The most custom banks any supported body has (C1–C7). Some bodies have fewer; see
    /// `slotsBeyond(_:)`.
    static let maxSlots = 7

    /// Not `.unique` (CloudKit forbids unique constraints). Defaults satisfy CloudKit's rule that
    /// every attribute be optional or defaulted; `init` sets real values.
    var uuid: UUID = UUID()
    var name: String = ""

    /// Ordered recipe identities. Position `i` maps to camera slot `C{i+1}`. At most `maxSlots`.
    var recipeUUIDs: [UUID] = []

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(uuid: UUID = UUID(),
         name: String,
         recipeUUIDs: [UUID] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.uuid = uuid
        self.name = name
        self.recipeUUIDs = recipeUUIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Chapter {
    /// True when another recipe can still be added.
    var hasFreeSlot: Bool { recipeUUIDs.count < Chapter.maxSlots }

    /// slot index (1-based) → recipe uuid, for handing straight to the push flow.
    var slotAssignments: [Int: UUID] {
        Dictionary(uniqueKeysWithValues: recipeUUIDs.enumerated().map { ($0.offset + 1, $0.element) })
    }

    /// The slots (1-based) a push to a body with `slotCount` banks leaves behind: an X-M5 has four,
    /// so a seven-recipe chapter loses C5–C7.
    func slotsBeyond(_ slotCount: Int) -> [Int] {
        recipeUUIDs.indices.map { $0 + 1 }.filter { $0 > slotCount }
    }

    /// "C7", "C6 and C7", "C5–C7" — for a run of consecutive slots like `slotsBeyond`'s.
    static func slotRunLabel(_ slots: [Int]) -> String {
        guard let first = slots.first, let last = slots.last else { return "" }
        switch slots.count {
        case 1: return "C\(first)"
        case 2: return "C\(first) and C\(last)"
        default: return "C\(first)–C\(last)"
        }
    }

    func touch() { updatedAt = Date() }
}
