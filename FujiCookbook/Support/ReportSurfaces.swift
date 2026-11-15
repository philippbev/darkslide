import Foundation

/// What the app shows for reports and feedback, decided in one place from
/// `FeatureFlags.reportsEnabled`.
///
/// Views read `ReportSurfaces.current` rather than the flag, so the list of what the flag hides is
/// this type and its tests, not a search through the views. With reports off, nothing in the app
/// offers to send anything to `SupportContact.address`; the diagnostics report stays readable and
/// copyable on the device.
struct ReportSurfaces: Equatable {
    let reportsEnabled: Bool

    static let current = ReportSurfaces(reportsEnabled: FeatureFlags.reportsEnabled)

    /// Settings ▸ Send Feedback.
    var showsSendFeedback: Bool { reportsEnabled }

    /// The Share button, with the support address above it, on the diagnostics screen.
    var showsShareOnReport: Bool { reportsEnabled }

    /// "Report a Problem" prompts outside Settings: on the Camera screen (a slot that changed, values
    /// that didn't read, the always-there row) and in the Darkroom (`ReportProblemRow`).
    var showsReportPrompts: Bool { reportsEnabled }

    /// The guided Camera Test: "Help improve camera support", its saved results, and "Tell Us What
    /// Happened" after a failed connect. Recovery of slots a test changed stays visible regardless,
    /// because it puts the camera's own settings back.
    var showsCameraTest: Bool { reportsEnabled }

    /// The diagnostics screen's title and its row in Settings.
    var diagnosticsTitle: String { reportsEnabled ? "Report a Problem" : "Diagnostics Report" }

    /// The button on the banner after a session ended unexpectedly.
    var unexpectedExitAction: String { reportsEnabled ? "Report a Problem" : "View Diagnostics" }

    /// The Settings section that holds the diagnostics row.
    var helpSectionTitle: String { reportsEnabled ? "Help & Feedback" : "Help" }
}
