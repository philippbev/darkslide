import Foundation
import SwiftData

/// Hands out the archive numbers recipes show in the design system ("034").
///
/// Numbers run in order of `createdAt`, starting at 1, and stay with a recipe for good. A recipe
/// without one gets the next free number; a deleted recipe's number is not handed out again. The
/// highest number ever given is kept in the app group's defaults for that, since the recipe that
/// held it may be gone.
///
/// The first run numbers the whole existing library, oldest first. That is the migration: the
/// column itself arrives by lightweight migration with every recipe at 0.
enum RecipeArchiveNumbering {
    static let highWaterKey = "recipes.archiveNumber.highWater"

    /// What the numbering needs to know about a recipe. `ID` tells the recipes apart; the uuid only
    /// breaks ties in `createdAt`, because copies of the starter recipe share one until
    /// `StarterRecipe.collapseCopies` merges them.
    struct Entry<ID: Hashable>: Equatable {
        let id: ID
        let uuid: UUID
        let number: Int
        let createdAt: Date
    }

    struct Plan<ID: Hashable>: Equatable {
        /// The numbers to give, by recipe.
        let assignments: [ID: Int]
        /// The highest number handed out after these assignments.
        let highWater: Int
    }

    /// The numbers to give the recipes that have none. Pure, for the tests.
    ///
    /// Counts on from the larger of the stored high-water mark and the highest number in the
    /// library, so numbers that arrive by sync from another device aren't handed out again here.
    /// Ties in `createdAt` fall back to the uuid, so the order is the same on every run.
    static func plan<ID: Hashable>(for entries: [Entry<ID>], highWater storedHighWater: Int) -> Plan<ID> {
        var next = max(storedHighWater, entries.map(\.number).max() ?? 0)
        var assignments: [ID: Int] = [:]
        let unnumbered = entries
            .filter { $0.number <= 0 }
            .sorted { ($0.createdAt, $0.uuid.uuidString) < ($1.createdAt, $1.uuid.uuidString) }
        for entry in unnumbered {
            next += 1
            assignments[entry.id] = next
        }
        return Plan(assignments: assignments, highWater: next)
    }

    /// Numbers every recipe in `context` that has no number yet, except those whose uuid is in
    /// `excluded` (a new recipe whose editor is still open, which a cancel would delete again: by
    /// uuid because its persistent id changes when autosave first stores it). Returns how many it
    /// numbered; saves when that is more than none.
    @discardableResult
    static func assignMissing(in context: ModelContext,
                              excluding excluded: Set<UUID> = [],
                              defaults: UserDefaults? = SharedDefaults.suite) throws -> Int {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
            .filter { $0.archiveNumber > 0 || !excluded.contains($0.uuid) }
        let entries = recipes.map {
            Entry(id: $0.persistentModelID, uuid: $0.uuid, number: $0.archiveNumber, createdAt: $0.createdAt)
        }
        let plan = plan(for: entries, highWater: defaults?.integer(forKey: highWaterKey) ?? 0)
        // Recording the mark even when nothing new is numbered keeps it at the library's highest
        // number, so deleting that recipe later can't free its number.
        defaults?.set(plan.highWater, forKey: highWaterKey)
        guard !plan.assignments.isEmpty else { return 0 }
        for recipe in recipes {
            if let number = plan.assignments[recipe.persistentModelID] { recipe.archiveNumber = number }
        }
        try context.save()
        return plan.assignments.count
    }
}
