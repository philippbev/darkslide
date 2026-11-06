import XCTest
import UIKit
import ImageIO
import Darwin
@testable import FujiCookbook

/// Synthetic release-scale checks: no user recipes, photographs, or private fixture files.
/// Timing and sampled process footprint are evidence, not environment-dependent pass thresholds.
final class RecipeImportScaleTests: XCTestCase {
    func testTenThousandRecipeBackupPreparesWithoutPhotoPayloads() async throws {
        let count = 10_000
        let data = try autoreleasepool {
            let recipes = (0..<count).map { index in
                PortableRecipe(name: "Synthetic recipe \(index)", settings: .neutral)
            }
            return try RecipePortability.encode(.many(recipes))
        }
        var finalProgress: RecipeImportPreparation.Progress?
        let started = Date()
        let before = footprint()
        var sampledPeak = before
        var prepared: PreparedRecipeImport? = try RecipeImportPreparation.prepare(.data(data)) { progress in
            finalProgress = progress
            // Sampling every 100 recipes avoids making the measurement dominate a light import.
            if progress.completed % 100 == 0 { self.updatePeak(&sampledPeak) }
        }
        updatePeak(&sampledPeak)
        report(label: "10,000 recipes without photos", seconds: Date().timeIntervalSince(started),
               inputBytes: data.count, stagedBytes: 0, before: before, sampledPeak: sampledPeak)

        XCTAssertEqual(prepared?.recipes.count, count)
        XCTAssertEqual(finalProgress?.completed, count)
        XCTAssertEqual(finalProgress?.total, count)
        XCTAssertEqual(prepared?.recipes.first?.recipe.name, "Synthetic recipe 0")
        XCTAssertEqual(prepared?.recipes.last?.recipe.name, "Synthetic recipe 9999")
        XCTAssertTrue(prepared?.recipes.allSatisfy { $0.recipe.photos == nil && $0.photos == nil && $0.skippedPhotos == 0 } == true)
        let directory = try XCTUnwrap(prepared?.staging.directory)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        prepared = nil
        await assertEventuallyRemoved(directory)
    }

    func testPhotoHeavyBackupStagesTensOfMiBAndReleasesItsFiles() async throws {
        let jpeg = try syntheticJPEG(width: 1280, height: 960)
        let base64 = jpeg.base64EncodedString()
        // At least 24 MiB of encoded photographs, using valid five-photo recipes. The deterministic
        // texture has photographic entropy; it avoids a tiny flat-color JPEG masquerading as load.
        let bytesPerRecipe = max(1, base64.utf8.count * Recipe.maxPhotos)
        let recipeCount = max(6, (24 * 1_048_576 + bytesPerRecipe - 1) / bytesPerRecipe)
        let data = try autoreleasepool {
            let photos = (0..<Recipe.maxPhotos).map { _ in PortablePhoto(data: base64) }
            let recipes = (0..<recipeCount).map { index in
                PortableRecipe(name: "Synthetic photo recipe \(index)", settings: .neutral, photos: photos)
            }
            return try RecipePortability.encode(.many(recipes))
        }
        XCTAssertGreaterThanOrEqual(data.count, 24 * 1_048_576)
        XCTAssertLessThan(data.count, RecipeImportLimits.standard.fileBytes)

        let started = Date()
        let before = footprint()
        var sampledPeak = before
        var finalProgress: RecipeImportPreparation.Progress?
        var prepared: PreparedRecipeImport? = try RecipeImportPreparation.prepare(.data(data)) { progress in
            finalProgress = progress
            self.updatePeak(&sampledPeak)
        }
        updatePeak(&sampledPeak)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(prepared?.recipes.count, recipeCount)
        XCTAssertEqual(finalProgress?.completed, recipeCount)
        XCTAssertEqual(finalProgress?.total, recipeCount)
        XCTAssertTrue(prepared?.recipes.allSatisfy { $0.recipe.photos == nil && $0.skippedPhotos == 0 } == true,
                      "review data must not retain the original base64 strings")
        let directory = try XCTUnwrap(prepared?.staging.directory)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        XCTAssertEqual(files.count, recipeCount * Recipe.maxPhotos * 2)
        var stagedBytes = 0
        for file in files {
            stagedBytes += try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }
        XCTAssertLessThanOrEqual(stagedBytes, RecipeImportLimits.standard.preparedPhotoBytes)
        for recipe in prepared?.recipes ?? [] {
            XCTAssertEqual(recipe.photos?.count, Recipe.maxPhotos)
            for photo in recipe.photos ?? [] {
                try autoreleasepool {
                    let loaded = try photo.load()
                    XCTAssertEqual(loaded.full, jpeg, "already normalized backup JPEGs retain their original bytes")
                    XCTAssertLessThanOrEqual(try longestEdge(loaded.full), Int(PhotoProcessing.maxLongEdge))
                    XCTAssertLessThanOrEqual(try longestEdge(loaded.thumbnail), Int(PhotoProcessing.thumbnailLongEdge))
                    XCTAssertFalse(loaded.thumbnail.isEmpty)
                }
            }
        }
        report(label: "\(recipeCount) recipes / \(recipeCount * Recipe.maxPhotos) embedded 1280px JPEGs",
               seconds: elapsed, inputBytes: data.count, stagedBytes: stagedBytes,
               before: before, sampledPeak: sampledPeak)
        prepared = nil
        await assertEventuallyRemoved(directory)
    }

    private func syntheticJPEG(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt32 = 0x46554A49
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            // Deterministic colored texture, generated locally; no image download or fixture asset.
            for channel in 0..<3 {
                state ^= state << 13; state ^= state >> 17; state ^= state << 5
                pixels[pixel + channel] = UInt8(truncatingIfNeeded: state)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                         bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try XCTUnwrap(UIImage(cgImage: image).jpegData(compressionQuality: 0.93))
    }

    private func longestEdge(_ data: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? NSNumber).intValue
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? NSNumber).intValue
        return max(width, height)
    }

    private func assertEventuallyRemoved(_ directory: URL, file: StaticString = #filePath, line: UInt = #line) async {
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: directory.path)
        }, object: nil)
        await fulfillment(of: [removed], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), file: file, line: line)
    }

    private func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private func updatePeak(_ peak: inout UInt64?) {
        guard let current = footprint() else { return }
        peak = max(peak ?? 0, current)
    }

    private func report(label: String, seconds: TimeInterval, inputBytes: Int, stagedBytes: Int,
                        before: UInt64?, sampledPeak: UInt64?) {
        let description = "\(label): preparation \(String(format: "%.3f", seconds))s; "
            + "JSON \(inputBytes) bytes; staged \(stagedBytes) bytes; "
            + "process footprint before \(before.map(String.init) ?? "unavailable") bytes; "
            + "maximum sampled footprint \(sampledPeak.map(String.init) ?? "unavailable") bytes. "
            + "Footprint includes the test host and input, is sampled at progress callbacks, and is not a peak-memory guarantee."
        print("[RecipeImportScale] \(description)")
        let evidence = XCTAttachment(string: description)
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}
