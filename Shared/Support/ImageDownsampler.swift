import CoreGraphics
import ImageIO
import UIKit

/// Decode an image straight to the size it's needed at, without ever materialising the full bitmap.
///
/// Reachable from the Share Extension: an extension's memory budget is far tighter than the app's,
/// and a 40MP share decoded through `UIImage(data:)` allocates ~160MB of backing store before
/// anything resizes it — enough to get jetsammed before the scan begins. ImageIO reads the header,
/// decodes at the requested size, and never holds the full image.
enum ImageDownsampler {

    /// A downsampled, orientation-corrected copy. ImageIO never upscales, so an image already
    /// smaller than `maxLongEdge` comes back with all of its pixels.
    static func downsample(_ data: Data, maxLongEdge: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // bake in the EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxLongEdge.rounded(.up)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
