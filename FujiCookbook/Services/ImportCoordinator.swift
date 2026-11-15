import Foundation
import Observation

/// A batch of recipes awaiting the user's duplicate decisions before they enter the library.
struct PendingImport: Identifiable {
    let id = UUID()
    let recipes: [PortableRecipe]
    /// Chapters carried by a full backup; empty for a plain recipe file.
    let chapters: [PortableChapter]
    /// Where the file came from, for the review sheet's title.
    let sourceName: String
    var preparedRecipes: [PreparedRecipe]? = nil
    /// Retained by both the pending import and its review sheet until all selected writes finish.
    var staging: RecipeImportStaging? = nil
}

/// Turns incoming recipe files into a review: files opened from Files, Mail, Messages or the share
/// sheet. A file that fails preparation surfaces an error and imports nothing.
@MainActor
@Observable
final class ImportCoordinator {
    var pendingImport: PendingImport?
    var importError: String?
    private(set) var isPreparingImport = false
    private(set) var importProgress: RecipeImportPreparation.Progress?

    typealias Preparer = (RecipeImportPreparation.Input, RecipeImportPreparation.ProgressHandler) throws -> PreparedRecipeImport
    @ObservationIgnored private let prepare: Preparer
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var importID = UUID()

    init(prepare: @escaping Preparer = { input, progress in
        try RecipeImportPreparation.prepare(input, progress: progress)
    }) {
        self.prepare = prepare
    }

    @discardableResult
    func load(url: URL) -> Task<Void, Never> {
        start(.file(url), sourceName: url.lastPathComponent)
    }

    @discardableResult
    func load(data: Data, sourceName: String) -> Task<Void, Never> {
        start(.data(data), sourceName: sourceName)
    }

    func cancelImport() {
        importID = UUID()
        preparationTask?.cancel()
        preparationTask = nil
        isPreparingImport = false
        importProgress = nil
    }

    private func start(_ input: RecipeImportPreparation.Input, sourceName: String) -> Task<Void, Never> {
        cancelImport()
        pendingImport = nil
        importError = nil
        isPreparingImport = true
        let id = importID
        let prepare = prepare
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            try Task.checkCancellation()
            return try prepare(input) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.importID == id, self.isPreparingImport else { return }
                    self.importProgress = progress
                }
            }
        }
        let task = Task { [weak self] in
            do {
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self, self.importID == id, !Task.isCancelled else { return }
                self.pendingImport = PendingImport(recipes: result.recipes.map(\.recipe),
                                                   chapters: result.chapters, sourceName: sourceName,
                                                   preparedRecipes: result.recipes, staging: result.staging)
            } catch is CancellationError {
                // Cancellation is an ordinary choice, not an import error.
            } catch {
                guard let self, self.importID == id, !Task.isCancelled else { return }
                if let fileError = error as? RecipeFileError {
                    AppLog.error(.importExport, "Import rejected the file — \(fileError.diagnosticReason)")
                    self.importError = fileError.errorDescription
                } else {
                    AppLog.error(.importExport, "Import failed — \(AppLog.bounded(error))")
                    self.importError = "Couldn't prepare “\(sourceName)”: \(error.localizedDescription)"
                }
            }
            guard let self, self.importID == id else { return }
            self.isPreparingImport = false
            self.importProgress = nil
            self.preparationTask = nil
        }
        preparationTask = task
        return task
    }
}
