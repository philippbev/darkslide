import UIKit
import XCTest
@testable import FujiCookbook

/// What the export gets for a recipe card: a layer when the preview shows one, nothing when the
/// preview shows nothing, and an error, never a silently missing card, when rasterising fails.
@MainActor
final class ShareCardRendererTests: XCTestCase {

    private let content: ShareCardContent = {
        let settings = RecipeSettings(
            filmSimulation: .classicNeg,
            grain: GrainEffect(strength: .weak, size: .small),
            whiteBalance: WhiteBalance(mode: .auto, shiftRed: 2, shiftBlue: -4, kelvin: nil),
            dynamicRange: .dr400,
            highlightTone: -1, shadowTone: 1, color: 3, sharpness: -2, highISONR: -4, clarity: 2)
        return ShareCardContent(recipe: Recipe(name: "Coral Neg", credit: "lumenfoto", settings: settings))
    }()

    private func card(_ style: ShareCardStyle) -> RecipeCard {
        RecipeCard(recipeUUID: UUID(), options: ShareCardOptions(style: style))
    }

    private func layout(_ canvas: FrameCanvas) -> FrameRenderer.Layout {
        var options = FrameOptions()
        options.canvas = canvas
        return FrameRenderer.layout(slots: [FrameRenderer.FrameSlot(size: CGSize(width: 3000, height: 4000))],
                                    options: options)
    }

    func testACardThatFitsIsRasterisedIntoItsRect() throws {
        let card = card(.plain)
        let layout = layout(.post)
        let layer = try XCTUnwrap(try ShareCardRenderer.layer(card: card, content: content, layout: layout))
        XCTAssertEqual(layer.rect, ShareCardRenderer.rect(card: card, layout: layout))
    }

    func testAFailedRasterisationThrowsRatherThanDroppingTheCard() {
        XCTAssertThrowsError(try ShareCardRenderer.layer(card: card(.plain), content: content,
                                                         layout: layout(.post)) { _, _ in nil }) { error in
            XCTAssertTrue(error is ShareCardRenderer.RasterisationFailed)
        }
    }

    func testNoContentIsNoLayer() throws {
        let layer = try ShareCardRenderer.layer(card: card(.plain), content: nil, layout: layout(.post)) { _, _ in
            XCTFail("nothing to rasterise")
            return nil
        }
        XCTAssertNil(layer)
    }

    /// A Story foot with ten parameters doesn't fit a square, and the preview shows no card there.
    func testAStyleTheCanvasCantHoldIsNoLayer() throws {
        let layer = try ShareCardRenderer.layer(card: card(.story), content: content, layout: layout(.square)) { _, _ in
            XCTFail("a refused style is never rasterised")
            return nil
        }
        XCTAssertNil(layer)
    }
}
