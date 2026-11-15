import Foundation

/// Resource budgets for external recipe files, separate from camera capabilities.
/// `Recipe.maxPhotos` still applies per recipe; the generous batch budgets also accommodate full
/// backups.
struct RecipeImportLimits: Sendable {
    var fileBytes = 256 * 1_048_576
    var recipes = 10_000
    var chapters = 10_000
    var photoBytes = 32 * 1_048_576
    var preparedPhotoBytes = 256 * 1_048_576
    static let standard = RecipeImportLimits()
}

enum RecipeImportValidation {
    static func validate(_ file: RecipeFile, limits: RecipeImportLimits) throws {
        guard file.allRecipes.count <= limits.recipes else {
            throw RecipeFileError.resourceLimit(detail: "This file contains more than \(limits.recipes) recipes. Export smaller recipe groups.")
        }
        guard (file.chapters?.count ?? 0) <= limits.chapters else {
            throw RecipeFileError.resourceLimit(detail: "This file contains more than \(limits.chapters) rolls.")
        }
        for (index, recipe) in file.allRecipes.enumerated() {
            try Task.checkCancellation()
            guard (recipe.photos?.count ?? 0) <= Recipe.maxPhotos else {
                throw RecipeFileError.resourceLimit(detail: "Recipe \(index + 1) contains more than \(Recipe.maxPhotos) sample photos. Remove the extra photos from the source before importing.")
            }
            if let field = RecipeSettingsPortabilityValidation.invalidField(in: recipe.settings) {
                throw RecipeFileError.unsafeNumber(recipe: index + 1, field: field)
            }
        }
    }
}

/// Only value data crosses the preparation worker boundary; SwiftData objects are made by the
/// importing context after the user confirms. `.preserve` keeps an overwritten recipe's existing
/// photos. A caller with nothing prepared passes nil instead, and `RecipeImporter.apply` decodes
/// the portable recipe's own photos.
enum RecipePhotoReplacement {
    case preserve
    case replace([PhotoProcessing.Processed])

    func makePhotos() -> [RecipePhoto] {
        guard case .replace(let photos) = self else { return [] }
        return photos.enumerated().map {
            RecipePhoto(imageData: $0.element.full, thumbnailData: $0.element.thumbnail, sortOrder: $0.offset)
        }
    }
}

struct PreparedRecipePhoto {
    let imageURL: URL
    let thumbnailURL: URL

    func load() throws -> PhotoProcessing.Processed {
        try .init(full: Data(contentsOf: imageURL), thumbnail: Data(contentsOf: thumbnailURL))
    }
}

struct PreparedRecipe {
    /// Encoded photos are removed once staged, avoiding a second in-memory copy of the batch.
    let recipe: PortableRecipe
    /// nil: omitted/all invalid. Empty: explicitly supplied [] (clear on overwrite).
    let photos: [PreparedRecipePhoto]?
    let skippedPhotos: Int

    func photoReplacement() throws -> RecipePhotoReplacement {
        guard let photos else { return .preserve }
        return .replace(try photos.map { try $0.load() })
    }
}

/// One shared owner for the temporary files, retained by the review sheet through the last write.
/// Errors/cancellation release it too. Cleanup is off the UI thread even for photo-heavy backups.
final class RecipeImportStaging {
    let directory: URL
    private static let cleanupQueue = DispatchQueue(label: "recipe-import-cleanup", qos: .utility)
    private static let root: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RecipeImportStaging", isDirectory: true)
        // First use in this process: discard anything a previous crash left behind.
        try? FileManager.default.removeItem(at: url)
        return url
    }()

    init() throws {
        directory = Self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        let directory = directory
        Self.cleanupQueue.async { try? FileManager.default.removeItem(at: directory) }
    }

    func store(_ photo: PhotoProcessing.Processed, recipe: Int, index: Int) throws -> PreparedRecipePhoto {
        let image = directory.appendingPathComponent("\(recipe)-\(index).jpg")
        let thumbnail = directory.appendingPathComponent("\(recipe)-\(index)-thumb.jpg")
        try photo.full.write(to: image, options: .atomic)
        try photo.thumbnail.write(to: thumbnail, options: .atomic)
        return PreparedRecipePhoto(imageURL: image, thumbnailURL: thumbnail)
    }
}

