import SwiftUI

/// The top-level tabs. Any screen can switch tabs through `AppRouter.selectedTab` — the Kitchen
/// sends people to Camera to connect, for one.
enum AppTab: Hashable { case library, chapters, ideas, kitchen, camera }

/// A pre-filled request for the Ideas tab. Any screen can hand Ideas a starting point — a Chapter
/// asking to have its free slots filled, or a past result being refined — by setting
/// `AppRouter.ideaSeed` and switching to `.ideas`; `RecommenderView` applies it and clears it.
struct IdeaSeed: Equatable {
    /// Recipes the model must keep, in slot order.
    var anchorUUIDs: [UUID] = []
    /// The shooting brief to pre-fill; may be empty when the anchors are the whole request.
    var brief: String = ""
    /// How many slots the finished set should fill.
    var slotTarget: Int = Chapter.maxSlots
    /// Recipes that were in the result being refined. Any of these the user *doesn't* keep as an
    /// anchor is treated as rejected and withheld from the next request (see `RecommenderView`).
    var previousPickUUIDs: [UUID] = []
    /// The chapter this request came from, so the result can offer to write straight back to it.
    var sourceChapter: SourceChapter?

    /// A chapter a request came from: its id, which the result writes back to, and its name, which
    /// the composer shows.
    struct SourceChapter: Equatable {
        let uuid: UUID
        let name: String

        init(_ chapter: Chapter) {
            uuid = chapter.uuid
            name = chapter.name
        }
    }
}

/// A pre-filled request for Frame & Fit. The recipe screen hands the Kitchen a recipe to build a
/// share card from, the same way `IdeaSeed` hands the Ideas tab a starting point; `FrameAndFitView`
/// applies it once and clears it.
struct FrameSeed: Equatable {
    /// The recipe the card should start on.
    var recipeUUID: UUID
}

/// Shared navigation state for cross-tab deep-linking. `RootView` binds the `TabView`'s selection to
/// `selectedTab`; feature views read it from the environment and set it to jump between tabs.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .library

    /// A pending pre-filled Ideas request. Set alongside `selectedTab = .ideas`; the Ideas tab
    /// consumes it once and sets it back to nil.
    var ideaSeed: IdeaSeed?

    /// A pending pre-filled Frame & Fit request. Set alongside `selectedTab = .kitchen`; Frame & Fit
    /// consumes it once and sets it back to nil.
    var frameSeed: FrameSeed?

    /// A photo import asked for from outside the Camera tab — the menu bar's Import Photos. Set
    /// alongside `selectedTab = .camera`; the Camera tab presents it and sets it back to nil.
    ///
    /// Presented there rather than over the whole window: on Mac Catalyst a sheet on `RootView`
    /// crashed SwiftData's `@Query` update in the tabs beneath it (macOS 27.3, 2026-11-13).
    var photoImport: PhotoImportRequest?
}
