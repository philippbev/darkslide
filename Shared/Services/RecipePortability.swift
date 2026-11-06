import Foundation

/// Errors surfaced during JSON import. Every case is **non-destructive**: nothing is added to or
/// changed in the library when one is thrown, and a partial or corrupt file never partially
/// imports.
enum RecipeFileError: LocalizedError, Equatable {
    case notJSON
    case wrongSchema(found: String)
    case unsupportedVersion(found: Int, supported: Int)
    case empty
    case malformed(detail: String)
    case resourceLimit(detail: String)
    case unsafeNumber(recipe: Int, field: String)

    var errorDescription: String? {
        switch self {
        case .notJSON:
            return "This file isn't valid JSON, so it can't be read as a recipe."
        case .wrongSchema(let found):
            return "This file is JSON but isn't a Fuji Cookbook recipe (schema “\(found)”). Nothing was imported."
        case .unsupportedVersion(let found, let supported):
            return "This recipe file uses format version \(found), which is newer than this app supports (up to \(supported)). Update the app to import it. Nothing was changed."
        case .empty:
            return "This recipe file doesn't contain any recipes."
        case .malformed(let detail):
            return "This recipe file is malformed and couldn't be imported: \(detail)"
        case .resourceLimit(let detail):
            return "\(detail) Nothing was imported."
        case .unsafeNumber(let recipe, let field):
            return "Recipe \(recipe) has an invalid \(field) value. Numeric settings must be finite and fit within a signed 32-bit number. Nothing was imported."
        }
    }
}

extension RecipeFileError {
    /// Coarse, non-identifying label for log lines — the same idea as
    /// `RecipeScanError.diagnosticReason`, for the same reason: "the import failed" covers several
    /// unrelated causes, only some of which are ours to fix.
    ///
    /// The associated values are deliberately **not** passed through. `wrongSchema(found:)` carries a
    /// string lifted straight out of whatever file the user opened, and `malformed(detail:)` carries a
    /// `DecodingError` description that can quote the offending value back — both are exactly the
    /// unbounded, user-supplied content a log line must not carry. They stay in the alert the user
    /// reads, which is where they're actually useful.
    var diagnosticReason: String {
        switch self {
        case .notJSON: return "not_json"
        case .wrongSchema: return "wrong_schema"
        case .unsupportedVersion: return "unsupported_version"
        case .empty: return "empty"
        case .malformed: return "malformed"
        case .resourceLimit: return "resource_limit"
        case .unsafeNumber: return "unsafe_number"
        }
    }
}

/// Converts between the persisted `Recipe` model and the portable JSON format, and validates files
/// before anything touches the library.
enum RecipePortability {

    // MARK: Encoding

    /// JSON encoder configured for **human-readable, stable, round-trippable** output.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Encode a file envelope to pretty JSON bytes.
    static func encode(_ file: RecipeFile) throws -> Data {
        try makeEncoder().encode(file)
    }

    /// A single recipe as a complete `.fujirecipe` file's bytes.
    /// Pass `includePhotos: true` to embed the recipe's sample photos (larger file).
    /// Each export throws `RecipeExportError` rather than write a file import would refuse.
    static func encodeSingle(_ recipe: Recipe, includePhotos: Bool = false,
                             limits: RecipeImportLimits = .standard) throws -> Data {
        try encode(.single(recipe, includePhotos: includePhotos), limits: limits)
    }

    /// Many recipes as one combined file's bytes.
    static func encodeMany(_ recipes: [Recipe], includePhotos: Bool = false,
                           limits: RecipeImportLimits = .standard) throws -> Data {
        try encode(.many(recipes, includePhotos: includePhotos), limits: limits)
    }

    /// A full backup: every recipe (with stable uuids) plus every chapter, as one file's bytes.
    /// Identity (`uuid`) is included here so chapters can re-link to their recipes on restore.
    static func encodeBackup(recipes: [Recipe], chapters: [Chapter], includePhotos: Bool,
                             limits: RecipeImportLimits = .standard) throws -> Data {
        try encode(.backup(recipes: recipes, chapters: chapters, includePhotos: includePhotos), limits: limits)
    }

    /// A snapshot as a complete file's bytes, checked against what import accepts. Touches no
    /// SwiftData objects, so it can run off the main actor; `progress` counts photos checked.
    static func encode(_ snapshot: RecipeExportSnapshot, limits: RecipeImportLimits = .standard,
                       progress: RecipeExportValidation.ProgressHandler = { _ in }) throws -> Data {
        try RecipeExportValidation.check(snapshot, limits: limits, progress: progress)
        try Task.checkCancellation()
        let recipes = snapshot.entries.map { entry -> PortableRecipe in
            var recipe = entry.recipe
            if !entry.photos.isEmpty {
                recipe.photos = entry.photos.map { PortablePhoto(data: $0.base64EncodedString()) }
            }
            return recipe
        }
        var file: RecipeFile = snapshot.shape == .single ? .single(recipes[0]) : .many(recipes)
        file.chapters = snapshot.chapters
        return try RecipeExportValidation.checked(encode(file), limits: limits)
    }

    static func portableChapter(from chapter: Chapter) -> PortableChapter {
        PortableChapter(name: chapter.name, recipeUUIDs: chapter.recipeUUIDs)
    }

    // MARK: Model <-> portable

