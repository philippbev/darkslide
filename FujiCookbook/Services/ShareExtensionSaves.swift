import Foundation
import SwiftData

/// Recipes the Share Extension saved straight to the store, brought into the app's view of it.
@MainActor
enum ShareExtensionSaves {
    /// Pick up recipes the Share Extension saved: anything it wrote to the store while this
    /// process was backgrounded is invisible to a `ModelContext` that has already loaded.
    static func adopt(into context: ModelContext) {
        guard SharedDefaults.suite?.bool(forKey: SharedDefaults.libraryChangedKey) == true else { return }
        SharedDefaults.suite?.set(false, forKey: SharedDefaults.libraryChangedKey)
        // Drop every cached object so the next fetch reads what the extension actually committed.
        // `rollback()` also discards this context's pending inserts, deletes and edits (Apple,
        // `ModelContext.rollback()`). The context is the container's main one, which autosaves
        // after every change and at scene and view lifecycle points (`ModelContext.autosaveEnabled`),
        // and this runs at launch and on return to the foreground before anything here writes, so
        // nothing is expected to be pending; an edit autosave has not yet flushed would be lost.
        context.rollback()
        AppLog.info(.data, "Reloaded the library after a Share Extension save")
    }
}
