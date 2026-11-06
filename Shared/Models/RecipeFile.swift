import Foundation

/// Schema constants for the portable JSON recipe format.
enum RecipeSchema {
    /// The `schema` discriminator written into every file.
    static let identifier = "fuji-recipe"
    /// The current schema version this app writes. Bump it and add a migration only for a change
    /// older versions can't read; an additive key needs neither.
    static let currentVersion = 1
}

/// A sample photo carried inside an exported recipe file. The bytes are the same compressed/resized
/// JPEG stored on-device, base64-encoded so they fit in JSON. Only present when the user chooses to
/// export *with* photos; recipe-only exports omit the `photos` key entirely.
struct PortablePhoto: Codable, Equatable {
    /// Base64-encoded compressed JPEG.
    var data: String
}

/// The portable, camera-agnostic representation of one recipe used for JSON import/export.
/// `docs/recipe-json-format.md` documents the shape.
struct PortableRecipe: Codable, Equatable {
    var name: String
    /// Stable identity, included so a full backup can re-link chapters to their recipes on restore.
    /// Optional and additive; recipe-only exports may omit it.
    var uuid: UUID?
    /// The camera-slot name (limited character set). Additive and backward-compatible.
    /// Always written on export, so a shared recipe arrives with a slot name already set.
    var cameraName: String?
    /// Whether `cameraName` is the author's own choice rather than the name generated from `name`.
    ///
    /// Without this, an importer can't tell the two apart once every export carries a slot name, and
    /// `.overwrite` would replace a local custom name with a remote generated one. Absent in files
    /// written before this key existed; those got their `cameraName` from a user typing it into the
    /// old editor, so treating a present-but-unflagged name as custom is the right reading.
    var cameraNameIsCustom: Bool?
    /// Who the recipe is by, carried with the file so attribution survives sharing. Additive and
    /// backward-compatible: older app versions ignore the key.
    var credit: String?
    var authoredForModel: String?
    var notes: String?
    var tags: [String]?
    var settings: RecipeSettings
    /// Fields preserved verbatim that this app version doesn't model.
    var unsupportedFields: [String: JSONValue]?
    /// Optional embedded sample photos. Additive and backward-compatible: older app versions simply
    /// ignore this key, and recipe-only exports leave it `nil`.
    var photos: [PortablePhoto]?
}

extension PortableRecipe {
    /// Whether this file's `cameraName` should be treated as the author's own choice.
    var isCameraNameCustom: Bool { cameraNameIsCustom ?? (cameraName != nil) }
}

/// A chapter in a full backup: a name plus the ordered recipe identities it groups. On restore the
/// importer remaps these to the imported recipes (see `RecipeImporter.applyBatch`).
struct PortableChapter: Codable, Equatable {
    var name: String
    var recipeUUIDs: [UUID]
}

/// A recipe file envelope. Carries the versioned schema header and either a single recipe
/// (`recipe`) or many (`recipes`); the importer handles both. A full backup also carries
/// `chapters`.
struct RecipeFile: Codable {
    var schema: String
    var version: Int
    var recipe: PortableRecipe?
    var recipes: [PortableRecipe]?
    /// Present in a full backup. Additive and backward-compatible — older versions ignore it.
    var chapters: [PortableChapter]?

    init(schema: String = RecipeSchema.identifier,
         version: Int = RecipeSchema.currentVersion,
         recipe: PortableRecipe? = nil,
         recipes: [PortableRecipe]? = nil,
         chapters: [PortableChapter]? = nil) {
        self.schema = schema
        self.version = version
        self.recipe = recipe
        self.recipes = recipes
        self.chapters = chapters
    }

    /// All recipes in the file regardless of single/multi shape.
    var allRecipes: [PortableRecipe] {
        if let recipes { return recipes }
        if let recipe { return [recipe] }
        return []
    }

    /// Build a single-recipe file.
    static func single(_ recipe: PortableRecipe) -> RecipeFile {
        RecipeFile(recipe: recipe)
    }

    /// Build a multi-recipe file.
    static func many(_ recipes: [PortableRecipe]) -> RecipeFile {
        RecipeFile(recipes: recipes)
    }
}
