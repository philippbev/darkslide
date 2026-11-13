import Foundation

/// Why an export was refused. Nothing is written when one is thrown.
enum RecipeExportError: LocalizedError, Equatable {
    case exceedsImportLimit(detail: String)
    /// Names the recipe, which the user can find in their library; an index into the export can't be.
    case unsafeNumber(recipe: String, field: String)

    var errorDescription: String? {
        switch self {
        case .exceedsImportLimit(let detail): return "\(detail) Nothing was exported."
        case .unsafeNumber(let recipe, let field):
            return "“\(recipe)” has an unsafe numeric value for \(field). Use a finite value within the signed 32-bit range before exporting. Nothing was exported."
        }
    }
}

/// Everything an export needs, copied out of SwiftData on the main actor so the checking, Base64
/// and JSON encoding can run off the main actor. Photos are the stored bytes in display order; they become
/// Base64 only when the file is built.
struct RecipeExportSnapshot {
    struct Entry {
        /// The recipe as it will be written, without its photos.
        var recipe: PortableRecipe
        /// Stored photo bytes in display order; empty when the export leaves photos out.
        var photos: [Data]
    }

    /// Whether the file holds one recipe (`recipe`) or a list (`recipes`).
    enum Shape { case single, many }

    var shape: Shape
    var entries: [Entry]
    var chapters: [PortableChapter]?

    var photoCount: Int { entries.reduce(0) { $0 + $1.photos.count } }

    static func single(_ recipe: Recipe, includePhotos: Bool) -> RecipeExportSnapshot {
        RecipeExportSnapshot(shape: .single, entries: [entry(recipe, includePhotos: includePhotos)])
    }

    static func many(_ recipes: [Recipe], includePhotos: Bool) -> RecipeExportSnapshot {
        RecipeExportSnapshot(shape: .many, entries: recipes.map { entry($0, includePhotos: includePhotos) })
    }

    /// Every recipe with its stable `uuid`, so chapters can re-link to them on restore, plus every
    /// chapter.
    static func backup(recipes: [Recipe], chapters: [Chapter], includePhotos: Bool) -> RecipeExportSnapshot {
        RecipeExportSnapshot(
            shape: .many,
            entries: recipes.map { entry($0, includePhotos: includePhotos, includeIdentity: true) },
            chapters: chapters.isEmpty ? nil : chapters.map(RecipePortability.portableChapter(from:)))
    }

    /// One chapter and the recipes in it, for sharing: the recipes in slot order with their `uuid`,
    /// so the chapter re-links to them on import the way a backup's chapters do.
    ///
    /// `recipes` is the library to resolve the chapter's slots against. A slot whose recipe is gone
    /// is left out of the file and of the chapter in it, so what arrives is a chapter with no holes.
    /// Nil when no slot resolves: a file without recipes can't be imported.
    static func chapter(_ chapter: Chapter, recipes: [Recipe], includePhotos: Bool) -> RecipeExportSnapshot? {
        let byUUID = Dictionary(recipes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let slots = chapter.recipeUUIDs.filter { byUUID[$0] != nil }
        guard !slots.isEmpty else { return nil }
        // A recipe that fills two slots is written once; both slots refer to it.
        var written = Set<UUID>()
        let entries = slots.filter { written.insert($0).inserted }
            .compactMap { byUUID[$0] }
            .map { entry($0, includePhotos: includePhotos, includeIdentity: true) }
        return RecipeExportSnapshot(shape: .many, entries: entries,
                                    chapters: [PortableChapter(name: chapter.name, recipeUUIDs: slots)])
    }

    private static func entry(_ recipe: Recipe, includePhotos: Bool, includeIdentity: Bool = false) -> Entry {
        Entry(recipe: RecipePortability.portable(from: recipe, includeIdentity: includeIdentity),
              photos: includePhotos ? recipe.sortedPhotos.map(\.imageData) : [])
    }
}

/// Refuses to write a recipe file this app couldn't import again.
///
/// Counts, numeric settings, source photo sizes and their Base64 sizes are checked before JSON is
/// built. Photos are then processed one at a time with the import pipeline to measure its prepared
/// photo budget, including regenerated thumbnails; that pass reports progress and stops when its
/// task is cancelled. The encoded file's exact size is checked after.
enum RecipeExportValidation {
    typealias Progress = RecipeImportPreparation.Progress
    typealias ProgressHandler = (Progress) -> Void

