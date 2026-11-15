import SwiftUI

/// The top-level tabs. Any screen can switch tabs through `AppRouter.selectedTab` — the Kitchen
/// sends people to Camera to connect, for one.
enum AppTab: Hashable { case library, chapters, kitchen, camera }

/// Shared navigation state for cross-tab deep-linking. `RootView` binds the `TabView`'s selection to
/// `selectedTab`; feature views read it from the environment and set it to jump between tabs.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .library

    /// A photo import asked for from outside the Camera tab — the menu bar's Import Photos. Set
    /// alongside `selectedTab = .camera`; the Camera tab presents it and sets it back to nil.
    ///
    /// Presented there rather than over the whole window: on Mac Catalyst a sheet on `RootView`
    /// crashed SwiftData's `@Query` update in the tabs beneath it (macOS 27.3, 2026-11-13).
    var photoImport: PhotoImportRequest?
}