struct PreparedRecipeImport {
    let recipes: [PreparedRecipe]
    let chapters: [PortableChapter]
    let staging: RecipeImportStaging
}

enum RecipeImportPreparation {
    enum Input { case file(URL), data(Data) }
    struct Progress {
        let completed: Int
        let total: Int
    }
    typealias ProgressHandler = (Progress) -> Void

    static func prepare(_ input: Input, limits: RecipeImportLimits = .standard,
                        progress: ProgressHandler = { _ in }) throws -> PreparedRecipeImport {
        let data: Data
        switch input {
        case .file(let url): data = try read(url, limits: limits)
        case .data(let bytes): data = bytes
        }
        return try prepareData(data, limits: limits, progress: progress)
    }

    /// Bounded while reading, including files that grow or have no reliable size metadata. Keeping
    /// the security scope inside this synchronous worker covers the entire read, not just launch.
    static func read(_ url: URL, limits: RecipeImportLimits = .standard) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(1_048_576, limits.fileBytes - data.count + 1)) ?? Data()
            if chunk.isEmpty { return data }
            guard chunk.count <= limits.fileBytes - data.count else {
                throw RecipeFileError.resourceLimit(detail: "This file exceeds the \(limits.fileBytes / 1_048_576) MiB import limit. Export smaller recipe groups or a backup without photos.")
            }
            data.append(chunk)
        }
    }

    private static func prepareData(_ data: Data, limits: RecipeImportLimits,
                                    progress: ProgressHandler) throws -> PreparedRecipeImport {
        try Task.checkCancellation()
        // Transfer ownership of the source array so each recipe's base64 can be released as soon
        // as its photos have been processed. The envelope must not keep a second array reference.
        var file = try RecipePortability.decodeFile(data, limits: limits)
        var source = file.allRecipes
        file.recipes = nil
        file.recipe = nil
        let staging = try RecipeImportStaging()
        var prepared: [PreparedRecipe] = []
        var preparedBytes = 0
        progress(.init(completed: 0, total: source.count))
        for index in source.indices {
            try Task.checkCancellation()
            var photos: [PreparedRecipePhoto] = []
            var skipped = 0
            let supplied = source[index].photos
            for (photoIndex, photo) in (supplied ?? []).enumerated() {
                try Task.checkCancellation()
                // Reject oversized encodings before allocating the decoded bytes. Allow padding.
                guard photo.data.utf8.count <= ((limits.photoBytes + 2) / 3) * 4 else {
                    throw photoSizeError(recipe: index, photo: photoIndex, limits: limits)
                }
                let result: PreparedRecipePhoto? = try autoreleasepool {
                    guard let bytes = Data(base64Encoded: photo.data) else { return nil }
                    guard bytes.count <= limits.photoBytes else {
                        throw photoSizeError(recipe: index, photo: photoIndex, limits: limits)
                    }
                    guard let processed = PhotoProcessing.importedPhoto(bytes) else { return nil }
                    let size = processed.full.count + processed.thumbnail.count
                    guard size <= limits.preparedPhotoBytes - preparedBytes else {
                        throw RecipeFileError.resourceLimit(detail: "The prepared sample photos exceed the \(limits.preparedPhotoBytes / 1_048_576) MiB import budget. Export smaller recipe groups or a backup without photos.")
                    }
                    preparedBytes += size
                    return try staging.store(processed, recipe: index, index: photoIndex)
                }
                if let result { photos.append(result) } else { skipped += 1 }
            }
            // Omission and wholly invalid input preserve existing photos. An intentional [] stays
            // an empty replacement; invalid data must never turn overwrite into silent deletion.
            let replacement = supplied == nil || (skipped > 0 && photos.isEmpty) ? nil : photos
            source[index].photos = nil
            prepared.append(PreparedRecipe(recipe: source[index], photos: replacement, skippedPhotos: skipped))
            progress(.init(completed: index + 1, total: source.count))
        }
        try Task.checkCancellation()
        return PreparedRecipeImport(recipes: prepared, chapters: file.chapters ?? [], staging: staging)
    }

    private static func photoSizeError(recipe: Int, photo: Int, limits: RecipeImportLimits) -> RecipeFileError {
        .resourceLimit(detail: "Photo \(photo + 1) in recipe \(recipe + 1) exceeds the \(limits.photoBytes / 1_048_576) MiB image limit. Resize that image before importing.")
    }
}
