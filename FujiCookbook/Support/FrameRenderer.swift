import CoreGraphics
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// **Frame & Fit** — the geometry and pixel pipeline behind the Kitchen's border tool.
///
/// Unlike the rest of the Kitchen this never talks to a camera: it composites one or more finished
/// photos onto a solid canvas, entirely on device. Three ideas compose:
///
/// - **Canvas** — the shape of the finished thing. `.original` keeps the photo's own ratio and grows
///   the canvas outward to make room for the mat (nothing is cropped). The fixed ratios (1:1, 4:5,
///   9:16, 16:9) instead pin the canvas and crop the photo to *fill* the opening, so the photo slots
///   into the frame rather than floating on it.
/// - **Arrangement** — a uniform rows × columns grid of openings, so a diptych, a triptych and a
///   2 × 2 are one piece of geometry rather than three special cases.
/// - **Tiles** — the canvas repeated horizontally *n* times before it is cut back apart on export.
///   A 4:5 canvas at 2 tiles is an 8:5 composition that exports as two 4:5 images: post them as a
///   carousel and the photo reads as continuous across the swipe. The mat wraps the whole canvas,
///   never the individual tiles, which is what makes the seam invisible.
///
/// The geometry (`layout`) is **linear in the source size**, which is what lets the live preview
/// compose from small proxies and the export run the same numbers at full resolution — no separate
/// preview math to drift out of sync. The one exception is `maxTilePixels`, which clamps an
/// extreme canvas; that clamp is a *uniform* scale of the whole layout, so the composition is
/// identical either way and only the reported pixel count moves.
enum FrameRenderer {

    // MARK: Tuning

    /// Outer mat thickness, as a fraction of the short edge — of the source on `.original`, of a
    /// single tile on the fixed ratios (per *tile*, so a 2-tile pano gets the same visual weight as
    /// a 1-tile post at the same percentage).
    static let borderRange: ClosedRange<CGFloat> = 0...0.20
    /// Gutter between photos, measured off the same reference as the border so equal percentages
    /// read as equal weight. 0 gives the seamless-diptych look.
    static let gapRange: ClosedRange<CGFloat> = 0...0.20
    /// Zoom range within a cell. 1.0 is the photo scaled to exactly fill its opening; zooming in
    /// crops further. It cannot go below 1 — that would pull the photo off the opening.
    static let zoomRange: ClosedRange<CGFloat> = 1...3
    /// Long edge of the on-screen proxies. The preview never touches the full-resolution pixels.
    static let proxyLongEdge: CGFloat = 1600
    /// JPEG quality for the export. High enough to be visually lossless on a 40MP file.
    static let exportQuality: CGFloat = 0.95

    /// Most photos one frame will hold. Past four, a photo in a 4:5 cell is too small to read on a
    /// phone, which is the only place these get looked at.
    static let maxPhotos = 4
    /// Most tiles a canvas may be split into for a carousel.
    static let maxTiles = 3

    /// Ceiling on a single *exported tile*, in pixels.
    ///
    /// Nothing is downsampled in the ordinary case — a 40MP photo with a 5% border exports at ~47MP.
    /// But a thick mat multiplies the canvas against the crop it surrounds, and a wide arrangement
    /// multiplies it again. Past this the whole layout is scaled down uniformly (`Layout.wasCapped`
    /// reports it, so the UI can say so rather than silently shrinking the user's photo).
    ///
    /// The budget is per tile rather than per canvas because tiles are rendered one at a time — the
    /// peak bitmap is one tile, however wide the composition is.
    static let maxTilePixels: CGFloat = 80_000_000

    // MARK: Geometry

    /// One opening in the mat and the photo behind it, in canvas-pixel coordinates.
    struct Cell: Equatable {
        /// The hole the photo shows through. The photo is clipped to this, so anything past it is
        /// cropped rather than painted over the border.
        let opening: CGRect
        /// The photo's frame. At least as large as `opening` and usually larger — the overflow is
        /// the crop. `.null` for a cell with no photo in it, which renders as bare background.
        let image: CGRect
    }

