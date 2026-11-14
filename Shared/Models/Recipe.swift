import Foundation
import SwiftData

/// A recipe in the user's inventory.
///
/// Persisted with SwiftData so the library survives app restarts and works fully offline with no
/// camera.
@Model
final class Recipe {
    /// Stable identity (separate from SwiftData's `persistentModelID`) used for export/import
    /// de-duplication, sharing, and list selection.
    ///
    /// Not `.unique`: CloudKit (the iCloud sync backend) forbids unique constraints. Identity
    /// de-duplication is done in app code (`DuplicateResolver`), so this is purely a stable id.
    var uuid: UUID = UUID()

    // Non-optional attributes carry default values because CloudKit requires every attribute to be
    // optional or defaulted. The defaults are placeholders; `init` always sets real values.
    /// `private(set)` so the only way to rename a recipe is ``setName(_:)``, which keeps
    /// ``slotNameDefault`` in step. Every would-be call site outside this file becomes a compile
    /// error rather than a slot name that quietly stops matching its recipe.
    private(set) var name: String = ""
    var notes: String = ""
    var tags: [String] = []
    var isFavorite: Bool = false

    /// Optional short name written to the camera's custom slot when this recipe is pushed.
    /// Camera slots only accept a limited character set and length (see `CameraModel.sanitizedSlotName`),
    /// so this lets the user keep an expressive library `name` while controlling the on-camera label.
    /// When nil or whitespace-only, the push uses ``slotNameDefault`` (see ``effectiveCameraName``).
    var cameraName: String?

    /// The slot name generated from ``name`` — what the camera gets when the user hasn't overridden
    /// it. Always kept in step with the recipe name by ``setName(_:)``.
    ///
    /// A cache, never the authority. ``effectiveCameraName`` regenerates when this is empty, which
    /// covers a row created by an older app version that doesn't know this column. A rename made on
    /// such a version (CloudKit mirroring keeps those clients syncing) leaves this value stale until
    /// ``setName(_:)`` next runs on the recipe.
    ///
    /// This is a second column rather than a `cameraNameIsCustom` flag beside a single name because
    /// existing rows can hold an over-long or emoji `cameraName`, which is unmistakably a deliberate
    /// override. A flag would default to `false` on all of them and the next rename would overwrite
    /// the user's text; lightweight migration can't run code to tell them apart. Here, "custom" is a
    /// `cameraName` with any non-whitespace character (``hasCustomCameraName``), which is correct for
    /// existing rows with no backfill.
    var slotNameDefault: String = ""

    /// Who this recipe is by — the photographer, blog, or channel it came from.
    /// Free text on purpose: attribution in this hobby is a person's name as often as a publication,
    /// and a recipe you wrote yourself simply has none. Nil/empty means unattributed, and every
    /// surface that shows it (detail screen, share card, exported file) drops the line entirely
    /// rather than printing a placeholder.
    var credit: String?

    /// The camera profile the editor filters by — the body whose fields and ranges the recipe is
    /// edited against — shown as "Camera Profile". Never a compatibility verdict: that is
    /// `RecipeCameraFit`, computed from the settings alone. Stored as a `CameraModel.id` string;
    /// nil means "generic / unspecified". The JSON key stays `authoredForModel`.
    var authoredForModelID: String?

    /// The parameter payload. SwiftData stores the `Codable` struct as a composite attribute; see
    /// `RecipeSettings.init(from:)`.
    ///
    /// `private(set)` for the same reason as ``name``: when the name sanitizes to nothing, the
    /// generated slot name is the film simulation's, so ``setSettings(_:)`` keeps it in step.
    private(set) var settings: RecipeSettings = RecipeSettings.neutral

    /// Sample photos for this recipe (up to `maxPhotos`). Owned by the recipe: deleting the recipe
    /// deletes its photos. Stored compressed/resized — see `RecipePhoto` / `PhotoProcessing`.
    /// Optional because CloudKit requires every relationship (including to-many) to be optional;
    /// access via `sortedPhotos`, which treats nil as empty.
    @Relationship(deleteRule: .cascade, inverse: \RecipePhoto.recipe)
    var photos: [RecipePhoto]?

    /// Fields preserved from import that this app version doesn't model.
    /// Stored as encoded JSON `Data` so SwiftData never has to persist the recursive `JSONValue`
    /// enum directly; accessed through the computed `unsupportedFields` below.
    private var unsupportedFieldsData: Data = Data()

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// The recipe's number in the archive ("034"), handed out in order of ``createdAt`` and kept for
    /// good: `RecipeArchiveNumbering` gives a new recipe the next free number and never hands a
    /// deleted recipe's number out again. 0 means not numbered yet, which is what lightweight
    /// migration gives every recipe saved before the column existed.
    var archiveNumber: Int = 0

