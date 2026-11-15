import Foundation
import Observation
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Drives the Share Extension: load the shared image, scan it, show what came back, save it.
///
/// This happens *here*, while the user is still looking at the screenshot, rather than being
/// queued for whenever the app next opens. Everything it needs is reachable: the AI settings
/// through ``ScanConfiguration``, the key through the shared Keychain group, and the library itself
/// through ``SharedModelStore``.
///
/// Every path that can't finish here offers the inbox instead (AI not set up, a failed scan, a
/// library the extension can't open, a user who'd rather not wait), and the app scans what it
/// finds there. Only Cancel discards the screenshot.
@MainActor
@Observable
final class ShareScanModel {

    enum Stage {
        case loading
        case scanning(UIImage)
        case review(Draft)
        /// Can't scan here. Carries the reason to show.
        case unavailable(title: String, message: String)
        /// The screenshot couldn't be loaded, scanned or queued. Trying again starts over.
        case failed(image: UIImage?, message: String)
        /// The scan succeeded but the library refused the recipe. Carries the draft as the user left
        /// it, so trying again repeats only the save: starting over would pay the provider for a
        /// second scan and throw away the user's edits.
        case saveFailed(Draft, message: String)
        case saved(name: String, outcome: RecipeImporter.Outcome)
        /// The screenshot went to the inbox instead; the app will pick it up.
        case queued
    }

    /// One extracted recipe, plus whatever the user changes about it before saving.
    struct Draft {
        var recipe: PortableRecipe
        var image: UIImage?
        /// An existing library recipe this looks like, if any.
        var duplicate: DuplicateMatch?
        var resolution: DuplicateResolution = .keepBoth
        var isEditing = false
    }

    private(set) var stage: Stage = .loading

    /// The running scan, so `cancelScan()` can stop it.
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// The App Group settings this run scans under, read by each `start()`. `makeContainer` takes
    /// its iCloud sync choice from here, so the extension opens the store the way the app did.
    @ObservationIgnored private var configuration: ScanConfiguration?

    /// Who the screenshot is sent to, for the scanning stage's disclosure line. `start()` sets
    /// `configuration` before it enters `.scanning`, so the fallback name never shows there.
    var scanProviderName: String { configuration?.provider.displayName ?? "your AI provider" }

    /// Kept so every fallback path can reach the inbox.
    @ObservationIgnored private var imageData: Data?
    @ObservationIgnored private let provider: NSItemProvider?
    @ObservationIgnored private let onFinish: (Bool) -> Void

    /// Shorter than the app's default: this sheet is sitting on top of whatever app the user was
    /// actually in, and a minute of it is not a reasonable thing to ask.
    private static let scanTimeout: TimeInterval = 30

    init(provider: NSItemProvider?, onFinish: @escaping (Bool) -> Void) {
        self.provider = provider
        self.onFinish = onFinish
    }

    // MARK: Loading and scanning

    func start() async {
        guard let provider else {
            stage = .failed(image: nil, message: "That image couldn't be loaded from the share sheet.")
            return
        }
        // Ask for the first image type the provider registered; screenshots arrive as PNG,
        // Photos shares as HEIC/JPEG. The scan re-encodes, so any decodable bytes do.
        let typeID = provider.registeredTypeIdentifiers
            .first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else {
            stage = .failed(image: nil, message: "That image couldn't be loaded from the share sheet.")
            return
        }
        imageData = data

        // Decoded through ImageIO at preview size rather than `UIImage(data:)`: a 40MP share would
        // otherwise allocate its full bitmap here, before the scan has even started.
        let preview = ImageDownsampler.downsample(data, maxLongEdge: 1024)
        guard let preview else {
            stage = .failed(image: nil, message: "That image couldn't be read.")
            return
        }

        guard let config = ScanConfiguration.current(), config.isConfigured else {
            stage = .unavailable(
                title: "AI Scanning Isn't Set Up",
                message: "Turn on AI Features in Darkslide's Settings, add your API key, and pick a model. Until then this screenshot waits in the app.")
            return
        }
        configuration = config
        // Open the store *before* spending money on a scan. Finding out afterwards that the library
        // can't be opened would mean paying for a scan we can't save, and paying again when the app
        // re-scans the file we fell back to queueing.
        do {
            _ = try makeContainer()
        } catch {
            AppLog.error(.data, "Share Extension couldn't open the recipe library — \(AppLog.bounded(error))")
            AppLog.flush()
            stage = .unavailable(
                title: "Can't Reach Your Library",
                message: "Darkslide couldn't open your recipes from here. Save this screenshot and the app will read it the next time you open it.")
            return
        }

        stage = .scanning(preview)
        scan(config: config, preview: preview, data: data)
    }

    private func scan(config: ScanConfiguration, preview: UIImage, data: Data) {
        scanTask = Task { [weak self] in
            do {
                let recipe = try await RecipeScanner.scan(imageData: data,
                                                          provider: config.provider,
                                                          apiKey: config.apiKey,
                                                          modelID: config.modelID,
                                                          timeout: Self.scanTimeout)
                guard !Task.isCancelled else { return }
                self?.present(recipe, preview: preview)
            } catch {
                let reason = (error as? RecipeScanError)?.diagnosticReason ?? "other"
                AppLog.error(.ai, "Share Extension scan failed — \(reason)")
                AppLog.flush()
                guard !Task.isCancelled else { return }
                self?.fail(error, preview: preview)
            }
        }
    }

