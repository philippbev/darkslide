import XCTest
@testable import FujiCookbook

/// The Quarter Grid card (design 2a): a 2 × 2 grid the frame lays out and the card draws around.
/// These pin the two things that make it work — the card's windows are the frame's openings, and
/// the text block fits its cell or the style says no.
@MainActor
final class ShareCardQuarterGridTests: XCTestCase {

    /// Every parameter the card lists, with a credit: the fullest block the style has to hold.
    private func content(name: String, credit: String? = "lumenfoto") -> ShareCardContent {
        let settings = RecipeSettings(
            filmSimulation: .classicNeg,
            grain: GrainEffect(strength: .strong, size: .large),
            colorChromeEffect: .strong,
            colorChromeFXBlue: .strong,
            whiteBalance: WhiteBalance(mode: .auto, shiftRed: 4, shiftBlue: -5, kelvin: nil),
            dynamicRange: .dr400,
            highlightTone: -2, shadowTone: 1, color: 4, sharpness: 0, highISONR: -4, clarity: -4)
        let content = ShareCardContent(recipe: Recipe(name: name, credit: credit, settings: settings))
        XCTAssertEqual(content.lines.count, 11, "the full list")
        return content
    }

    /// The shape the design was drawn at.
    private let native = CGSize(width: 1080, height: 1350)
    private let longName = "Classic Negative Cuban Summer Street"

    // MARK: Geometry

    func testTheDesignsGridAtItsNativeShape() throws {
        let m = try XCTUnwrap(ShareCardStyle.quarterGrid.metrics(canvas: native, content: content(name: "Coral Neg")))

        // 44 all round, 24 between, 484 × 600 cells, 38 held back for the sign-off beyond the mat.
        XCTAssertEqual(m.photoFrames, [CGRect(x: 552, y: 44, width: 484, height: 600),
                                       CGRect(x: 44, y: 668, width: 484, height: 600),
                                       CGRect(x: 552, y: 668, width: 484, height: 600)])
        XCTAssertEqual(m.photoFrame, CGRect(x: 44, y: 44, width: 992, height: 1224), "the union")
        XCTAssertEqual(m.textFrame, CGRect(x: 48, y: 50, width: 460, height: 594), "the first cell, less its padding")
        XCTAssertEqual(m.nameLines, 1)
        XCTAssertEqual(m.textScale, 1, "a short name and every parameter fit as drawn")
    }

    func testTheWindowsAreTheFramesOpenings() throws {
        let content = content(name: "Coral Neg")
        let card = RecipeCard(recipeUUID: UUID(), options: ShareCardOptions(style: .quarterGrid))
        let plan = try XCTUnwrap(ShareCardStyle.quarterGrid.framePlan)

        // What `FrameAndFitView.resolveOptions` hands the frame while the card is on.
        var options = FrameOptions()
        options.canvas = .post
        options.arrangement = plan.arrangement
        options.border = plan.border
        options.gap = plan.gap
        options.reservedCells = plan.reservedCells
        let bands = ShareCardRenderer.reservedBands(card: card, content: content, aspect: 4.0 / 5)
        XCTAssertEqual(bands.top, 0, accuracy: 0.0001, "the mat covers the top; nothing beyond it")
        XCTAssertEqual(bands.bottom, 38.0 / 1350, accuracy: 0.001, "the sign-off's band beyond the mat")
        options.reservedTop = bands.top
        options.reservedBottom = bands.bottom

        let slots = (0..<3).map { _ in FrameRenderer.FrameSlot(size: CGSize(width: 3000, height: 4000)) }
        let layout = FrameRenderer.layout(slots: slots, options: options)
        XCTAssertEqual(layout.cells.count, 3)
        let openings = layout.cells.map(\.opening)

        // Once the frame has laid out, the card takes its openings exactly.
        let snapped = try XCTUnwrap(ShareCardRenderer.metrics(card: card, content: content, layout: layout))
        XCTAssertEqual(snapped.photoFrames, openings)
        // The text cell is the position the photographs skipped, on whole pixels.
        XCTAssertEqual(snapped.textFrame.minX, openings[1].minX + QuarterGridSpec.padLeading * snapped.unit, accuracy: 0.5)
        XCTAssertEqual(snapped.textFrame.maxY, openings[0].maxY, accuracy: 0.5)
        XCTAssertEqual(snapped.textFrame.minX, snapped.textFrame.minX.rounded())

        // And the card's own arithmetic agreed with the frame's to within a pixel anyway.
        let own = try XCTUnwrap(ShareCardStyle.quarterGrid.metrics(canvas: layout.canvas, content: content))
        for (window, opening) in zip(own.photoFrames, openings) {
            XCTAssertEqual(window.minX, opening.minX, accuracy: 1)
            XCTAssertEqual(window.minY, opening.minY, accuracy: 1)
            XCTAssertEqual(window.maxX, opening.maxX, accuracy: 1)
            XCTAssertEqual(window.maxY, opening.maxY, accuracy: 1)
        }
    }

    // MARK: Fitting the text

    func testALongNameAndAFullListShrinkTogether() throws {
        let m = try XCTUnwrap(ShareCardStyle.quarterGrid.metrics(canvas: native, content: content(name: longName)))

        XCTAssertEqual(m.nameLines, 2)
        XCTAssertLessThan(m.textScale, 1, "two lines of name, a credit and eleven rows overrun the cell")
        XCTAssertGreaterThanOrEqual(m.textScale, QuarterGridSpec.minTextScale)

        let needed = QuarterGridSpec.textHeight(rows: 11, nameLines: m.nameLines,
                                                showsCredit: true, showsFilm: true) * m.unit * m.textScale
        XCTAssertLessThanOrEqual(needed, m.textFrame.height + 0.5, "the scaled block fits")
    }

    func testTheCreditBuysItsHeightBack() throws {
        let m = try XCTUnwrap(ShareCardStyle.quarterGrid.metrics(canvas: native, content: content(name: longName, credit: nil)))
        XCTAssertEqual(m.nameLines, 2)
        XCTAssertEqual(m.textScale, 1, "without a credit the same block fits as drawn")
    }

    func testAWideCanvasIsRefused() {
        let wide = CGSize(width: 1000, height: 524)
        XCTAssertNil(ShareCardStyle.quarterGrid.metrics(canvas: wide, content: content(name: longName)),
                     "a 1.91:1 cell can't hold the block above the floor")
    }

    func testTallerShapesFitWithRoomToSpare() throws {
        for size in [CGSize(width: 1080, height: 1440), CGSize(width: 1080, height: 1920)] {
            let m = try XCTUnwrap(ShareCardStyle.quarterGrid.metrics(canvas: size, content: content(name: longName)))
            XCTAssertEqual(m.textScale, 1, "\(size)")
            XCTAssertEqual(m.photoFrames.count, 3)
        }
    }
}
