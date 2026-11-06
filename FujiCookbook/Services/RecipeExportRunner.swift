import SwiftUI

/// Runs an export off the main actor with progress and cancellation, the way `ImportCoordinator`
/// prepares an import. Checking a backup's photos decodes every one, which on the main actor would
/// hold the screen for seconds on a large library.
///
/// The caller takes the snapshot on the main actor; from there nothing touches SwiftData.
@MainActor
@Observable
final class RecipeExportRunner {
    private(set) var isExporting = false
    private(set) var progress: RecipeExportValidation.Progress?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runID = UUID()

    /// `completion` gets the file, or why there isn't one. It isn't called once the run is
    /// cancelled or replaced by a newer one.
    func start(_ snapshot: RecipeExportSnapshot, named name: String,
               completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
        cancel()
        isExporting = true
        let id = runID
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            try RecipeExporter.export(snapshot, named: name) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.runID == id, self.isExporting else { return }
                    self.progress = progress
                }
            }
        }
        task = Task { [weak self] in
            let result: Result<URL, Error>
            do {
                result = .success(try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                })
            } catch {
                result = .failure(error)
            }
            guard let self, self.runID == id else { return }
            self.isExporting = false
            self.progress = nil
            self.task = nil
            if case .failure(let error) = result, error is CancellationError { return }
            completion(result)
        }
    }

    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        isExporting = false
        progress = nil
    }
}

extension View {
    /// The shared progress overlay while `runner` is exporting.
    func exportProgress(_ runner: RecipeExportRunner) -> some View {
        overlay {
            if runner.isExporting {
                CancellableProgressOverlay(
                    title: "Preparing export…",
                    detail: runner.progress.map { "\($0.completed) of \($0.total) photos checked" },
                    onCancel: runner.cancel)
            }
        }
    }
}
