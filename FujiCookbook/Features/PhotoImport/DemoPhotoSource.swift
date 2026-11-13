import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// A card with a handful of generated JPEGs over two days, so the import screen and both
/// destinations can be walked without a camera. Shown beside the Demo Camera while the diagnostic
/// tools are on.
@MainActor
final class DemoPhotoSource: PhotoSource {
    let displayName = "Demo Card"

    private let now: Date
    private var pictures: [String: Data] = [:]

    init(now: Date = .now) {
        self.now = now
    }

    func open(progress: @escaping @MainActor (CatalogProgress) -> Void,
              partial: @escaping @MainActor ([ImportFile]) -> Void) async throws -> [ImportFile] {
        progress(CatalogProgress(percent: 0, files: 0))
        pictures = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var files: [ImportFile] = []
        for index in 0..<9 {
            // Six frames yesterday afternoon, three this morning.
            let day = index < 6 ? calendar.date(byAdding: .day, value: -1, to: today) ?? today : today
            let date = day.addingTimeInterval(TimeInterval((index < 6 ? 15 : 9) * 3600 + index * 420))
            let name = String(format: "DSCF%04d.JPG", 1284 + index)
            let data = Self.jpeg(index: index, date: date)
            guard let file = ImportFile(id: name, name: name, folder: "DCIM/100_FUJI",
                                        byteSize: Int64(data.count), captureDate: date) else { continue }
            pictures[file.id] = data
            files.append(file)
        }
        progress(CatalogProgress(percent: 100, files: files.count))
        return files
    }

    func thumbnail(for file: ImportFile) async -> CGImage? {
        guard let data = pictures[file.id], let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 360]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func download(_ file: ImportFile, to directory: URL) async throws -> URL {
        guard let data = pictures[file.id] else {
            throw PhotoImportError.downloadFailed(file: file.name, detail: "The demo card no longer lists it.")
        }
        let url = directory.appendingPathComponent(file.name)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PhotoImportError.downloadFailed(file: file.name, detail: error.localizedDescription)
        }
        return url
    }

    func close() async {
        pictures = [:]
    }

    /// A plain picture, different for each frame, with a capture date in its EXIF so the photo
    /// library files it on the day the card says.
    private static func jpeg(index: Int, date: Date) -> Data {
        let simulations: [FilmSimulation] = [.classicChrome, .velvia, .astia, .classicNeg, .eterna,
                                             .realaAce, .nostalgicNeg, .provia, .acros]
        let patches = TestStripPalette.hexValues(for: simulations[index % simulations.count])
        let size = CGSize(width: 1200, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(dsHex: patches[3]).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(dsHex: patches[1]).setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38))
            UIColor(dsHex: patches[4]).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 140 + CGFloat(index) * 90, y: 150, width: 180, height: 180))
        }
        guard let cgImage = image.cgImage else { return Data() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: formatter.string(from: date)],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "FUJIFILM", kCGImagePropertyTIFFModel: "Demo Card"]
        ]
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
