import UIKit

/// The user's Light or Dark choice, from Settings ▸ Display. `.system`, the default, follows the
/// device's own setting.
///
/// Stored in the App Group suite, where earlier builds put it so a Share Extension could match the
/// app; it stays there so existing installs keep their choice.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    /// Key in `SharedDefaults.suite`. The app binds it with
    /// `@AppStorage(AppearancePreference.key, store: SharedDefaults.suite)`.
    static let key = "shared.appearance"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// For UIKit's `overrideUserInterfaceStyle`, which is how the app's windows apply it.
    /// `.unspecified` defers to the device.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