    /// Where everything sits. `canvas` is the whole composition; on export it is cut into `tiles`
    /// equal-width images.
    struct Layout: Equatable {
        let canvas: CGSize
        let tiles: Int
        let cells: [Cell]
        /// True if `maxTilePixels` forced a uniform downscale (see that constant).
        let wasCapped: Bool

        /// The dimensions of one exported image.
        var tileSize: CGSize {
            CGSize(width: (canvas.width / CGFloat(max(1, tiles))).rounded(), height: canvas.height)
        }

        func tileRect(_ index: Int) -> CGRect {
            let width = canvas.width / CGFloat(max(1, tiles))
            return CGRect(x: width * CGFloat(index), y: 0, width: width, height: canvas.height)
        }

        /// X positions of the cuts, for the preview's seam markers.
        var seams: [CGFloat] {
            guard tiles > 1 else { return [] }
            let width = canvas.width / CGFloat(tiles)
            return (1..<tiles).map { width * CGFloat($0) }
        }
    }

    /// One photo's contribution to the layout: how big it is, and how the user has framed it inside
    /// its cell. Kept alongside the photo (rather than indexed by cell) so reordering or removing a
    /// photo carries its crop with it.
    struct FrameSlot: Equatable {
        var size: CGSize
        var zoom: CGFloat = 1
        /// Offset from the cell's centre, as a fraction of the *cell* — resolution-independent, and
        /// meaningful per-cell in a grid.
        var offset: CGSize = .zero

        var isRepositioned: Bool { zoom != 1 || offset != .zero }
    }

    static func layout(slots: [FrameSlot], options: FrameOptions) -> Layout {
        guard let first = slots.first else {
            return Layout(canvas: CGSize(width: 1, height: 1), tiles: 1, cells: [], wasCapped: false)
        }

        let border = options.border.clamped(to: borderRange)
        let gap = options.gap.clamped(to: gapRange)
        let tiles = options.tiles.clamped(to: 1...maxTiles)
        // Never let the bands leave nothing for the photograph; the card refuses those shapes long
        // before this, so the clamp is a guard rather than a policy.
        let reservedTop = options.reservedTop.clamped(to: 0...0.7)
        let reservedBottom = options.reservedBottom.clamped(to: 0...(0.7 - reservedTop))

        // `.original` takes its shape from the photo, so it only means anything for a single,
        // un-tiled photo. Anything else falls back to the default fixed ratio (the UI keeps the two
        // in step, so this is a guard rather than a path users reach).
        guard let tileAspect = options.canvas.tileAspect else {
            if slots.count == 1 && tiles == 1 {
                return capped(originalLayout(slot: first, border: border,
                                             reservedTop: reservedTop, reservedBottom: reservedBottom))
            }
            var fallback = options
            fallback.canvas = .post
            return layout(slots: slots, options: fallback)
        }

        let rows = max(1, options.arrangement.rows)
        let columns = max(1, options.arrangement.columns)
        // Cells held for type come off the front of the grid, so photo *i* sits at position
        // `i + reserved` and `cells` stays indexed by photo — nothing downstream has to know.
        let reserved = options.reservedCells.clamped(to: 0...(rows * columns - 1))
        let positions = rows * columns - reserved

        // Work in a unit canvas of height 1 first: the cell sizes there are fixed by the ratio, the
        // border and the gap alone, independent of how big the canvas turns out to be. That lets us
        // pick the largest canvas none of the photos has to be upscaled to fill, then scale to it.
        let reference = min(tileAspect, 1)          // one tile's short edge, in units of canvas height
        let unitBorder = border * reference
        let unitGap = gap * reference
        let unitCell = CGSize(
            width: (tileAspect * CGFloat(tiles) - 2 * unitBorder - CGFloat(columns - 1) * unitGap) / CGFloat(columns),
            height: (1 - 2 * unitBorder - reservedTop - reservedBottom - CGFloat(rows - 1) * unitGap) / CGFloat(rows))
        guard unitCell.width > 0, unitCell.height > 0 else {
            return capped(originalLayout(slot: first, border: 0))
        }

        // The canvas height at which every photo exactly covers its cell without being upscaled.
        var unit = CGFloat.greatestFiniteMagnitude
        for slot in slots.prefix(positions) {
            let w = max(1, slot.size.width), h = max(1, slot.size.height)
            unit = min(unit, min(w / unitCell.width, h / unitCell.height))
        }
        guard unit.isFinite, unit > 0 else {
            return capped(originalLayout(slot: first, border: border,
                                         reservedTop: reservedTop, reservedBottom: reservedBottom))
        }

        // Derive the tile width first and multiply up, so the canvas divides into whole tiles and
        // the export cuts land on exact pixel boundaries.
        let tileWidth = max(1, (tileAspect * unit).rounded())
        let canvas = CGSize(width: tileWidth * CGFloat(tiles), height: max(1, unit.rounded()))

        // Re-derive the mat from the rounded canvas so it is exactly uniform on all four sides.
        let pixelReference = min(tileWidth, canvas.height)
        let borderPx = (border * pixelReference).rounded()
        let gapPx = (gap * pixelReference).rounded()
        let reservedTopPx = (reservedTop * canvas.height).rounded()
        let reservedBottomPx = (reservedBottom * canvas.height).rounded()
        let cell = CGSize(
            width: (canvas.width - 2 * borderPx - CGFloat(columns - 1) * gapPx) / CGFloat(columns),
            height: (canvas.height - 2 * borderPx - reservedTopPx - reservedBottomPx
                        - CGFloat(rows - 1) * gapPx) / CGFloat(rows))
        guard cell.width >= 1, cell.height >= 1 else {
            return capped(originalLayout(slot: first, border: border))
        }

        let cells = (0..<positions).map { index -> Cell in
            let position = index + reserved
            // Round the two *edges* rather than the origin and the size, so the last row and column
            // land exactly on the mat instead of drifting a pixel past it.
            let left = borderPx + CGFloat(position % columns) * (cell.width + gapPx)
            let top = borderPx + reservedTopPx + CGFloat(position / columns) * (cell.height + gapPx)
            let opening = CGRect(x: left.rounded(), y: top.rounded(),
                                 width: (left + cell.width).rounded() - left.rounded(),
                                 height: (top + cell.height).rounded() - top.rounded())
            guard index < slots.count else { return Cell(opening: opening, image: .null) }
            return Cell(opening: opening, image: place(slots[index], in: opening))
        }

        return capped(Layout(canvas: canvas, tiles: tiles, cells: cells, wasCapped: false))
    }

