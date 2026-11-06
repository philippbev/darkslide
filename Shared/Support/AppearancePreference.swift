import UIKit

/// The user's Light or Dark choice, from Settings ▸ Display. `.system`, the default, follows the
/// device's own setting.
///
/// Stored in the App Group suite rather than `UserDefaults.standard` so the Share Extension can
/// match the app: someone who picked Light in the app shouldn't get a dark scan sheet.
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

    /// For UIKit's `overrideUserInterfaceStyle`, which is how both the app's windows and the Share
    /// Extension apply it. `.unspecified` defers to the device.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The stored choice, read once by the Share Extension when its sheet opens.
    static var current: AppearancePreference {
        SharedDefaults.suite?.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .system
    }
}
