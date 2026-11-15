import Foundation
import SwiftData

/// What a new library starts with: three recipes and a roll that holds them in slots C1–C3. The
/// recipes ship in the app bundle as ordinary `.fujirecipe` files and go through the same decoding
/// and validation as a file the user imports, so the bundled copies can't drift from what the format
/// accepts.
///
/// Seeded once per install, and only into an empty library: ``seedIfNeeded(into:defaults:)`` never
/// adds to a library that already holds recipes. The empty Library still offers the set, so a user
/// who deleted it can add it back.
///
/// Every copy the app writes carries its entry's fixed uuid (and the roll ``rollUUID``), on every
/// device and every install, so copies that sync brings together are recognisable as one, and
/// ``collapseCopies(in:)`` merges them. The identity is the uuid rather than a marker attribute
/// because rolls, picks and frame seeds reference recipes by uuid: the roll keeps resolving its
/// recipes whichever copies survive.
///
/// A seed lands before the install's first sync, because iCloud sync starts switched off. So a
/// reinstall, or a new device, that turns sync on brings the starters into the synced library, even
/// one the user had deleted them from.
enum StarterLibrary {
    struct Entry: Equatable {
        /// The bundled file's name, which is also the recipe's.
        let name: String
        /// The identity of every copy of this recipe. Never changes: a copy written by an older
        /// build on another device has to match one written by this build.
        let uuid: UUID
    }

    // Well-formed literals, so the initializers cannot fail. `StarterLibraryTests` pins the values.
    /// In roll order: the first goes to C1.
    static let recipes = [
        Entry(name: "Acros Pro", uuid: UUID(uuidString: "A37634E7-80CD-43FD-97DF-27F0D0F423DF")!),
        Entry(name: "FUJICOLOR 400", uuid: UUID(uuidString: "8AA7D12C-C8D8-40D4-B643-4BCAA0B70DC7")!),
        Entry(name: "NATURAL", uuid: UUID(uuidString: "11A8ADE1-FCE0-480E-957A-6F438E921846")!),
    ]

    static let rollName = "Starter"
    static let rollUUID = UUID(uuidString: "5775D737-49FC-4922-BD06-E69B6CDC0FE5")!

    static var recipeUUIDs: [UUID] { recipes.map(\.uuid) }

    struct Loaded {
        let entry: Entry
        let recipe: PortableRecipe
        let photos: RecipePhotoReplacement
    }

    /// One bundled recipe, validated, with any photos processed and ready to attach. Synchronous and
    /// free of SwiftData objects, so it can run off the main actor.
    static func load(_ entry: Entry, from bundle: Bundle = .main) throws -> Loaded {
        guard let url = bundle.url(forResource: entry.name, withExtension: "fujirecipe") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let file = try RecipePortability.decodeFile(Data(contentsOf: url))
        guard var recipe = file.allRecipes.first else { throw RecipeFileError.empty }
        let photos = (recipe.photos ?? []).compactMap { portable in
            Data(base64Encoded: portable.data).flatMap(PhotoProcessing.importedPhoto)
        }
        recipe.photos = nil
        return Loaded(entry: entry, recipe: recipe, photos: .replace(photos))
    }

    /// UserDefaults key, set once this install has seeded its library or found it already in use.
    /// The key predates the roll: an install that seeded the earlier single starter is done too.
    static let seededDefaultsKey = "library.starterRecipeSeeded"

