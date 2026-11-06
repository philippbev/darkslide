import Foundation
import SwiftData

/// The recipe a new library starts with: Lua de Mel and its sample photos, shipped in the app bundle
/// as an ordinary `.fujirecipe` file. It goes through the same decoding and validation as a file the
/// user imports, so the bundled copy can't drift from what the format accepts.
///
/// Seeded once per install, and only into an empty library: ``seedIfNeeded(into:defaults:)`` never
/// adds to a library that already holds recipes. The empty Library still offers it, so a user who
/// deleted it can add it back.
///
/// Every copy the app writes carries ``uuid``, on every device and every install, so copies that
/// sync brings together are recognisable as one recipe, and ``collapseCopies(in:)`` merges them.
/// The identity is the uuid rather than a marker attribute because chapters, picks and frame seeds
/// reference recipes by uuid: a reference to the starter keeps resolving whichever copy survives.
///
/// A seed lands before the install's first sync, because iCloud sync starts switched off. So a
/// reinstall, or a new device, that turns sync on brings the starter into the synced library, even
/// one the user had deleted it from.
///
/// The file's photos are not under the Apache license; TRADEMARKS.md says what a fork does with them.
enum StarterRecipe {
    /// The bundled file's name, which is also the recipe's.
    static let name = "Lua de Mel"

    /// The identity of every copy of the starter. Never changes: a copy written by an older build
    /// on another device has to match one written by this build.
    // A well-formed literal, so the initializer cannot fail. `StarterRecipeTests` pins the value.
    static let uuid = UUID(uuidString: "32784DB2-A466-4DA1-9899-88CFD7E32CD1")!

    struct Loaded {
        let recipe: PortableRecipe
        let photos: RecipePhotoReplacement
    }

    /// The bundled recipe, validated, with its photos processed and ready to attach. Synchronous and
    /// free of SwiftData objects, so it can run off the main actor.
    static func load(from bundle: Bundle = .main) throws -> Loaded {
        guard let url = bundle.url(forResource: name, withExtension: "fujirecipe") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let file = try RecipePortability.decodeFile(Data(contentsOf: url))
        guard var recipe = file.allRecipes.first else { throw RecipeFileError.empty }
        let photos = (recipe.photos ?? []).compactMap { portable in
            Data(base64Encoded: portable.data).flatMap(PhotoProcessing.importedPhoto)
        }
        recipe.photos = nil
        return Loaded(recipe: recipe, photos: .replace(photos))
    }

    /// UserDefaults key, set once this install has seeded its library or found it already in use.
    static let seededDefaultsKey = "library.starterRecipeSeeded"

    /// Add the starter to a new library, once per install. A library that already holds recipes (one
    /// from an earlier build, or a recipe the Share Extension saved) is marked done and left alone.
    /// On failure the mark stays unset, so the next launch tries again.
    @MainActor
    static func seedIfNeeded(into context: ModelContext, defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: seededDefaultsKey) else { return }
        do {
            if try context.fetchCount(FetchDescriptor<Recipe>()) == 0 {
                try await add(to: context)
                AppLog.info(.importExport, "Added the starter recipe to a new library")
            }
            defaults.set(true, forKey: seededDefaultsKey)
        } catch {
            AppLog.error(.importExport, "Seeding the starter recipe failed — \(AppLog.bounded(error))")
        }
    }

    /// Add the bundled recipe to the library and save it. When the library already holds a copy,
    /// returns that copy and adds nothing.
    @MainActor @discardableResult
    static func add(to context: ModelContext) async throws -> Recipe {
        let loaded = try await Task.detached(priority: .userInitiated) { try load() }.value
        // Checked after the load, not before: another add can land while the file decodes.
        if let existing = try context.fetch(copiesFetch).first { return existing }
        let recipe = makeRecipe(from: loaded, at: Date())
        context.insert(recipe)
        try context.save()
        return recipe
    }

    /// A new, unsaved copy of the starter, created and last updated at `date`.
    static func makeRecipe(from loaded: Loaded, at date: Date) -> Recipe {
        let recipe = RecipePortability.makeRecipe(from: loaded.recipe, photoReplacement: loaded.photos)
        recipe.uuid = uuid
        // One instant for both, so a copy nobody has edited stays recognisable: every edit stamps
        // `Recipe.touch()`, which moves `updatedAt` past `createdAt`.
        recipe.createdAt = date
        recipe.updatedAt = date
        return recipe
    }

    /// Merge the library's copies of the starter by the rules in ``StarterRecipeCopies``, and save.
    /// With at most one copy, does nothing: no save and no log line.
    @MainActor
    static func collapseCopies(in context: ModelContext) throws {
        let copies = try context.fetch(copiesFetch)
        let resolution = StarterRecipeCopies.resolve(copies.map {
            StarterRecipeCopies.Copy(id: $0.persistentModelID, createdAt: $0.createdAt,
                                     isEdited: $0.updatedAt != $0.createdAt)
        })
        guard !resolution.isEmpty else { return }
        let copiesByID = Dictionary(uniqueKeysWithValues: copies.map { ($0.persistentModelID, $0) })
        for id in resolution.delete {
            if let copy = copiesByID[id] { context.delete(copy) }
        }
        for id in resolution.rekey {
            copiesByID[id]?.uuid = UUID()
        }
        try context.save()
        AppLog.info(.data, "Starter recipe copies collapsed: \(resolution.delete.count) deleted, \(resolution.rekey.count) re-keyed")
    }

    /// Every copy of the starter in the library.
    private static var copiesFetch: FetchDescriptor<Recipe> {
        let id = uuid
        return FetchDescriptor(predicate: #Predicate { $0.uuid == id })
    }
}
