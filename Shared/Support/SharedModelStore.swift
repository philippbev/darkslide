import Foundation
import SwiftData

/// The one definition of the recipe store: its schema and its configuration.
///
/// The store lives in the App Group container, where earlier builds put it so a Share Extension
/// could write to it. The extension is gone, but the location stays: moving the store would leave
/// every existing install with an empty library.
///
/// `groupContainer` names the App Group with `.identifier`. The default, `.automatic`, resolves to
/// the first App Group entitlement, which is the same group today, but would make the store's
/// location depend on the order of an entitlements array.
enum SharedModelStore {

    /// Every `@Model` type in the store. Must stay in step with the model files under `Shared/Models`.
    static let modelTypes: [any PersistentModel.Type] = [
        Recipe.self, Chapter.self, RecipePhoto.self, CookedPhoto.self, CookedVersion.self,
        Recommendation.self
    ]

    static var schema: Schema { Schema(modelTypes) }

    /// The configuration the app opens the store with.
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
                                  groupContainer: .identifier(AppIdentifiers.appGroup),
                                  cloudKitDatabase: cloudKit ? .automatic : .none)
    }
}
