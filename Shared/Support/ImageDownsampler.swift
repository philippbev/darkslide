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

    /// The source's pixel dimensions with its EXIF orientation already applied, read from the
    /// container without decoding the pixels.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }

        // Orientations 5–8 are the quarter turns, which swap the axes.
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width)
                                             : CGSize(width: width, height: height)
    }
}