    /// `.original`: a uniform margin on all four sides of the whole photo, thickness measured off the
    /// *short* edge so a panorama and a portrait get a border that reads the same weight. Note this
    /// grows both dimensions by the same absolute amount, so the canvas ratio moves a little toward
    /// square — that's what a real mat board does. At zoom 1 nothing is cropped: the photo exactly
    /// fills its opening, and `place` reduces to the identity.
    private static func originalLayout(slot: FrameSlot, border: CGFloat,
                                       reservedTop: CGFloat = 0, reservedBottom: CGFloat = 0) -> Layout {
        let w = max(1, slot.size.width), h = max(1, slot.size.height)
        let inset = (min(w, h) * border).rounded()
        // The bands are fractions of the finished canvas, and the canvas is what they grow, so solve
        // for it rather than iterating: canvasH = (photo + mat) / (1 − bands).
        let remaining = max(0.3, 1 - reservedTop - reservedBottom)
        let canvasHeight = ((h + inset * 2) / remaining).rounded()
        let topPx = (reservedTop * canvasHeight).rounded()
        let opening = CGRect(x: inset, y: inset + topPx, width: w, height: h)
        return Layout(canvas: CGSize(width: w + inset * 2, height: canvasHeight),
                      tiles: 1,
                      cells: [Cell(opening: opening, image: place(slot, in: opening))],
                      wasCapped: false)
    }

    /// How big the photo is drawn in a cell: scaled to cover the opening, then the user's zoom.
    static func drawnSize(_ slot: FrameSlot, opening: CGSize) -> CGSize {
        let w = max(1, slot.size.width), h = max(1, slot.size.height)
        let fill = max(opening.width / w, opening.height / h)
        let scale = fill * slot.zoom.clamped(to: zoomRange)
        return CGSize(width: w * scale, height: h * scale)
    }

