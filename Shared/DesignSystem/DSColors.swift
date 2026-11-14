import SwiftUI
import UIKit

/// One semantic color of the design system: a light and a dark value, each with its own opacity.
/// The hex values stay readable on the token so the tests can check contrast and the gallery can
/// print them. Specification: `docs/fork/design-system.md`.
struct DSColorToken: Identifiable, Equatable {
    let name: String
    let light: UInt32
    let dark: UInt32
    var lightOpacity: Double = 1
    var darkOpacity: Double = 1

    var id: String { name }

    init(name: String, light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.name = name
        self.light = light
        self.dark = dark
        self.lightOpacity = lightOpacity
        self.darkOpacity = darkOpacity
    }

    /// The same value in both modes.
    init(name: String, both: UInt32, opacity: Double = 1) {
        self.init(name: name, light: both, dark: both, lightOpacity: opacity, darkOpacity: opacity)
    }

    var color: Color { Color(uiColor) }

    var uiColor: UIColor {
        let token = self
        return UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dsHex: token.dark, alpha: token.darkOpacity)
                : UIColor(dsHex: token.light, alpha: token.lightOpacity)
        }
    }

    func hex(for scheme: ColorScheme) -> UInt32 { scheme == .dark ? dark : light }
    func opacity(for scheme: ColorScheme) -> Double { scheme == .dark ? darkOpacity : lightOpacity }
}

/// The semantic palette. Views name a role, never a hex value.
///
/// Separate from `Theme`, which the existing screens keep until they move over in phase 5.
enum DSColor {
    enum Tokens {
        static let background = DSColorToken(name: "background", light: 0xE8E7E3, dark: 0x0F0F0F)
        static let surface = DSColorToken(name: "surface", light: 0xF7F7F4, dark: 0x1A1A19)
        static let panel = DSColorToken(name: "panel", light: 0xDAD9D4, dark: 0x232322)
        static let key = DSColorToken(name: "key", light: 0xF7F7F4, dark: 0x2A2A29)
        static let keyShadow = DSColorToken(name: "keyShadow", light: 0x000000, dark: 0x000000,
                                            lightOpacity: 0.18, darkOpacity: 0.60)
        static let separator = DSColorToken(name: "separator", light: 0xC6C5BF, dark: 0x363634)
        static let textPrimary = DSColorToken(name: "textPrimary", light: 0x121212, dark: 0xF2F2EF)
        static let textSecondary = DSColorToken(name: "textSecondary", light: 0x5A5954, dark: 0x9E9D98)
        static let signal = DSColorToken(name: "signal", light: 0x1F3BD6, dark: 0x3350F0)
        static let onSignal = DSColorToken(name: "onSignal", both: 0xFFFFFF)
        static let signalText = DSColorToken(name: "signalText", light: 0x1F3BD6, dark: 0x7D93FF)
        static let knob = DSColorToken(name: "knob", light: 0x1E1E1E, dark: 0xE8E7E3)
        static let knobMark = DSColorToken(name: "knobMark", light: 0x7D93FF, dark: 0x1F3BD6)
        static let ledOff = DSColorToken(name: "ledOff", light: 0xBDBCB6, dark: 0x4A4A47)
        static let ledOK = DSColorToken(name: "ledOK", both: 0x3FD07A)
        /// The system red (`UIColor.systemRed`) as iOS 26 draws it, for the gallery's readout.
        /// `DSColor.danger` is the system color itself, so it follows any later retuning.
        static let danger = DSColorToken(name: "danger", light: 0xFF383C, dark: 0xFF4245)
        /// The ground at 88 % over a material, for floating bars before iOS 26.
        static let chromeGlass = DSColorToken(name: "chromeGlass", light: 0xE8E7E3, dark: 0x0F0F0F,
                                              lightOpacity: 0.88, darkOpacity: 0.88)

        /// Two values the specification gives inline rather than as tokens: the shadow pressed into
        /// an active key ("inset 0 2 0, black 18 %") and the panel's light edge along its top.
        static let keyInset = DSColorToken(name: "keyInset", both: 0x000000, opacity: 0.18)
        static let panelEdge = DSColorToken(name: "panelEdge", light: 0xFFFFFF, dark: 0xFFFFFF,
                                            lightOpacity: 0.7, darkOpacity: 0.08)

        /// The print on a contact sheet frame ("Mono 10 auf Schwarz"): white on black in both modes.
        static let filmEdge = DSColorToken(name: "filmEdge", both: 0x000000)
        static let filmEdgeText = DSColorToken(name: "filmEdgeText", both: 0xFFFFFF)

        static let all = [background, surface, panel, key, keyShadow, separator, textPrimary, textSecondary,
                          signal, onSignal, signalText, knob, knobMark, ledOff, ledOK, danger, chromeGlass,
                          keyInset, panelEdge, filmEdge, filmEdgeText]
    }

    /// Screen ground: the instrument's body.
    static let background = Tokens.background.color
    /// Archive cards and lists.
    static let surface = Tokens.surface.color
    /// The device panel, the search field, the active tab's ground.
    static let panel = Tokens.panel.color
    /// The face of a key that is not active.
    static let key = Tokens.key.color
    /// The hard shadow under a key: offset, no blur.
    static let keyShadow = Tokens.keyShadow.color
    /// Fine lines inside a data sheet, 1 pt.
    static let separator = Tokens.separator.color
    /// Archive frames and table lines, 1.5 pt: the text color itself.
    static let rule = Tokens.textPrimary.color
    static let textPrimary = Tokens.textPrimary.color
    /// Field labels and meta lines.
    static let textSecondary = Tokens.textSecondary.color
    /// Klein blue, the one signal color: an active key, the primary key, a switch that is on, an LED.
    static let signal = Tokens.signal.color
    /// Text and icons on `signal`.
    static let onSignal = Tokens.onSignal.color
    /// The signal as text: object numbers, counters, the active tab.
    static let signalText = Tokens.signalText.color
    /// A dial's body.
    static let knob = Tokens.knob.color
    /// The pointer on a dial.
    static let knobMark = Tokens.knobMark.color
    static let ledOff = Tokens.ledOff.color
    /// A connection that is up.
    static let ledOK = Tokens.ledOK.color
    /// Destructive actions only, through `role: .destructive`, never as decoration. The system red,
    /// so a delete reads the same as in the system's own lists and dialogs.
    static let danger = Color(uiColor: .systemRed)
    /// Tint over a material for floating bars before iOS 26, which has no Liquid Glass.
    static let chromeGlass = Tokens.chromeGlass.color
    static let keyInset = Tokens.keyInset.color
    static let panelEdge = Tokens.panelEdge.color
    static let filmEdge = Tokens.filmEdge.color
    static let filmEdgeText = Tokens.filmEdgeText.color
}

extension UIColor {
    convenience init(dsHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
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
