import Foundation
import ImageIO

enum DevelopOutputError: LocalizedError {
    case ambiguousObjects
    case unexpectedFormat
    case incompleteDownload
    case invalidJPEG
    case recoverySaveFailed

    var errorDescription: String? {
        switch self {
        case .ambiguousObjects:
            return "More than one new object appeared on the camera, so this conversion's JPEG couldn't be identified. The objects were left on the camera."
        case .unexpectedFormat:
            return "The new camera object isn't a JPEG. It was left on the camera."
        case .incompleteDownload:
            return "The downloaded image doesn't match the size reported by the camera. The original was left on the camera."
        case .invalidJPEG:
            return "The downloaded image isn't a complete, readable JPEG. The original was left on the camera."
        case .recoverySaveFailed:
            return "The JPEG couldn't be saved locally. The original was left on the camera. Free some storage before trying again."
        }
    }

    var diagnosticReason: String {
        switch self {
        case .ambiguousObjects: return "ambiguous_conversion_objects"
        case .unexpectedFormat: return "unexpected_conversion_format"
        case .incompleteDownload: return "incomplete_conversion_download"
        case .invalidJPEG: return "invalid_conversion_jpeg"
        case .recoverySaveFailed: return "conversion_save_failed"
        }
    }
}

/// The one copy of a developed JPEG outside the library: written before camera cleanup, read by the
/// store when it saves the batch and by the results sheet on demand. Failed library saves retain this
/// file; successful saves remove only the copies belonging to the saved result IDs.
enum DevelopOutputRecovery {
    /// Scoped storage injection for a run (including tests of disk-write failure), never global
    /// mutable state. Capture before detached image work, which doesn't inherit task locals.
    @TaskLocal static var directoryOverride: URL?

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recovered Develops", isDirectory: true)
    }

    static var destinationDirectory: URL { directoryOverride ?? directory }

    static func validate(_ jpeg: Data, expectedSize: UInt32) throws {
        guard !jpeg.isEmpty, jpeg.count == Int(expectedSize) else {
            throw DevelopOutputError.incompleteDownload
        }
        guard jpeg.starts(with: [0xFF, 0xD8]), jpeg.suffix(2) == Data([0xFF, 0xD9]),
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.jpeg",
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width > 0, image.height > 0,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw DevelopOutputError.invalidJPEG
        }
    }

    static func save(_ jpeg: Data, id: UUID, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("\(id.uuidString).jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: url, options: .atomic)
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.synchronize()
            return url
        } catch {
            throw DevelopOutputError.recoverySaveFailed
        }
    }

    /// The JPEG at `url`, read off the main actor: a full-resolution develop is 25.7 MB on the X-T50
    /// (zgrimz/fujifilm-ptp-reference `docs/05-raw-conversion.md`), and a synchronous read of that
    /// on the main actor stalls the UI for the length of it.
    static func load(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
    }

    static func removeAfterLibrarySave(_ url: URL?) {
        guard let url,
              url.deletingLastPathComponent().standardizedFileURL == destinationDirectory.standardizedFileURL
        else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