    /// A slot's zoom and offset pulled back to what the layout will actually honour in a given cell.
    ///
    /// `layout` clamps anyway, so this changes nothing on screen — it exists so the *stored* value
    /// matches the drawn one. Without it, a gesture that ran past the limit would leave the slot
    /// holding a value the renderer silently ignores, and the next drag would start from that dead
    /// travel instead of from the edge.
    static func clamped(_ slot: FrameSlot, opening: CGSize) -> FrameSlot {
        var slot = slot
        slot.zoom = slot.zoom.clamped(to: zoomRange)
        let limit = offsetLimit(opening: opening, drawn: drawnSize(slot, opening: opening))
        slot.offset = CGSize(width: slot.offset.width.clamped(to: -limit.width...limit.width),
                             height: slot.offset.height.clamped(to: -limit.height...limit.height))
        return slot
    }

    /// Scale the photo to cover its opening, apply the user's zoom, then centre it — offset by
    /// however far they dragged, clamped so the opening is always fully covered.
    private static func place(_ slot: FrameSlot, in opening: CGRect) -> CGRect {
        let drawn = drawnSize(slot, opening: opening.size)
        let limit = offsetLimit(opening: opening.size, drawn: drawn)
        let centre = CGPoint(x: opening.midX + opening.width * slot.offset.width.clamped(to: -limit.width...limit.width),
                             y: opening.midY + opening.height * slot.offset.height.clamped(to: -limit.height...limit.height))
        return CGRect(x: centre.x - drawn.width / 2, y: centre.y - drawn.height / 2,
                      width: drawn.width, height: drawn.height)
    }

    /// How far a photo may be dragged from centre, per axis, as a fraction of its own cell.
    ///
    /// The limit is exactly the overflow: the photo may be panned across whatever the crop is hiding
    /// and no further, so the opening is always covered and the mat never shows a bare corner. With
    /// no overflow it pins to 0, which is what makes the reposition gesture safe to leave switched
    /// on in every mode — at `.original` and zoom 1 there is simply nothing to pan.
    static func offsetLimit(opening: CGSize, drawn: CGSize) -> CGSize {
        CGSize(width: max(0, drawn.width - opening.width) / (2 * max(1, opening.width)),
               height: max(0, drawn.height - opening.height) / (2 * max(1, opening.height)))
    }

    /// Enforce `maxTilePixels` by scaling the whole layout uniformly — composition preserved, only
    /// the pixel count moves. Applied last so both canvas branches go through one clamp.
    private static func capped(_ layout: Layout) -> Layout {
        let tileWidth = layout.canvas.width / CGFloat(max(1, layout.tiles))
        let pixels = tileWidth * layout.canvas.height
        guard pixels > maxTilePixels else { return layout }

        let k = sqrt(maxTilePixels / pixels)
        let scaledTile = max(1, (tileWidth * k).rounded())
        func scale(_ rect: CGRect) -> CGRect {
            rect.isNull ? .null : CGRect(x: rect.minX * k, y: rect.minY * k,
                                         width: rect.width * k, height: rect.height * k)
        }
        return Layout(canvas: CGSize(width: scaledTile * CGFloat(max(1, layout.tiles)),
                                     height: max(1, (layout.canvas.height * k).rounded())),
                      tiles: layout.tiles,
                      cells: layout.cells.map { Cell(opening: scale($0.opening), image: scale($0.image)) },
                      wasCapped: true)
    }

    // MARK: Reading the source

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

    /// A downsampled, orientation-corrected copy. Built by ImageIO, which decodes straight to the
    /// target size instead of materialising the full 40MP bitmap first. Used for the live preview
    /// (at `proxyLongEdge`) and, on export, to load each photo at exactly the size it will be drawn
    /// — which is what keeps a four-photo collage from needing four full decodes at once. ImageIO
    /// never upscales here, so a single photo drawn at full size still gets all of its pixels.
    static func proxy(from data: Data, maxLongEdge: CGFloat = proxyLongEdge) -> UIImage? {
        ImageDownsampler.downsample(data, maxLongEdge: maxLongEdge)
    }

    // MARK: Export