    init(uuid: UUID = UUID(),
         name: String,
         cameraName: String? = nil,
         notes: String = "",
         tags: [String] = [],
         isFavorite: Bool = false,
         credit: String? = nil,
         authoredForModelID: String? = nil,
         settings: RecipeSettings = .neutral,
         unsupportedFields: [String: JSONValue] = [:],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.uuid = uuid
        self.name = name
        self.cameraName = cameraName
        self.notes = notes
        self.tags = tags
        self.isFavorite = isFavorite
        self.credit = credit
        self.authoredForModelID = authoredForModelID
        self.settings = settings
        self.unsupportedFieldsData = (try? JSONEncoder().encode(unsupportedFields)) ?? Data()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        // Last, so it sees the final `name` and `settings`. Seeding here is what makes every
        // construction site correct without each one having to remember.
        self.slotNameDefault = Self.generatedSlotName(name: self.name, settings: self.settings)
    }

    /// Rename, keeping the generated slot name in step. The only way to set ``name``.
    func setName(_ newName: String) {
        name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        regenerateSlotNameDefault()
    }

    /// Replace the settings, keeping the generated slot name in step. The only way to set
    /// ``settings``.
    func setSettings(_ newSettings: RecipeSettings) {
        settings = newSettings
        regenerateSlotNameDefault()
    }

    private func regenerateSlotNameDefault() {
        slotNameDefault = Self.generatedSlotName(name: name, settings: settings)
    }

    private static func generatedSlotName(name: String, settings: RecipeSettings) -> String {
        CameraSlotName.generate(from: name, fallback: settings.filmSimulation?.displayName)
    }
}

extension Recipe {
    /// Maximum number of sample photos allowed per recipe.
    static let maxPhotos = 5

    /// The fetch for screens that hold the whole recipe table (the Library list, pickers, lookup
    /// tables), with the `photos` relationship prefetched in one batched query.
    ///
    /// Without the prefetch, SwiftData fulfills the to-many fault lazily for every recipe the fetch
    /// returns — one `SELECT … FROM ZRECIPEPHOTO WHERE ZRECIPE = ?` round-trip per row, fired by
    /// the framework itself even when no app code reads `photos` (measured: ~250 queries per list
    /// fetch on a 250-recipe library, repeated on every tab switch).
    static func listFetch(sortBy: [SortDescriptor<Recipe>] = []) -> FetchDescriptor<Recipe> {
        var descriptor = FetchDescriptor<Recipe>(sortBy: sortBy)
        descriptor.relationshipKeyPathsForPrefetching = [\.photos]
        return descriptor
    }

    /// The name to write to the camera slot on push: the user's override when there is one, else the
    /// generated default. Still passed through `CameraModel.sanitizedSlotName` before writing, which
    /// is what clamps a legacy over-long override and lets the push screen say so.
    ///
    /// Three tiers: override → cached default → regenerated from the name on the spot. The last
    /// covers a row whose cache was never filled, which would otherwise push the "Recipe" fallback.
    var effectiveCameraName: String {
        // `contains(where:)` rather than trimming: this runs inside SwiftUI `body` (the push screen
        // calls it per assigned slot) and the trim would allocate a string just to be thrown away.
        // A whitespace-only override counts as absent: it sanitizes to nothing, and the generated
        // default names the bank better than the "Recipe" fallback a push would substitute.
        if let cameraName, cameraName.contains(where: { !$0.isWhitespace }) { return cameraName }
        if !slotNameDefault.isEmpty { return slotNameDefault }
        return Self.generatedSlotName(name: name, settings: settings)
    }

    /// Whether the slot name is the user's own rather than the generated default. Drives the grey /
    /// ink distinction on the editor and detail screens.
    var hasCustomCameraName: Bool { cameraName?.contains(where: { !$0.isWhitespace }) == true }

    /// The credit to print, or nil when the recipe is unattributed. Trimmed so a field left as a
    /// stray space doesn't turn into an empty "Recipe by" line.
    var displayCredit: String? {
        guard let credit else { return nil }
        let trimmed = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Photos in display order.
    var sortedPhotos: [RecipePhoto] {
        (photos ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Preserved unsupported fields, decoded on demand (backed by `unsupportedFieldsData`).
    var unsupportedFields: [String: JSONValue] {
        get { (try? JSONDecoder().decode([String: JSONValue].self, from: unsupportedFieldsData)) ?? [:] }
        set { unsupportedFieldsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// The camera profile this recipe was authored for, if it's a known model.
    var authoredForModel: CameraModel? {
        guard let id = authoredForModelID else { return nil }
        return CameraModelRegistry.shared.model(withID: id)
    }

    /// Short subtitle for the inventory list: film simulation · dynamic range.
    var summary: String {
        let line = RecipeSettingsFormatter.summary(for: settings)
        return line.isEmpty ? "No film simulation set" : line
    }

    /// True if any imported field couldn't be modeled and was preserved verbatim.
    ///
    /// Answered from the raw bytes: the backing data is always a JSON object, so "nothing
    /// preserved" is exactly the two-byte `{}` (or the pre-init empty `Data`). Every recipe list
    /// row shows a badge off this flag, and decoding the JSON per row per body evaluation was
    /// measurable scroll cost for a question the byte count already answers.
    var hasPreservedUnsupportedFields: Bool { unsupportedFieldsData.count > 2 }

    func touch() { updatedAt = Date() }
}
