import XCTest
@testable import FujiCookbook

/// A grid cell held back for type — the piece of `FrameRenderer` the Quarter Grid card stands on.
/// The cells stay indexed by photo, so everything that draws or drags a photo by its index is
/// unaffected; only *where* each photo lands moves.
@MainActor
final class FrameRendererReservedCellsTests: XCTestCase {

    private func options(reservedCells: Int) -> FrameOptions {
        var options = FrameOptions()
        options.canvas = .post
        options.arrangement = .grid
        options.border = 0.05
        options.gap = 0.02
        options.reservedCells = reservedCells
        return options
    }

    private let three = (0..<3).map { _ in
        FrameRenderer.FrameSlot(size: CGSize(width: 3000, height: 2000))
    }

    func testPhotosSkipTheReservedCell() {
        let layout = FrameRenderer.layout(slots: three, options: options(reservedCells: 1))
        let plain = FrameRenderer.layout(slots: three + [three[0]], options: options(reservedCells: 0))

        XCTAssertEqual(layout.cells.count, 3, "three positions remain on a 2 × 2 with one held back")
        XCTAssertEqual(layout.canvas, plain.canvas, "the canvas is the grid's, not the photos'")
        for (index, cell) in layout.cells.enumerated() {
            XCTAssertEqual(cell.opening, plain.cells[index + 1].opening, "photo \(index) sits one position on")
            XCTAssertFalse(cell.image.isNull, "photo \(index) is drawn")
        }
        XCTAssertFalse(layout.cells.contains { $0.opening == plain.cells[0].opening },
                       "nothing occupies the reserved position")
    }

    func testTheCellsAreEqual() {
        let layout = FrameRenderer.layout(slots: three, options: options(reservedCells: 1))
        let first = layout.cells[0].opening.size
        for cell in layout.cells {
            XCTAssertEqual(cell.opening.width, first.width, accuracy: 1)
            XCTAssertEqual(cell.opening.height, first.height, accuracy: 1)
        }
    }

    func testAFourthPhotoHasNoCellAndNoSay() {
        let portrait = FrameRenderer.FrameSlot(size: CGSize(width: 1000, height: 1500))
        let layout = FrameRenderer.layout(slots: three + [portrait], options: options(reservedCells: 1))
        let withoutIt = FrameRenderer.layout(slots: three, options: options(reservedCells: 1))

        XCTAssertEqual(layout.cells.count, 3, "the grid has no fourth position to give")
        XCTAssertEqual(layout.canvas, withoutIt.canvas, "a photo with no cell doesn't size the canvas")
    }

    func testAnOrdinaryFrameIsUnchanged() {
        let layout = FrameRenderer.layout(slots: three + [three[0]], options: options(reservedCells: 0))
        XCTAssertEqual(layout.cells.count, 4)
        XCTAssertTrue(layout.cells.allSatisfy { !$0.image.isNull })
    }
}
