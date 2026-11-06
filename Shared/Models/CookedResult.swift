import Foundation
import SwiftData

/// A single source RAF developed in the **Kitchen**, together with the versions produced for it
/// (one per recipe — exactly one for a Develop run, up to three for a Test Kitchen comparison).
/// Persisted with SwiftData so a result survives dismissal and app restart and can be browsed later,
/// rather than living only in a throwaway results sheet.
///
/// Follows the same CloudKit-safe rules as `Recipe`/`RecipePhoto`: every attribute is optional or
/// defaulted, relationships are optional with an explicit inverse.
@Model
final class CookedPhoto {
    var uuid: UUID = UUID()
    /// The source RAF's filename (e.g. "DSCF1234.RAF").
    var sourceFilename: String = ""
    /// Groups every photo developed in one run, so history can show them together.
    var batchID: UUID = UUID()
    var createdAt: Date = Date()
    /// Order within the batch (the order the files were picked).
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \CookedVersion.photo)
    var versions: [CookedVersion]?

    init(uuid: UUID = UUID(), sourceFilename: String, batchID: UUID,
         createdAt: Date = Date(), sortOrder: Int = 0) {
        self.uuid = uuid
        self.sourceFilename = sourceFilename
        self.batchID = batchID
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

extension CookedPhoto {
    /// The history fetch, with the `versions` relationship prefetched in one batched query — same
    /// rationale as `Recipe.listFetch`: without it every fetched photo's to-many fault is fulfilled
    /// lazily, one SQL round-trip per row.
    static func historyFetch(sortBy: [SortDescriptor<CookedPhoto>]) -> FetchDescriptor<CookedPhoto> {
        var descriptor = FetchDescriptor<CookedPhoto>(sortBy: sortBy)
        descriptor.relationshipKeyPathsForPrefetching = [\.versions]
        return descriptor
    }

    /// Versions in display/swipe order (the order their recipes were selected).
    var sortedVersions: [CookedVersion] {
        (versions ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
    var versionCount: Int { versions?.count ?? 0 }
    /// True when this photo came from a Test Kitchen comparison, whose versions are downscaled
    /// previews rather than the full-resolution file a Develop run produces.
    var isComparison: Bool { sortedVersions.contains(where: \.isComparisonPreview) }
}

/// One recipe's developed JPEG for a `CookedPhoto`. The full-resolution developed JPEG is the
/// deliverable, so it's kept in external storage (like `RecipePhoto.imageData`); a tiny inline
/// thumbnail drives list/grid rendering without decoding the full image.
@Model
final class CookedVersion {
    var uuid: UUID = UUID()
    /// The recipe (or camera-slot) name this version was developed with.
    var recipeName: String = ""
    /// The recipe's film simulation, for a compact subtitle.
    var filmSimulation: String?
    /// Full developed JPEG bytes (the product) — kept out of the main store file.
    @Attribute(.externalStorage) var imageData: Data = Data()
    /// Small JPEG (long edge ≈ 240px) for fast thumbnails.
    var thumbnailData: Data = Data()
    /// Recipe fields that were clamped to the camera's range before conversion.
    var clampedFields: [String] = []
    /// Decisions the develop made on the recipe's behalf, in plain language — see
    /// `ConversionResult.notes`. Persisted because the question they answer ("why is this flatter
    /// than the recipe?") is asked of a saved version days later, not of the results sheet that is
    /// already dismissed. Empty for records written before this existed, which reads correctly:
    /// nothing to say.
    var notes: [String] = []
    var sortOrder: Int = 0
    /// Whether the camera developed this at full resolution (a Develop run's deliverable) or
    /// downscaled (a Test Kitchen comparison preview — see `cookMatrix`). nil for records that
    /// predate this field; the UI then makes no claim either way.
    var isFullResolution: Bool?
    /// The `0xD185` conversion-profile field report for this develop (zgrimz/fujifilm-ptp-reference
    /// `docs/06-conversion-profile.md`): base vs. patched, cell by cell, headed by the verification
    /// result when the camera didn't confirm the profile. Kept because a colour problem is only
    /// diagnosable against the profile that produced it, and the in-memory `ConversionResult` is
    /// gone once the results sheet closes. Shown behind Diagnostic Mode (`ComparisonViewer`); nil
    /// for records that predate this field.
    var diagnostics: String?

    /// Inverse of `CookedPhoto.versions`. The photo owns its versions (cascade delete).
    var photo: CookedPhoto?

    init(uuid: UUID = UUID(), recipeName: String, filmSimulation: String?,
         imageData: Data, thumbnailData: Data, clampedFields: [String], sortOrder: Int,
         notes: [String] = [], isFullResolution: Bool? = nil, diagnostics: String? = nil) {
        self.uuid = uuid
        self.recipeName = recipeName
        self.filmSimulation = filmSimulation
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.clampedFields = clampedFields
        self.notes = notes
        self.sortOrder = sortOrder
        self.isFullResolution = isFullResolution
        self.diagnostics = diagnostics
    }
}

extension CookedVersion {
    /// True only when we know the image is a downscaled comparison preview, so callers can label it
    /// without mislabeling legacy records where the fidelity wasn't recorded.
    var isComparisonPreview: Bool { isFullResolution == false }
}
