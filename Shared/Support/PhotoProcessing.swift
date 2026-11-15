import UIKit
import ImageIO

/// Resizes and compresses imported photos so we never persist full-resolution camera files.
///
/// Fuji's 40MP X-Trans V bodies (X-T5, X-T50, X100VI…) write JPEGs of about 25MB, and a recipe
/// holds up to `Recipe.maxPhotos` of them. Each is downscaled to `maxLongEdge` and re-encoded as
/// JPEG, which still looks sharp on screen. Measured 2026-11-05 on 32 X-T50 frames (7728×5152,
/// 24–27MB each) through ImageIO on macOS: 173–370KB full size, 7–16KB thumbnail.
enum PhotoProcessing {
    /// Longest edge of the stored full-size image, in pixels.
    static let maxLongEdge: CGFloat = 1280
    /// JPEG quality for the stored full-size image (0…1).
    static let jpegQuality: CGFloat = 0.7

    /// Longest edge of the inline thumbnail, in pixels.
    static let thumbnailLongEdge: CGFloat = 240
    /// JPEG quality for the inline thumbnail (0…1).
    static let thumbnailQuality: CGFloat = 0.6

    /// The compressed outputs for one imported photo.
    struct Processed {
        /// Resized/compressed full-size JPEG (≈ `maxLongEdge`px long edge).
        let full: Data
        /// Tiny JPEG for thumbnails (≈ `thumbnailLongEdge`px long edge).
        let thumbnail: Data
    }

    /// Resize + compress picked image bytes into our stored representation.
    /// Returns `nil` if the bytes aren't a decodable image.
    static func process(_ data: Data) -> Processed? {
        prepare(data, preservingSmallJPEG: false)
    }

    /// The stored form of a photo from a portable backup, which already holds our compressed JPEGs.
    ///
    /// A JPEG already within `maxLongEdge` keeps its bytes, metadata included, so a restore doesn't
    /// lose quality to another re-encode; anything else is processed as `process` does. Such a JPEG
    /// is never decoded at full size: building the thumbnail is the decode that proves it's an
    /// image. Export checks every photo through this path, so the skipped decode is most of an
    /// export's cost.
    static func importedPhoto(_ data: Data) -> Processed? {
        prepare(data, preservingSmallJPEG: true)
    }

    /// A `thumbnailLongEdge` JPEG of any decodable image: the thumbnail half of `process` and
    /// `importedPhoto`, and called directly when filing developed JPEGs. Goes through ImageIO
    /// (``ImageDownsampler``), which decodes straight to the target size; `UIImage(data:)` and a
    /// redraw would materialise the full bitmap first, all of a 40MP develop to make a 240px icon.
    static func thumbnail(from fullData: Data) -> Data? {
        guard let image = ImageDownsampler.downsample(fullData, maxLongEdge: thumbnailLongEdge) else {
            return nil
        }
        return jpeg(image, quality: thumbnailQuality)
    }

    // MARK: Private

    private static func prepare(_ data: Data, preservingSmallJPEG: Bool) -> Processed? {
        guard let thumbnail = thumbnail(from: data) else { return nil }
        if preservingSmallJPEG, isSmallJPEG(data) { return Processed(full: data, thumbnail: thumbnail) }
        guard let image = ImageDownsampler.downsample(data, maxLongEdge: maxLongEdge),
              let full = jpeg(image, quality: jpegQuality) else { return nil }
        return Processed(full: full, thumbnail: thumbnail)
    }

    private static func isSmallJPEG(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.jpeg",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        return width.doubleValue > 0 && height.doubleValue > 0
            && max(width.doubleValue, height.doubleValue) <= Double(maxLongEdge)
    }

    private static func jpeg(_ image: UIImage, quality: CGFloat) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}