    struct Export {
        /// Finished JPEG bytes, ready for the photo library or the share sheet.
        let jpeg: Data
        /// Exported pixel dimensions.
        let size: CGSize
        /// True if `maxTilePixels` forced a uniform downscale (see that constant).
        let wasCapped: Bool
        /// Position in a tiled carousel, 1-based. Always 1 of 1 for an ordinary single export.
        let index: Int
        let count: Int
    }

    /// A piece of type rasterised on the main actor, ready to composite over the photographs.
    struct Overlay: Sendable {
        let image: UIImage
        /// Where it goes, in canvas coordinates.
        let rect: CGRect
    }

    /// Composite at full resolution, one image per tile, in the order they should be posted.
    /// Expensive and blocking — call it off the main actor.
    ///
    /// A transparent PNG needs no special case: the canvas is filled edge to edge *before* the
    /// photos are drawn, so anything transparent lands on the solid background rather than nothing.
    ///
    /// `overlays` arrive already rasterised, in canvas coordinates: the type is laid out by SwiftUI
    /// on the main actor (see `ShareCardRenderer.layer`) so that the export and the preview go
    /// through one layout engine, and this pass only has to composite the result.
    static func render(sources: [Data], slots: [FrameSlot], options: FrameOptions,
                       overlays: [Overlay] = []) -> [Export]? {
        guard !sources.isEmpty else { return nil }

        // Re-read the true pixel sizes rather than trusting the caller's, so the exported geometry
        // is derived from the files themselves.
        var resolved: [FrameSlot] = []
        for (index, data) in sources.enumerated() {
            guard let size = pixelSize(of: data) else { return nil }
            var slot = index < slots.count ? slots[index] : FrameSlot(size: size)
            slot.size = size
            resolved.append(slot)
        }

        let layout = layout(slots: resolved, options: options)
        guard layout.canvas.width >= 1, layout.canvas.height >= 1 else { return nil }

        // Decode each photo at exactly the size it gets drawn — never larger.
        let images: [UIImage?] = sources.enumerated().map { index, data in
            guard index < layout.cells.count else { return nil }
            let frame = layout.cells[index].image
            guard !frame.isNull else { return nil }
            return proxy(from: data, maxLongEdge: max(frame.width, frame.height))
        }
        guard images.contains(where: { $0 != nil }) else { return nil }

        // EXIF (and with it GPS) is only carried when there is exactly one photo. Stamping one
        // photo's camera and location onto a collage of several would be a quiet lie.
        let metadataSource = sources.count == 1 ? sources[0] : nil

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1            // canvas is already in pixels
        format.opaque = true        // the background is always fully opaque

        var exports: [Export] = []
        for tile in 0..<max(1, layout.tiles) {
            let rect = layout.tileRect(tile)
            let output = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
                let cg = context.cgContext
                cg.interpolationQuality = .high
                // Draw the whole composition in canvas coordinates and let the tile's bounds do the
                // cutting; the peak bitmap is one tile, not the full canvas.
                cg.translateBy(x: -rect.minX, y: -rect.minY)
                options.backgroundColor.setFill()
                cg.fill(rect)

                for (index, cell) in layout.cells.enumerated() {
                    guard index < images.count, let image = images[index],
                          !cell.image.isNull, cell.opening.intersects(rect) else { continue }
                    // Clip to the opening so the cropped overflow stops at the mat instead of
                    // covering it — and so a photo can't bleed into its neighbour's cell.
                    cg.saveGState()
                    cg.clip(to: cell.opening)
                    image.draw(in: cell.image)
                    cg.restoreGState()
                }

                // Type goes on last, over everything, and unclipped — a card is already confined
                // to its own tile by `ShareCardRenderer.rect`.
                for overlay in overlays where overlay.rect.intersects(rect) {
                    overlay.image.draw(in: overlay.rect)
                }
            }

            guard let jpeg = encode(output, carryingMetadataFrom: metadataSource) else { return nil }
            exports.append(Export(jpeg: jpeg, size: rect.size, wasCapped: layout.wasCapped,
                                  index: tile + 1, count: max(1, layout.tiles)))
        }
        return exports
    }

    // MARK: Encoding

    /// JPEG-encode the composite, carrying the source's EXIF/TIFF/GPS/IPTC across so a developed
    /// frame keeps its camera, lens, exposure and capture date (same posture as `ImageSaver`).
    /// Orientation is dropped, not copied — it's baked into the pixels by this point.
    private static func encode(_ image: UIImage, carryingMetadataFrom source: Data?) -> Data? {
        guard let cgImage = image.cgImage else { return image.jpegData(compressionQuality: exportQuality) }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return image.jpegData(compressionQuality: exportQuality) }

        var properties = source.map(metadata(from:)) ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality] = exportQuality
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = cgImage.width
        properties[kCGImagePropertyPixelHeight] = cgImage.height

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return image.jpegData(compressionQuality: exportQuality)
        }
        return output as Data
    }

    /// The metadata dictionaries worth carrying over. Deliberately a copy of known sub-dictionaries
    /// rather than the whole property bag, which also holds now-stale facts about the *source*
    /// container (dimensions, colour model, embedded thumbnails).
    private static func metadata(from data: Data) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let all = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [:] }

        var carried: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary] {
            guard var dictionary = all[key] as? [CFString: Any] else { continue }
            if key == kCGImagePropertyTIFFDictionary {
                dictionary[kCGImagePropertyTIFFOrientation] = nil
            }
            carried[key] = dictionary
        }
        return carried
    }
}

