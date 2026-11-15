import Foundation

/// Build-time switches for features that are written and working but deliberately not exposed yet.
///
/// Unlike ``DiagnosticMode`` — a user-facing toggle in Settings — these aren't discoverable at all:
/// flipping one is a code change. Use this when a feature should stay in the codebase (and keep
/// compiling, so it doesn't rot) while being invisible to everyone using the app.
enum FeatureFlags {
    /// **Reports and feedback** — every way a report, test result or feedback message leaves the
    /// app for `SupportContact.address`. Hidden.
    ///
    /// Darkslide doesn't collect reports yet: the address and the sending flow came from the
    /// original app, and a report should reach someone who has said they'll read it. What the flag
    /// hides is listed once, in `ReportSurfaces`, which every gated view reads instead of this flag:
    /// Send Feedback, the Share button and support address on the diagnostics screen, the "Report a
    /// Problem" prompts on the Camera and Darkroom screens, and the Camera Test, whose whole purpose
    /// is a report for the developer. The diagnostics report itself stays reachable from Settings,
    /// with Copy, because reading it on the device sends nothing.
    ///
    /// Flipping this back on is a privacy change: the privacy policy (`docs/privacy-policy.md`)
    /// says reports aren't collected, so it needs updating in the same change.
    static let reportsEnabled = false
}
