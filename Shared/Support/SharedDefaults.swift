import Foundation

/// The App Group `UserDefaults` suite. Holds the appearance choice and the archive numbering.
///
/// The suite is named by the App Group because earlier builds shared it with a Share Extension;
/// it keeps that name so existing installs keep their settings.
enum SharedDefaults {
    static let suite = UserDefaults(suiteName: AppIdentifiers.appGroup)
}