// MARK: - Canvas

/// The shape of the finished frame. `.original` is the odd one: it has no fixed ratio, taking its
/// shape from the photo and growing outward to make room for the mat, so nothing is ever cropped.
/// The rest pin the canvas and crop the photo to fill it.
///
/// The fixed ratios are exactly Instagram's published set, deduplicated — a profile photo and a
/// square feed post are both 1:1, and a Story and a Reels cover are both 9:16, so each of those is
/// one canvas here rather than two chips that produce identical files. Ordered squarest-to-tallest
/// and then the wide one, so the row reads as a progression rather than a list.
enum FrameCanvas: String, CaseIterable, Identifiable {
    /// Stays first: it's the default, and a default the user can't see when the row opens reads as
    /// no selection at all.
    case original
    /// 1:1 — square feed post, and the profile photo.
    case square
    /// 4:5 — the long-standing vertical feed post.
    case post
    /// 3:4 — the taller vertical feed post.
    case tall
    /// 9:16 — Stories, and the Reels cover/thumbnail.
    case story
    /// 1.91:1 — the horizontal feed post. Not 16:9: Instagram crops to 1.91:1, so a 16:9 export
    /// would lose a sliver off the top and bottom that the user never chose.
    case wide

    var id: String { rawValue }

    /// Width ÷ height of a *single tile*. `nil` for `.original`.
    var tileAspect: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .post: return 4.0 / 5
        case .tall: return 3.0 / 4
        case .story: return 9.0 / 16
        case .wide: return 1.91
        }
    }

    var label: String {
        switch self {
        case .original: return "Original"
        case .square: return "Square"
        case .post: return "Post"
        case .tall: return "Post Tall"
        case .story: return "Story"
        case .wide: return "Wide"
        }
    }

    var ratioText: String {
        switch self {
        case .original: return "As shot"
        case .square: return "1:1"
        case .post: return "4:5"
        case .tall: return "3:4"
        case .story: return "9:16"
        case .wide: return "1.91:1"
        }
    }

    /// What the ratio is *for*, for the accessibility label — the chip shows a true-to-ratio glyph
    /// and the numbers, which VoiceOver can't convey.
    var use: String {
        switch self {
        case .original: return "the photo's own shape, nothing cropped"
        case .square: return "square feed post or profile photo"
        case .post: return "vertical feed post"
        case .tall: return "taller vertical feed post"
        case .story: return "Story or Reels cover"
        case .wide: return "horizontal feed post"
        }
    }

    /// Splitting into carousel tiles needs a fixed ratio to repeat, and holding several photos needs
    /// a canvas that doesn't depend on which photo you'd take the shape from.
    var supportsTiles: Bool { tileAspect != nil }
    var supportsMultiplePhotos: Bool { tileAspect != nil }

    /// Ratio for the preview glyph, which draws the canvas as a miniature of itself.
    /// `.original` has no ratio of its own, so it borrows a neutral 3:2.
    func glyphAspect(tiles: Int) -> CGFloat { (tileAspect ?? 3.0 / 2) * CGFloat(max(1, tiles)) }
}

