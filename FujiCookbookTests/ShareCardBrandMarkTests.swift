import SwiftUI
import XCTest
@testable import FujiCookbook

/// Every card signs off with the brand mark in the brand kit's colour for the ground it sits on:
/// green on paper and beside ink type, mint beside light type over a photograph. The mark is the
/// only thing on any card drawn in either colour, so finding it in the rendered card finds the mark.
@MainActor
final class ShareCardBrandMarkTests: XCTestCase {

    private static let green: UInt32 = 0x2E6B4A
    private static let mint: UInt32 = 0x86D5AC

    private let content: ShareCardContent = {
        let settings = RecipeSettings(
            filmSimulation: .classicNeg,
            grain: GrainEffect(strength: .weak, size: .small),
            whiteBalance: WhiteBalance(mode: .auto, shiftRed: 2, shiftBlue: -4, kelvin: nil),
            dynamicRange: .dr400,
            highlightTone: -1, shadowTone: 1, color: 3)
        return ShareCardContent(recipe: Recipe(name: "Coral Neg", credit: "lumenfoto", settings: settings),
                                recipeNumber: 4)
    }()

    func testThePaperCardsSignOffInGreen() throws {
        for style in [ShareCardStyle.feed, .specimen, .quarterGrid] {
            let pixels = try markPixels(ShareCardOptions(style: style))
            XCTAssertGreaterThan(pixels[Self.green, default: 0], 50, "\(style.title) draws a green mark")
            XCTAssertEqual(pixels[Self.mint, default: 0], 0, "\(style.title) draws no mint")
        }
    }

    func testTheStoryCardSignsOffInMint() throws {
        let pixels = try markPixels(ShareCardOptions(style: .story), canvas: CGSize(width: 1080, height: 1920))
        XCTAssertGreaterThan(pixels[Self.mint, default: 0], 50)
        XCTAssertEqual(pixels[Self.green, default: 0], 0)
    }

    /// Plain's tone says which ground it writes on: light type for a dark photograph, ink for a
    /// bright one.
    func testThePlainCardsMarkFollowsItsTone() throws {
        let light = try markPixels(ShareCardOptions(style: .plain, tone: .light))
        XCTAssertGreaterThan(light[Self.mint, default: 0], 50, "mint beside light type")
        XCTAssertEqual(light[Self.green, default: 0], 0)

        let ink = try markPixels(ShareCardOptions(style: .plain, tone: .dark))
        XCTAssertGreaterThan(ink[Self.green, default: 0], 50, "green beside ink type")
        XCTAssertEqual(ink[Self.mint, default: 0], 0)
    }

    // MARK: Helpers

    /// How many opaque pixels of the rendered card are within a hair of each mark colour.
    private func markPixels(_ options: ShareCardOptions,
                            canvas: CGSize = CGSize(width: 1080, height: 1350)) throws -> [UInt32: Int] {
        let metrics = try XCTUnwrap(options.style.metrics(canvas: canvas, content: content))
        let renderer = ImageRenderer(content: ShareCardOverlay(options: options, content: content, metrics: metrics))
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try XCTUnwrap(renderer.cgImage)

        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)

        var counts: [UInt32: Int] = [:]
        for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] == 255 {
            for target in [Self.green, Self.mint] where matches(bytes, at: offset, target) {
                counts[target, default: 0] += 1
            }
        }
        return counts
    }

    private func matches(_ bytes: [UInt8], at offset: Int, _ hex: UInt32) -> Bool {
        let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF]
        return channels.enumerated().allSatisfy { index, value in
            abs(Int(bytes[offset + index]) - Int(value)) <= 2
        }
    }
}
