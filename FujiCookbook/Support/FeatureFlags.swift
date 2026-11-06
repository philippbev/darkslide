import Foundation

/// Build-time switches for features that are written and working but deliberately not exposed yet.
///
/// Unlike ``DiagnosticMode`` — a user-facing toggle in Settings — these aren't discoverable at all:
/// flipping one is a code change. Use this when a feature should stay in the codebase (and keep
/// compiling, so it doesn't rot) while being invisible to everyone using the app.
enum FeatureFlags {
    /// **Ideas** — the AI-backed recipe recommender (`RecommenderView`, `RecipeRecommender`,
    /// `IdeaSeed`). Hidden.
    ///
    /// The feature is intact; only its entry points are gated on this flag, at four checks: the
    /// Ideas tab in `RootView` (once in the iOS 18 `Tab` tab bar and once in the legacy `tabItem`
    /// one), the "Fill Out with Ideas…" row in `ChapterDetailView`, and the Recipe Ideas model
    /// picker in `SettingsView`. Everything else that mentions Ideas (the result screen's "Refine
    /// These Ideas…" button, past recommendations stored in SwiftData) is only reachable from
    /// inside those, so it goes quiet with them. Set this to `true` to bring the whole experience
    /// back — no other *code* change is needed, and saved recommendations are still there.
    ///
    /// **Flipping this is a privacy release gate, not just a UI change.** Ideas sends the user's
    /// shooting brief plus their *entire recipe library* — names, settings, notes, tags — to their
    /// AI provider (`RecipeRecommender`), and no shipped privacy surface describes that payload.
    /// Before a build ships with this true, all four must be updated in the same release: the
    /// privacy policy's AI section, the Settings ▸ AI Features copy, the App Store Connect privacy
    /// answers, and PrivacyInfo.xcprivacy if the payload's categories change. The Settings ▸ iCloud
    /// Sync copy needs a line too: `Recommendation` is in the synced schema, so saved results sync
    /// — but that sentence names a tab nobody can reach while this is false, which is why it isn't
    /// there now.
    ///
    /// The Settings item is easy to mis-scope, so read this before ticking it off. The consent
    /// alert and the AI Features footer name no payload — they say "your data" — so Ideas does not
    /// make either of them *false*, and wording that already covers it is not evidence the work is
    /// done. What both surfaces do is offer importing a recipe from a screenshot as *the example*,
    /// and someone consenting on the strength of that example would not expect their whole library
    /// to go too. What the gate wants is Ideas named as a second example, not a noun swapped.
    static let ideasEnabled = false
}