// MARK: - Arrangement

/// How the canvas is divided between photos: a uniform grid. Stack, Row and Grid are presets over
/// the same rows × columns geometry, which is why a diptych, a triptych and a 2 × 2 need no
/// special cases anywhere downstream.
struct FrameArrangement: Equatable, Hashable, Identifiable {
    var rows: Int
    var columns: Int

    var id: String { "\(rows)x\(columns)" }
    var cellCount: Int { rows * columns }

    static let single = FrameArrangement(rows: 1, columns: 1)
    static let grid = FrameArrangement(rows: 2, columns: 2)
    static func stack(_ count: Int) -> FrameArrangement { .init(rows: count, columns: 1) }
    static func row(_ count: Int) -> FrameArrangement { .init(rows: 1, columns: count) }

    /// The arrangements worth offering for a given number of photos. Every option holds exactly
    /// that many photos, so switching arrangement never orphans one.
    static func options(for photoCount: Int) -> [FrameArrangement] {
        switch max(1, photoCount) {
        case 1: return [.single]
        case 2: return [.stack(2), .row(2)]
        case 3: return [.stack(3), .row(3)]
        default: return [.grid, .stack(4), .row(4)]
        }
    }

    var label: String {
        if cellCount <= 1 { return "Single" }
        if columns == 1 { return "Stack" }
        if rows == 1 { return "Side by Side" }
        return "Grid"
    }

    /// A sensible default for a set of photos: stack landscapes (each keeps its width), sit
    /// portraits side by side (each keeps its height), grid four. Picking the axis that crops least
    /// means the first thing the user sees is usually the thing they wanted.
    static func best(for sizes: [CGSize]) -> FrameArrangement {
        guard sizes.count > 1 else { return .single }
        guard sizes.count < 4 else { return .grid }
        let landscape = sizes.filter { $0.width >= $0.height }.count
        return landscape * 2 >= sizes.count ? .stack(sizes.count) : .row(sizes.count)
    }
}

// MARK: - Options

/// Everything the user can dial in that isn't tied to a specific photo. Held by the view, consumed
/// by `FrameRenderer`. Per-photo framing lives on `FrameRenderer.FrameSlot` instead, so it travels
/// with the photo when the set is reordered.
struct FrameOptions: Equatable {
    var canvas: FrameCanvas = .original
    /// Horizontal repeats of the canvas, cut back apart on export. 1 is an ordinary single image.
    var tiles: Int = 1
    var arrangement: FrameArrangement = .single
    /// Outer mat, as a fraction of the short edge (of the source on `.original`, of one tile
    /// otherwise).
    var border: CGFloat = 0.05
    /// Gutter between photos, same reference as `border`. Only visible with more than one photo.
    var gap: CGFloat = 0.05
    var background: Color = .white

    /// Bands of canvas height held back at the top and bottom, as fractions, for type that isn't an
    /// overlay — the recipe card's paper block and its header. Zero for an ordinary frame.
    ///
    /// The mat can't express this: a border is uniform on four sides by definition, and a ledger
    /// under a photograph is not a border. Reserving the band here rather than letting the card
    /// simply cover the photo is what keeps the picture *composed* for the space it ends up in — the
    /// cell shrinks, so panning and zooming move the photo inside the window you can actually see,
    /// not inside a canvas half of which is hidden behind paper.
    var reservedTop: CGFloat = 0
    var reservedBottom: CGFloat = 0
    /// Leading cells of the arrangement held back the same way, for a card that takes a cell of the
    /// grid rather than a band of the canvas. The photographs fill the cells that remain, in order;
    /// a photo past the last one has no cell and isn't drawn. Zero for an ordinary frame.
    var reservedCells: Int = 0

    var backgroundColor: UIColor {
        // Force full opacity: the canvas is rendered opaque, and a translucent pick would otherwise
        // composite against black rather than against what the user saw in the preview.
        UIColor(background).withAlphaComponent(1)
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
