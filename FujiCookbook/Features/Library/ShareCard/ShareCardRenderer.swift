import SwiftUI
import UIKit

/// A recipe card placed on a Frame & Fit canvas.
///
/// It names a recipe and a look, belongs to one carousel tile, and is resolved against the frame's
/// layout rather than carrying a canvas of its own.
struct RecipeCard: Equatable {
    /// The recipe on the card. Nil until one is chosen, and nothing is drawn until then.
    var recipeUUID: UUID?
    var options = ShareCardOptions()
    /// Which carousel tile the card sits on, 0-based. A card sliced across a seam is nonsense, so it
    /// belongs to a tile.
    var tile: Int = 0
}

/// Rasterises a recipe card into the layers `FrameRenderer` composites over a frame.
///
/// The seam: rasterise SwiftUI on the main actor, hand plain `UIImage` + `CGRect` pairs to the
/// CoreGraphics pass. `FrameRenderer` needs no knowledge of recipes at all.
@MainActor
enum ShareCardRenderer {

    /// Rasterising the card produced no image, so an export would leave out the card the preview
    /// shows.
    struct RasterisationFailed: Error {}

    /// The card's layer for a given frame layout.
    ///
    /// Nil when there is no recipe content or the canvas can't hold the chosen style: the preview
    /// draws no card then either, so an export without one is what the user sees. Throws
    /// `RasterisationFailed` when the card should be drawn but rasterising it produces no image.
    static func layer(card: RecipeCard,
                      content: ShareCardContent?,
                      layout: FrameRenderer.Layout,
                      rasterise: @MainActor (ShareCardOverlay, CGSize) -> UIImage? = rasterise(_:size:)) throws
        -> FrameRenderer.Overlay? {
        guard let content else { return nil }
        let rect = rect(card: card, layout: layout)
        guard let metrics = metrics(card: card, content: content, layout: layout) else { return nil }
        let overlay = ShareCardOverlay(options: card.options, content: content, metrics: metrics)
        guard let image = rasterise(overlay, rect.size) else { throw RasterisationFailed() }
        return FrameRenderer.Overlay(image: image, rect: rect)
    }

    /// `card` at one point per pixel, transparent around it, in a box of `size`.
    static func rasterise(_ card: ShareCardOverlay, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: card.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// The area of the canvas the card is drawn into.
    ///
    /// A paper style takes the whole tile — it is the page. An overlay style takes only the opening
    /// the photographs occupy, so its type lands *on the picture* rather than out on the mat, which
    /// is the entire premise of writing straight onto a photograph.
    static func rect(card: RecipeCard, layout: FrameRenderer.Layout) -> CGRect {
        let tile = card.tile.clamped(to: 0...max(0, layout.tiles - 1))
        let tileRect = layout.tileRect(tile)
        guard !card.options.style.suppliesPaper else { return tileRect }

        let openings = layout.cells.map(\.opening).filter { $0.intersects(tileRect) }
        guard let first = openings.first else { return tileRect }
        let union = openings.dropFirst().reduce(first) { $0.union($1) }
        return union.intersection(tileRect)
    }

    /// The card resolved against the area it is drawn into.
    static func metrics(card: RecipeCard,
                        content: ShareCardContent,
                        layout: FrameRenderer.Layout) -> ShareCardMetrics? {
        let box = rect(card: card, layout: layout)
        guard box.width > 0, box.height > 0 else { return nil }
        let style = card.options.style
        guard let metrics = style.metrics(canvas: box.size, content: content) else { return nil }
        // A style with a plan had the frame lay its grid out; take the frame's openings as the
        // card's windows so the paper mask and the photo clip can't disagree by a pixel.
        guard let plan = style.framePlan, layout.cells.count >= plan.photoCapacity else { return metrics }
        let openings = layout.cells.prefix(plan.photoCapacity).map {
            $0.opening.offsetBy(dx: -box.minX, dy: -box.minY)
        }
        return style.snapping(metrics, to: openings)
    }

    /// The bands of canvas the card needs held back for paper, as fractions of the canvas height.
    ///
    /// Resolved against a stand-in canvas of the right *shape* rather than the real one, because the
    /// real one isn't known until `FrameRenderer.layout` has run and the bands are one of its
    /// inputs. That is sound precisely because the card is scale-invariant: every size in it is a
    /// fraction of the short edge, so the bands come out the same at any size.
    static func reservedBands(card: RecipeCard,
                              content: ShareCardContent?,
                              aspect: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        guard let content, aspect > 0 else { return (0, 0) }
        let probe = CGSize(width: 1000, height: (1000 / aspect).rounded())
        guard let metrics = card.options.style.metrics(canvas: probe, content: content) else {
            return (0, 0)
        }
        // A style with a plan states its bands itself, off the short edge the way the frame
        // measures its mat. Scaling by the short edge's share of the height turns that into the
        // fraction `FrameOptions` wants without rounding on a probe first — so the pixel the frame
        // rounds to is the pixel the card rounds to.
        if let plan = card.options.style.framePlan {
            let shortEdgeShare = min(aspect, 1)
            return (plan.bandTop * shortEdgeShare, plan.bandBottom * shortEdgeShare)
        }
        let photo = metrics.photoFrame
        let top = max(0, photo.minY) / probe.height
        let bottom = max(0, probe.height - photo.maxY) / probe.height
        return (top, bottom)
    }
}