    /// Pass `includeIdentity: true` to embed the recipe's stable `uuid` — only needed for full
    /// backups, where chapters reference recipes by uuid. Recipe-only exports (single/combined)
    /// omit it so shared files stay clean; the importer mints a fresh id on import either way.
    static func portable(from recipe: Recipe, includePhotos: Bool = false, includeIdentity: Bool = false) -> PortableRecipe {
        let photos: [PortablePhoto]? = includePhotos && !recipe.sortedPhotos.isEmpty
            ? recipe.sortedPhotos.map { PortablePhoto(data: $0.imageData.base64EncodedString()) }
            : nil
        return PortableRecipe(
            name: recipe.name,
            uuid: includeIdentity ? recipe.uuid : nil,
            // Always carried, generated or not, so an imported recipe has a usable slot name
            // immediately; the flag beside it is what keeps the two kinds distinguishable.
            cameraName: recipe.effectiveCameraName,
            cameraNameIsCustom: recipe.hasCustomCameraName,
            credit: recipe.displayCredit,
            authoredForModel: recipe.authoredForModelID,
            notes: recipe.notes.isEmpty ? nil : recipe.notes,
            tags: recipe.tags.isEmpty ? nil : recipe.tags,
            settings: recipe.settings,
            unsupportedFields: recipe.unsupportedFields.isEmpty ? nil : recipe.unsupportedFields,
            photos: photos
        )
    }

    /// Build a fresh (unsaved) `Recipe` from a portable recipe. A new `uuid` is minted so importing
    /// never silently collides with an existing inventory item; duplicate detection is handled
    /// separately by `DuplicateResolver`. Any embedded photos are attached as `RecipePhoto`s (they
    /// enter the store when the recipe is inserted into a context).
    static func makeRecipe(from portable: PortableRecipe,
                           photoReplacement: RecipePhotoReplacement? = nil) -> Recipe {
        let recipe = Recipe(
            name: portable.name,
            // Only an author's own name is carried across as an override. A generated one is left
            // for `Recipe.init` to regenerate, so it tracks this library's copy of the name —
            // which the importer may still be about to disambiguate to "… (2)".
            cameraName: portable.isCameraNameCustom ? portable.cameraName : nil,
            notes: portable.notes ?? "",
            tags: portable.tags ?? [],
            credit: portable.credit,
            authoredForModelID: portable.authoredForModel,
            settings: portable.settings,
            unsupportedFields: portable.unsupportedFields ?? [:]
        )
        recipe.photos = photoReplacement?.makePhotos() ?? makePhotos(from: portable.photos)
        return recipe
    }

    /// Decode embedded portable photos into `RecipePhoto`s, regenerating thumbnails locally.
    /// Photos that fail to decode are skipped (non-destructive). `sortOrder` follows file order.
    static func makePhotos(from portablePhotos: [PortablePhoto]?) -> [RecipePhoto] {
        guard let portablePhotos else { return [] }
        var result: [RecipePhoto] = []
        for portable in portablePhotos {
            guard let imageData = Data(base64Encoded: portable.data),
                  let processed = PhotoProcessing.importedPhoto(imageData) else { continue }
            result.append(RecipePhoto(imageData: processed.full,
                                      thumbnailData: processed.thumbnail,
                                      sortOrder: result.count))
        }
        return result
    }

    // MARK: Decoding + validation

    /// Validate and decode the full file envelope (recipes + any chapters). Throws `RecipeFileError`
    /// on any problem; on success the recipes are guaranteed non-empty. Performs **all** validation
    /// before the caller writes anything to the library.
    static func decodeFile(_ data: Data, limits: RecipeImportLimits = .standard) throws -> RecipeFile {
        guard data.count <= limits.fileBytes else {
            throw RecipeFileError.resourceLimit(detail: "This file exceeds the \(limits.fileBytes / 1_048_576) MiB import limit. Export smaller recipe groups or a backup without photos.")
        }
        // Decode once. A JSONSerialization preflight would materialize a second complete tree,
        // including every base64 image, just to throw it away before JSONDecoder reads it again.
        let file: RecipeFile
        do {
            file = try JSONDecoder().decode(RecipeFile.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw RecipeFileError.malformed(detail: "missing field “\(key.stringValue)”")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw RecipeFileError.malformed(detail: ctx.debugDescription)
        } catch let DecodingError.dataCorrupted(ctx) {
            if ctx.codingPath.isEmpty { throw RecipeFileError.notJSON }
            throw RecipeFileError.malformed(detail: ctx.debugDescription)
        } catch {
            throw RecipeFileError.malformed(detail: error.localizedDescription)
        }

        guard file.schema == RecipeSchema.identifier else {
            throw RecipeFileError.wrongSchema(found: file.schema)
        }

        // Older versions migrate up; newer ones are refused.
        guard file.version <= RecipeSchema.currentVersion else {
            throw RecipeFileError.unsupportedVersion(found: file.version,
                                                     supported: RecipeSchema.currentVersion)
        }
        let migrated = RecipeSchemaMigrator.migrate(file)
        guard !migrated.allRecipes.isEmpty else { throw RecipeFileError.empty }
        try RecipeImportValidation.validate(migrated, limits: limits)
        return migrated
    }
}

/// Forward-migration of older schema versions to the current shape: the schema is versioned so
/// future app versions can migrate older files. v1 is the baseline; add `case` branches here as
/// the schema evolves.
enum RecipeSchemaMigrator {
    static func migrate(_ file: RecipeFile) -> RecipeFile {
        switch file.version {
        case RecipeSchema.currentVersion:
            return file
        default:
            // No older versions exist yet. When v2 ships, transform v1 payloads here.
            return file
        }
    }
}
