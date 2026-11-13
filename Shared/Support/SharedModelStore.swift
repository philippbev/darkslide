import Foundation
import SwiftData

/// The one definition of the recipe store, shared by the app and the Share Extension.
///
/// The extension writes recipes directly into the library, so both processes open the *same*
/// SQLite file out of the App Group container. That only works if they agree exactly on the schema
/// and the configuration, which is the entire reason this type exists rather than each target
/// building its own `ModelConfiguration` — a schema that drifts between two processes is a store
/// that fails to open, and it would fail in the extension, where nobody is watching.
///
/// `groupContainer` names the App Group with `.identifier`. The default, `.automatic`, resolves to
/// the first App Group entitlement, which is the same group today, but would make the store's
/// location depend on the order of an entitlements array that two processes rely on.
enum SharedModelStore {

    /// Every `@Model` type in the store. Must stay in step with the model files under `Shared/Models`.
    static let modelTypes: [any PersistentModel.Type] = [
        Recipe.self, Chapter.self, RecipePhoto.self, CookedPhoto.self, CookedVersion.self,
        Recommendation.self
    ]

    static var schema: Schema { Schema(modelTypes) }

    /// The configuration both processes open the store with.
    ///
    /// `cloudKit` has to be the *same answer* in both processes. CloudKit mirroring maintains its own
    /// metadata and leans on persistent history; a second process opening the same store without it
    /// can write rows the mirror never learns about. Both targets carry the iCloud container
    /// entitlement so either answer is available to both — what matters is that they agree, which is
    /// why the extension reads what the app actually did from ``ScanConfiguration`` rather than
    /// deciding for itself.
    static func configuration(cloudKit: Bool) -> ModelConfiguration {
        #if targetEnvironment(macCatalyst)
        // A locally signed Mac build has no App Group (`SharedContainer`): its own store, where
        // the App Group's would be, and never CloudKit, which needs the entitlement it lacks.
        if !SharedContainer.isAppGroup, let container = SharedContainer.url {
            let url = container.appendingPathComponent("Library/Application Support/default.store")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        #endif
        return ModelConfiguration(schema: schema,
                                  groupContainer: .identifier(ScreenshotInbox.appGroupID),
                                  cloudKitDatabase: cloudKit ? .automatic : .none)
    }
}