    private func present(_ recipe: PortableRecipe, preview: UIImage) {
        var draft = Draft(recipe: recipe, image: preview)
        // A library that can't be read here skips the duplicate check, not the review: the save
        // reports the failure.
        if let existing = try? libraryRecipes() {
            draft.duplicate = DuplicateResolver.match(for: recipe, in: existing)
        }
        stage = .review(draft)
    }

    private func fail(_ error: Error, preview: UIImage) {
        stage = .failed(image: preview, message: error.localizedDescription)
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        queueForLater()
    }

    // MARK: Editing

    /// The draft under review, for the editing surface to bind to. No-ops in any other stage.
    var draft: Draft? {
        get { if case .review(let draft) = stage { return draft } else { return nil } }
        set { if let newValue, case .review = stage { stage = .review(newValue) } }
    }

    // MARK: Saving

    func save() {
        guard case .review(let draft) = stage else { return }
        save(draft)
    }

    private func save(_ draft: Draft) {
        do {
            let container = try makeContainer()
            let context = ModelContext(container)
            let existing = try context.fetch(FetchDescriptor<Recipe>())

            // Re-matched against this context: the match made at review time holds a `Recipe` from a
            // different context, and `RecipeImporter.apply` has to mutate one from this one.
            let match = DuplicateResolver.match(for: draft.recipe, in: existing)
            var usedNameKeys = Set(existing.map { RecipeImporter.nameKey($0.name) })
            let result = RecipeImporter.apply(draft.recipe,
                                              resolution: draft.duplicate == nil ? .keepBoth : draft.resolution,
                                              match: match,
                                              into: context,
                                              usedNameKeys: &usedNameKeys)
            try context.save()

            // Only when something actually changed. `.skipped` means the user chose to keep what
            // they already had, so flagging the library as modified would make the app throw away
            // its loaded context to read back exactly what it already has.
            if result.outcome != .skipped {
                // The app's loaded context can't see this write; the flag tells `ShareExtensionSaves`
                // to reset that context.
                SharedDefaults.suite?.set(true, forKey: SharedDefaults.libraryChangedKey)
            }
            stage = .saved(name: result.recipe?.name ?? draft.recipe.name, outcome: result.outcome)
        } catch {
            AppLog.error(.data, "Share Extension couldn't save the scanned recipe — \(AppLog.bounded(error))")
            AppLog.flush()
            stage = .saveFailed(draft, message: "The recipe couldn't be saved: \(error.localizedDescription)")
        }
    }

    // MARK: Retrying

    /// Try Again from a failure stage. A failed save is saved again from the draft it carries; any
    /// other failure starts over from the shared image. No-op in every other stage.
    func retry() async {
        switch stage {
        case .saveFailed(let draft, _):
            save(draft)
        case .failed:
            await start()
        case .loading, .scanning, .review, .unavailable, .saved, .queued:
            return
        }
    }

    // MARK: Fallback

    /// Hand the screenshot to the inbox, for everything that can't be finished here.
    func queueForLater() {
        guard let imageData else {
            finish(saved: false)
            return
        }
        do {
            try ScreenshotInbox.save(imageData)
            stage = .queued
        } catch {
            AppLog.error(.share, "Couldn't save the shared screenshot to the inbox — \(AppLog.bounded(error))")
            AppLog.flush()
            stage = .failed(image: nil, message: error.localizedDescription)
        }
    }

    func finish(saved: Bool) {
        // The confirmation both dismisses itself and offers Done. Whichever comes first finishes the
        // request, and the other must not complete it a second time.
        guard !hasFinished else { return }
        hasFinished = true
        AppLog.flush()
        onFinish(saved)
    }

    @ObservationIgnored private var hasFinished = false

    /// How long a confirmation stays up before dismissing itself. Long enough to read four words,
    /// short enough that nobody reaches for a button first — the point of this flow is to hand the
    /// user back to whatever they were doing.
    static let confirmationDuration: Duration = .milliseconds(1400)

    // MARK: Store

    /// One container per run, built on first use.
    ///
    /// Cached because the duplicate check and the save both need it, and two `ModelContainer`s over
    /// one store URL in one process is something Core Data complains about. Lazy so a screenshot
    /// shared with AI switched off never opens the library.
    @ObservationIgnored private var cachedContainer: ModelContainer?

    private func makeContainer() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        // Mirrors the app with CloudKit on or off; see `SharedModelStore.configuration(cloudKit:)`.
        // `configuration` is set before the first call; `false` matches a store that was never synced.
        let container = try ModelContainer(
            for: SharedModelStore.schema,
            configurations: SharedModelStore.configuration(cloudKit: configuration?.icloudSyncEnabled ?? false))
        cachedContainer = container
        return container
    }

    private func libraryRecipes() throws -> [Recipe] {
        try ModelContext(makeContainer()).fetch(FetchDescriptor<Recipe>())
    }
}