    /// Add the starters to a new library, once per install. A library that already holds recipes
    /// (one from an earlier build, say) is marked done and left alone.
    /// On failure the mark stays unset, so the next launch tries again.
    @MainActor
    static func seedIfNeeded(into context: ModelContext, defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: seededDefaultsKey) else { return }
        do {
            if try context.fetchCount(FetchDescriptor<Recipe>()) == 0 {
                try await add(to: context)
                AppLog.info(.importExport, "Added the starter recipes and roll to a new library")
            }
            defaults.set(true, forKey: seededDefaultsKey)
        } catch {
            AppLog.error(.importExport, "Seeding the starter recipes failed — \(AppLog.bounded(error))")
        }
    }

    /// Add every bundled recipe the library has no copy of, and the roll if it has none, then save.
    /// Copies already there are left as they are.
    @MainActor
    static func add(to context: ModelContext) async throws {
        let loaded = try await Task.detached(priority: .userInitiated) {
            try recipes.map { try load($0) }
        }.value
        // Checked after the load, not before: another add can land while the files decode.
        let now = Date()
        for (index, item) in loaded.enumerated() where try !hasCopy(of: item.entry.uuid, in: context) {
            // A second apart, in roll order, so archive numbers follow the slots.
            context.insert(makeRecipe(from: item, at: now.addingTimeInterval(TimeInterval(index))))
        }
        if try context.fetchCount(rollCopiesFetch) == 0 {
            context.insert(makeRoll(at: now))
        }
        if context.hasChanges { try context.save() }
    }

    /// A new, unsaved copy of a starter recipe, created and last updated at `date`.
    static func makeRecipe(from loaded: Loaded, at date: Date) -> Recipe {
        let recipe = RecipePortability.makeRecipe(from: loaded.recipe, photoReplacement: loaded.photos)
        recipe.uuid = loaded.entry.uuid
        // One instant for both, so a copy nobody has edited stays recognisable: every edit stamps
        // `Recipe.touch()`, which moves `updatedAt` past `createdAt`.
        recipe.createdAt = date
        recipe.updatedAt = date
        return recipe
    }

    /// A new, unsaved copy of the starter roll. Like a recipe copy, untouched while `updatedAt`
    /// equals `createdAt`; the roll editor stamps `Chapter.touch()` on save.
    static func makeRoll(at date: Date) -> Chapter {
        Chapter(uuid: rollUUID, name: rollName, recipeUUIDs: recipeUUIDs, createdAt: date, updatedAt: date)
    }

    /// Whether the given recipes or rolls hold a starter twice, which sync does when two devices
    /// each seeded. What the views watch to call ``collapseCopies(in:)``.
    static func hasDuplicates(recipeUUIDs ids: some Sequence<UUID>) -> Bool {
        let starters = Set(recipeUUIDs)
        var seen = Set<UUID>()
        for id in ids where starters.contains(id) {
            if !seen.insert(id).inserted { return true }
        }
        return false
    }

    /// Merge the library's copies of each starter recipe and of the roll by the rules in
    /// ``StarterCopies``, and save. With at most one copy of each, does nothing: no save and no log
    /// line.
    @MainActor
    static func collapseCopies(in context: ModelContext) throws {
        var deleted = 0
        var rekeyed = 0
        for id in recipeUUIDs {
            let copies = try context.fetch(recipeCopiesFetch(id))
            let resolution = StarterCopies.resolve(copies.map {
                StarterCopies.Copy(id: $0.persistentModelID, createdAt: $0.createdAt,
                                   isEdited: $0.updatedAt != $0.createdAt)
            })
            let byID = Dictionary(uniqueKeysWithValues: copies.map { ($0.persistentModelID, $0) })
            for copyID in resolution.delete { byID[copyID].map(context.delete) }
            for copyID in resolution.rekey { byID[copyID]?.uuid = UUID() }
            deleted += resolution.delete.count
            rekeyed += resolution.rekey.count
        }
        let rolls = try context.fetch(rollCopiesFetch)
        let resolution = StarterCopies.resolve(rolls.map {
            StarterCopies.Copy(id: $0.persistentModelID, createdAt: $0.createdAt,
                               isEdited: $0.updatedAt != $0.createdAt)
        })
        let rollsByID = Dictionary(uniqueKeysWithValues: rolls.map { ($0.persistentModelID, $0) })
        for copyID in resolution.delete { rollsByID[copyID].map(context.delete) }
        for copyID in resolution.rekey { rollsByID[copyID]?.uuid = UUID() }
        deleted += resolution.delete.count
        rekeyed += resolution.rekey.count

        guard deleted + rekeyed > 0 else { return }
        try context.save()
        AppLog.info(.data, "Starter copies collapsed: \(deleted) deleted, \(rekeyed) re-keyed")
    }

    private static func hasCopy(of id: UUID, in context: ModelContext) throws -> Bool {
        try context.fetchCount(recipeCopiesFetch(id)) > 0
    }

    private static func recipeCopiesFetch(_ id: UUID) -> FetchDescriptor<Recipe> {
        FetchDescriptor(predicate: #Predicate { $0.uuid == id })
    }

    private static var rollCopiesFetch: FetchDescriptor<Chapter> {
        let id = rollUUID
        return FetchDescriptor(predicate: #Predicate { $0.uuid == id })
    }
}