    /// Checks recipes straight from the library, as one combined file would hold them.
    static func check(_ recipes: [Recipe], includePhotos: Bool,
                      limits: RecipeImportLimits = .standard) throws {
        try check(.many(recipes, includePhotos: includePhotos), limits: limits)
    }

    /// `progress` counts photos run through the import pipeline; it isn't called when there are
    /// none.
    static func check(_ snapshot: RecipeExportSnapshot, limits: RecipeImportLimits = .standard,
                      progress: ProgressHandler = { _ in }) throws {
        guard snapshot.entries.count <= limits.recipes else {
            throw tooLarge("This export has more than \(limits.recipes) recipes, more than Fuji Cookbook can import from one file. Export fewer recipes at a time.")
        }
        guard (snapshot.chapters?.count ?? 0) <= limits.chapters else {
            throw tooLarge("This export has more than \(limits.chapters) chapters, more than Fuji Cookbook can import from one file.")
        }
        for entry in snapshot.entries {
            if let field = RecipeSettingsPortabilityValidation.invalidField(in: entry.recipe.settings) {
                throw RecipeExportError.unsafeNumber(recipe: entry.recipe.name, field: field)
            }
        }

        // Cheap limits come first so an oversized source never needs image processing or Base64.
        var encodedPhotoBytes = 0
        for entry in snapshot.entries {
            guard entry.photos.count <= Recipe.maxPhotos else {
                throw tooLarge("“\(entry.recipe.name)” has more than \(Recipe.maxPhotos) sample photos, more than Fuji Cookbook can import. Remove the extras or export without sample photos.")
            }
            for photo in entry.photos {
                guard photo.count <= limits.photoBytes else {
                    throw tooLarge("A sample photo in “\(entry.recipe.name)” is larger than Fuji Cookbook can import. Export without sample photos.")
                }
                let encodedBytes = (photo.count + 2) / 3 * 4
                guard encodedBytes <= limits.fileBytes - encodedPhotoBytes else {
                    throw fileTooLarge(limits)
                }
                encodedPhotoBytes += encodedBytes
            }
        }

        let total = snapshot.photoCount
        guard total > 0 else { return }
        var preparedPhotoBytes = 0
        var checked = 0
        progress(Progress(completed: 0, total: total))
        for entry in snapshot.entries {
            for photo in entry.photos {
                try Task.checkCancellation()
                // Legacy photos may be PNGs or oversized JPEGs. Their normalized bytes can grow,
                // and the stored thumbnail need not match the one import regenerates. Release each
                // result immediately; export still preserves the original photo bytes in the file.
                try autoreleasepool {
                    guard let processed = PhotoProcessing.importedPhoto(photo) else { return }
                    let size = processed.full.count + processed.thumbnail.count
                    guard size <= limits.preparedPhotoBytes - preparedPhotoBytes else {
                        throw tooLarge("The prepared sample photos would exceed the \(limits.preparedPhotoBytes / 1_048_576) MiB import budget, so this export couldn't be opened again. Export without sample photos, or export fewer recipes at a time.")
                    }
                    preparedPhotoBytes += size
                }
                checked += 1
                progress(Progress(completed: checked, total: total))
            }
        }
    }

    /// The encoded file, unchanged, once it is known to fit.
    static func checked(_ data: Data, limits: RecipeImportLimits = .standard) throws -> Data {
        guard data.count <= limits.fileBytes else { throw fileTooLarge(limits) }
        return data
    }

    private static func fileTooLarge(_ limits: RecipeImportLimits) -> RecipeExportError {
        tooLarge("This export would be larger than the \(limits.fileBytes / 1_048_576) MiB Fuji Cookbook can import, so it couldn't be opened again. Export fewer recipes at a time, or export without sample photos.")
    }

    private static func tooLarge(_ detail: String) -> RecipeExportError {
        .exceedsImportLimit(detail: detail)
    }
}
