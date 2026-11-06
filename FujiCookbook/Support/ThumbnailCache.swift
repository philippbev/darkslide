import UIKit

/// Decoded list-row thumbnails, keyed by the owning photo's stable uuid.
///
/// `UIImage(data:)` inside a row's `body` re-parses the JPEG on every body evaluation — a scroll
/// through the library repeats the same decodes over and over. Thumbnails are immutable once stored
/// (edits create a new `RecipePhoto`/`CookedVersion` with a new uuid), so a uuid-keyed cache is
/// safe. `NSCache` empties itself under memory pressure; at ~240px a cached thumbnail is ~200KB of
/// bitmap, so the cap keeps the whole cache in the tens of megabytes worst case.
enum ThumbnailCache {
    private static let cache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    /// The decoded thumbnail for `uuid`, decoding `data` on a miss. Returns nil for undecodable bytes.
    static func thumbnail(uuid: UUID, data: Data) -> UIImage? {
        if let hit = cache.object(forKey: uuid as NSUUID) { return hit }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: uuid as NSUUID)
        return image
    }
}
