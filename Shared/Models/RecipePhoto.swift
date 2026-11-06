import Foundation
import SwiftData

/// A sample photo attached to a `Recipe` (up to `Recipe.maxPhotos` per recipe).
///
/// Photos are always stored **compressed and resized** (see `PhotoProcessing`) — never at the
/// camera's full sensor resolution — so a handful of samples per recipe stays in the low single-digit
/// megabytes. The large `imageData` blob is kept in SwiftData external storage so it never bloats the
/// main store file; a tiny `thumbnailData` is kept inline for cheap list/grid rendering.
///
/// `thumbnailData` is sized for small fixed-size icons (list rows, editor strip) only. Anything that
/// draws a photo large — the detail-page hero, the full-screen viewer — must use `imageData`.
@Model
final class RecipePhoto {
    /// Stable identity, used for reconciling edits and for export/import round-tripping.
    /// Not `.unique` (CloudKit forbids unique constraints). Defaults satisfy CloudKit's rule that
    /// every attribute be optional or defaulted; `init` sets real values.
    var uuid: UUID = UUID()

    /// Compressed, resized JPEG bytes (long edge ≈ 1280px). Stored outside the main DB file
    /// (and synced as a CloudKit asset when iCloud is enabled).
    @Attribute(.externalStorage) var imageData: Data = Data()

    /// A small JPEG (long edge ≈ 240px) for fast thumbnails without decoding the full image.
    var thumbnailData: Data = Data()

    /// Display order within the recipe (0-based).
    var sortOrder: Int = 0

    var addedAt: Date = Date()

    /// Inverse of `Recipe.photos`. The recipe owns its photos (cascade delete).
    var recipe: Recipe?

    init(uuid: UUID = UUID(),
         imageData: Data,
         thumbnailData: Data,
         sortOrder: Int,
         addedAt: Date = Date()) {
        self.uuid = uuid
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.sortOrder = sortOrder
        self.addedAt = addedAt
    }
}
