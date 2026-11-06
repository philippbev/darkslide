import Foundation
import SwiftData

/// Applies a duplicate `DuplicateResolution` while inserting an imported recipe into the inventory.
/// Shared by JSON import and camera import.
enum RecipeImporter {
    /// Result of importing one recipe, for a summary message.
    enum Outcome { case added, replaced, skipped }

    /// What happened, plus the resulting library recipe: the matched one for skip and overwrite
    /// (nil when skip had no match), the new one whenever a recipe is added. The recipe lets
    /// callers reference it afterward — e.g. to group an import into a Chapter.
    struct ApplyResult {
        let outcome: Outcome
        let recipe: Recipe?
    }

    static func defaultResolution(for match: DuplicateMatch?) -> DuplicateResolution {
        match?.reason == .sameNameAndSettings ? .skip : .keepBoth
    }

    /// Commit a reviewed file using one context. Save unrelated pending edits first; thereafter a
    /// staging/read/save failure can roll back this batch without discarding earlier user work.
    /// No suspension points: autosave cannot publish a half-written batch between recipes.
    static func applyBatch(_ recipes: [PortableRecipe], chapters: [PortableChapter],
                           prepared: [PreparedRecipe]? = nil,
                           resolutions: [Int: DuplicateResolution], into context: ModelContext) throws {
        try context.save()
        do {
            try context.transaction {
                let existing = try context.fetch(Recipe.listFetch())
                let existingChapters = try context.fetch(FetchDescriptor<Chapter>())
                // Match against the pre-import library, as the review does. Earlier additions in
                // this same batch must not turn the user's "keep both" into an overwrite.
                let matches = recipes.map { DuplicateResolver.match(for: $0, in: existing) }
                var usedNames = Set(existing.map { nameKey($0.name) })
                var idMap: [UUID: UUID] = [:]
                for (index, recipe) in recipes.enumerated() {
                    let match = matches[index]
                    let resolution = match == nil ? .keepBoth : (resolutions[index] ?? defaultResolution(for: match))
                    let replacement: RecipePhotoReplacement?
                    if resolution == .skip { replacement = nil }
                    else { replacement = try prepared?[index].photoReplacement() }
                    let result = apply(recipe, resolution: resolution, match: match, into: context,
                                       usedNameKeys: &usedNames, photoReplacement: replacement)
                    if let original = recipe.uuid, let imported = result.recipe { idMap[original] = imported.uuid }
                }
                for chapter in chapters {
                    let mapped = chapter.recipeUUIDs.compactMap { idMap[$0] }
                    guard !mapped.isEmpty else { continue }
                    guard !existingChapters.contains(where: {
                        $0.name == chapter.name && Set($0.recipeUUIDs) == Set(mapped)
                    }) else { continue }
                    context.insert(Chapter(name: chapter.name, recipeUUIDs: Array(mapped.prefix(Chapter.maxSlots))))
                }
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    /// A recipe name normalized for duplicate detection and disambiguation: trimmed and lowercased.
    /// `DuplicateResolver.match` and the importer's taken-name set both use it, so a name detected
    /// as a duplicate is always disambiguated.
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `usedNameKeys` holds every name already taken, as ``nameKey`` values: the library's plus
    /// those this import has added. The caller builds it once per import from the library it
    /// already holds for duplicate matching, and `apply` inserts each name it adds. Rebuilding it
    /// here would fetch the whole Recipe table once per imported recipe.
    @discardableResult
    static func apply(_ portable: PortableRecipe,
                      resolution: DuplicateResolution,
                      match: DuplicateMatch?,
                      into context: ModelContext,
                      usedNameKeys: inout Set<String>,
                      photoReplacement: RecipePhotoReplacement? = nil) -> ApplyResult {
        switch resolution {
        case .skip:
            // Nothing added, but the existing match is the recipe this slot maps to.
            return ApplyResult(outcome: .skipped, recipe: match?.existing)

        case .overwrite:
            if let existing = match?.existing {
                existing.setSettings(portable.settings)
                existing.setName(portable.name)
                // Only an incoming *custom* name replaces a local one. `cameraName != nil` is no
                // guard: every export carries a generated name, so it would have overwrite quietly
                // replace every local custom slot name with a remote automatic one.
                if portable.isCameraNameCustom { existing.cameraName = portable.cameraName }
                // A field the incoming file leaves out keeps the local value, so overwriting never
                // erases notes, tags or a credit.
                existing.notes = portable.notes ?? existing.notes
                existing.tags = portable.tags ?? existing.tags
                existing.credit = portable.credit ?? existing.credit
                existing.authoredForModelID = portable.authoredForModel
                existing.unsupportedFields = portable.unsupportedFields ?? [:]
                // Only touch photos when the incoming file actually carried them; a recipe-only
                // export (no `photos` key) leaves the existing samples intact.
                let incomingPhotos: [RecipePhoto]?
                if let photoReplacement {
                    if case .preserve = photoReplacement { incomingPhotos = nil }
                    else { incomingPhotos = photoReplacement.makePhotos() }
                } else if let supplied = portable.photos {
                    let decoded = RecipePortability.makePhotos(from: supplied)
                    incomingPhotos = !supplied.isEmpty && decoded.isEmpty ? nil : decoded
                } else {
                    incomingPhotos = nil
                }
                if let incomingPhotos {
                    for old in (existing.photos ?? []) { context.delete(old) }
                    existing.photos = []
                    for photo in incomingPhotos {
                        photo.recipe = existing
                        context.insert(photo)
                    }
                }
                existing.touch()
                usedNameKeys.insert(nameKey(existing.name))
                return ApplyResult(outcome: .replaced, recipe: existing)
            }
            let added = insert(portable, into: context, photoReplacement: photoReplacement)
            usedNameKeys.insert(nameKey(added.name))
            return ApplyResult(outcome: .added, recipe: added)

        case .keepBoth:
            let recipe = RecipePortability.makeRecipe(from: portable, photoReplacement: photoReplacement)
            // Disambiguate when a same-named recipe already exists. `setName` regenerates the
            // generated slot name, so "Velvia Daily (2)" doesn't reach the camera under the same
            // label as "Velvia Daily".
            if match?.reason == .sameName || match?.reason == .sameNameAndSettings {
                let unique = uniqueName(portable.name, among: usedNameKeys)
                recipe.setName(unique.name)
                // A *custom* slot name isn't touched by `setName` — `effectiveCameraName` prefers
                // the override, so without this "keep both" produces two recipes the camera shows
                // under one label. Only when it actually collides: an override the author already
                // made distinct is theirs, and renaming it would be presumptuous.
                if let counter = unique.counter,
                   let override = recipe.cameraName,
                   let existing = match?.existing,
                   CameraSlotName.sanitize(override) == CameraSlotName.sanitize(existing.effectiveCameraName) {
                    // Sanitize rather than truncate: `CameraSlotName` keeps the counter when it has
                    // to cut, which is the only reason this fits inside 25 characters.
                    recipe.cameraName = CameraSlotName.sanitize("\(override) (\(counter))")
                }
            }
            usedNameKeys.insert(nameKey(recipe.name))
            context.insert(recipe)
            return ApplyResult(outcome: .added, recipe: recipe)
        }
    }

    @discardableResult
    private static func insert(_ portable: PortableRecipe, into context: ModelContext,
                               photoReplacement: RecipePhotoReplacement?) -> Recipe {
        let recipe = RecipePortability.makeRecipe(from: portable, photoReplacement: photoReplacement)
        context.insert(recipe)
        return recipe
    }

    /// The first free variant of `base`, plus the counter that made it free (nil when `base` was
    /// already free). The caller needs the counter so a custom slot name can carry the same one.
    private static func uniqueName(_ base: String, among keys: Set<String>) -> (name: String, counter: Int?) {
        if !keys.contains(nameKey(base)) { return (base, nil) }
        var n = 2
        while keys.contains(nameKey("\(base) (\(n))")) { n += 1 }
        return ("\(base) (\(n))", n)
    }
}
