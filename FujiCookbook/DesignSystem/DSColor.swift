import SwiftUI
import UIKit

/// One semantic color of the fork's design system: a light ("paper") and a dark ("darkroom")
/// value. The hex values stay readable on the token so the tests can check contrast and the
/// gallery can print them. Specification: `docs/fork/design-system.md`.
struct DSColorToken: Identifiable, Equatable {
    let name: String
    let light: UInt32
    let dark: UInt32
    /// The same in both modes; below 1 only for `chromeGlass`.
    var opacity: Double = 1

    var id: String { name }

    var color: Color {
        let light = light, dark = dark, opacity = opacity
        return Color(UIColor { traits in
            UIColor(dsHex: traits.userInterfaceStyle == .dark ? dark : light, alpha: opacity)
        })
    }

    func hex(for scheme: ColorScheme) -> UInt32 { scheme == .dark ? dark : light }
}

/// The semantic palette. Views name a role, never a hex value.
///
/// Separate from `Theme`, which the existing screens keep until they migrate.
enum DSColor {
    enum Tokens {
        static let background = DSColorToken(name: "background", light: 0xF4F2ED, dark: 0x111110)
        static let surface = DSColorToken(name: "surface", light: 0xFFFFFF, dark: 0x1C1B19)
        static let surfaceSecondary = DSColorToken(name: "surfaceSecondary", light: 0xEAE7E0, dark: 0x262522)
        static let separator = DSColorToken(name: "separator", light: 0xDDD9D0, dark: 0x2E2D2A)
        static let textPrimary = DSColorToken(name: "textPrimary", light: 0x1B1A18, dark: 0xF3F0EA)
        static let textSecondary = DSColorToken(name: "textSecondary", light: 0x625E56, dark: 0xA6A096)
        static let accent = DSColorToken(name: "accent", light: 0xC2410C, dark: 0xFF7A45)
        static let onAccent = DSColorToken(name: "onAccent", light: 0xFFFFFF, dark: 0x1B1A18)
        static let accentText = DSColorToken(name: "accentText", light: 0xA8360A, dark: 0xFF9B70)
        static let accentSoft = DSColorToken(name: "accentSoft", light: 0xF6E3D8, dark: 0x3A2117)
        static let success = DSColorToken(name: "success", light: 0x2F8F4E, dark: 0x5BC27A)
        static let chromeGlass = DSColorToken(name: "chromeGlass", light: 0xFFFFFF, dark: 0x1C1B19, opacity: 0.78)

        static let all = [background, surface, surfaceSecondary, separator, textPrimary, textSecondary,
                          accent, onAccent, accentText, accentSoft, success, chromeGlass]
    }

    /// Screen ground.
    static let background = Tokens.background.color
    /// Cards and grouped lists.
    static let surface = Tokens.surface.color
    /// Chips, the search field, round icon buttons, the secondary button.
    static let surfaceSecondary = Tokens.surfaceSecondary.color
    /// Hairlines and borders.
    static let separator = Tokens.separator.color
    static let textPrimary = Tokens.textPrimary.color
    /// Secondary text and labels.
    static let textSecondary = Tokens.textSecondary.color
    /// Safelight, the one accent: the primary button, a toggle that is on, selection.
    static let accent = Tokens.accent.color
    /// Text and icons on `accent`.
    static let onAccent = Tokens.onAccent.color
    /// The accent as text or outline (slot badge, active tab), darker than `accent` in light mode
    /// so it holds 4.5:1 on paper.
    static let accentText = Tokens.accentText.color
    /// The fill behind a hint.
    static let accentSoft = Tokens.accentSoft.color
    /// Connection status.
    static let success = Tokens.success.color
    /// Tint over a material for floating bars before iOS 26, which has no Liquid Glass.
    static let chromeGlass = Tokens.chromeGlass.color
}

extension UIColor {
    convenience init(dsHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(dsHex hex: UInt32) { self.init(UIColor(dsHex: hex)) }
}

/// WCAG 2 contrast arithmetic on hex values, for the tests and the gallery's readout.
enum DSContrast {
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        let a = relativeLuminance(first), b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
