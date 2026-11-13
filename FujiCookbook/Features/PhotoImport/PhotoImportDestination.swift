import CoreLocation
import Foundation
import Photos

/// Where imported photos go.
enum PhotoImportDestination: Equatable {
    case photoLibrary
    /// A folder the user picked in Files: on the device, in iCloud Drive, or on a drive plugged in.
    case folder(URL)

    var label: String {
        switch self {
        case .photoLibrary: return "Photo Library"
        case .folder(let url): return url.lastPathComponent
        }
    }
}

/// Writes one frame's downloaded files to a destination. A frame goes in whole or not at all.
///
/// `position` is where the frame was taken, when the import placed it. JPEG and HEIF files
/// already carry it by then where ImageIO could add it (`GeoTagWriter.embed`); the destination
/// covers what they can't.
protocol PhotoImportWriter {
    func write(_ files: [(file: ImportFile, url: URL)], position: GeoPoint?) async throws
}

extension PhotoImportDestination {
    var writer: PhotoImportWriter {
        switch self {
        case .photoLibrary: return PhotoLibraryImportWriter()
        case .folder(let url): return FolderImportWriter(folder: url)
        }
    }
}

/// Adds a frame to the photo library as one asset, from the files as the camera wrote them: no
/// re-encoding, so EXIF, the maker notes and the RAF survive. Requires
/// `NSPhotoLibraryAddUsageDescription`; add-only access is enough.
struct PhotoLibraryImportWriter: PhotoImportWriter {
    func write(_ files: [(file: ImportFile, url: URL)], position: GeoPoint?) async throws {
        guard await Self.authorize() else { throw PhotoImportError.photoLibraryDenied }
        let resources = Self.resources(for: files.map(\.file))
        let location = position?.location
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            // The asset's own location, which is what Photos maps and searches by. It also places a
            // RAF-only frame, whose file carries none.
            if let location { request.location = location }
            for (index, entry) in files.enumerated() {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = entry.file.name
                request.addResource(with: resources[index], fileURL: entry.url, options: options)
            }
        }
    }

    /// The role each file plays in the asset, in the order given. A RAF beside a JPEG or HEIF is
    /// the alternate, which is how the library keeps a RAW+JPEG pair as one photo; a RAF alone is
    /// the photo.
    static func resources(for files: [ImportFile]) -> [PHAssetResourceType] {
        let hasRendered = files.contains { $0.kind == .jpeg || $0.kind == .heif }
        return files.map { file in
            switch file.kind {
            case .movie: return .video
            case .raw: return hasRendered ? .alternatePhoto : .photo
            case .jpeg, .heif: return .photo
            }
        }
    }

    private static func authorize() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default: return false
        }
    }
}

/// Copies a frame's files into a folder under their own names. A file already there with the same
/// size is taken as the same file and left alone; a different one of the same name is kept, and the
/// new file gets a counter.
///
/// With a position, a RAF gets an XMP sidecar beside it, and so does a JPEG or HEIF that ImageIO
/// couldn't write the position into.
struct FolderImportWriter: PhotoImportWriter {
    let folder: URL

    func write(_ files: [(file: ImportFile, url: URL)], position: GeoPoint?) async throws {
        // A folder from the document picker is security-scoped; one the app owns isn't, and the
        // call then returns false, which is fine.
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        var copied: [URL] = []
        do {
            for entry in files {
                guard let target = Self.target(for: entry.file, in: folder, manager: manager) else { continue }
                try manager.copyItem(at: entry.url, to: target)
                copied.append(target)
                if let position, entry.file.kind == .raw || !GeoTagWriter.hasPosition(target),
                   entry.file.kind != .movie,
                   let sidecar = try GeoTagWriter.writeSidecar(position, besideFileNamed: target.lastPathComponent, in: folder) {
                    copied.append(sidecar)
                }
            }
        } catch {
            // Whole or not at all: a JPEG without its RAF would look imported and not be.
            copied.forEach { try? manager.removeItem(at: $0) }
            throw PhotoImportError.destinationUnavailable(error.localizedDescription)
        }
    }

    /// Where to copy `file`, or nil when the folder already holds it.
    static func target(for file: ImportFile, in folder: URL, manager: FileManager = .default) -> URL? {
        let stem = file.stem, ext = (file.name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(file.name)
        var counter = 2
        while manager.fileExists(atPath: candidate.path) {
            let size = (try? manager.attributesOfItem(atPath: candidate.path)[.size] as? NSNumber)?.int64Value
            if size == file.byteSize { return nil }
            candidate = folder.appendingPathComponent("\(stem) (\(counter)).\(ext)")
            counter += 1
        }
        return candidate
    }
}

/// Remembers the destination folder between launches as a security-scoped bookmark.
enum PhotoImportFolderBookmark {
    static let key = "photoImport.destinationFolder"

    static func save(_ url: URL, to defaults: UserDefaults = .standard) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else { return }
        defaults.set(data, forKey: key)
    }

    /// Nil when nothing was saved, or the folder is gone: a drive that isn't plugged in.
    static func load(from defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale { save(url, to: defaults) }
        return url
    }
}
