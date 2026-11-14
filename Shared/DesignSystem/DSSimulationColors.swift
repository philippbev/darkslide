import SwiftUI

/// How a film simulation shows in the design system: a short code and a fixed color, the only
/// color besides the signal blue. Filter variants share their base's, so the filter is a value in
/// the data sheet rather than a color of its own.
///
/// On the existing `FilmSimulation` so there is one list of simulations.
struct DSSimulationStyle: Equatable {
    /// "PRV", "CC", "ACR".
    let code: String
    /// The color field or column.
    let fill: DSColorToken
    /// Text on `fill`.
    let text: DSColorToken
}

extension FilmSimulation {
    /// The simulation whose code and color a filter variant takes.
    var dsBase: FilmSimulation {
        switch self {
        case .acros, .acrosYe, .acrosR, .acrosG: return .acros
        case .monochrome, .monochromeYe, .monochromeR, .monochromeG: return .monochrome
        default: return self
        }
    }

    var dsStyle: DSSimulationStyle {
        func solid(_ code: String, _ fill: UInt32, _ text: UInt32) -> DSSimulationStyle {
            DSSimulationStyle(code: code,
                              fill: DSColorToken(name: code, both: fill),
                              text: DSColorToken(name: "\(code) text", both: text))
        }
        // Black and white flip with the mode: ink on paper, paper on ink.
        func monochrome(_ code: String) -> DSSimulationStyle {
            DSSimulationStyle(code: code,
                              fill: DSColorToken(name: code, light: 0x121212, dark: 0xF2F2EF),
                              text: DSColorToken(name: "\(code) text", light: 0xFFFFFF, dark: 0x121212))
        }
        switch self {
        case .provia: return solid("PRV", 0x8FB8E8, 0x121212)
        case .velvia: return solid("VLV", 0xD61F69, 0xFFFFFF)
        case .astia: return solid("AST", 0xF4B6C8, 0x121212)
        case .classicChrome: return solid("CC", 0x7E9488, 0x121212)
        case .classicNeg: return solid("CN", 0xE3A82B, 0x121212)
        case .nostalgicNeg: return solid("NN", 0xE8743B, 0x121212)
        case .realaAce: return solid("RA", 0x3FA06A, 0x121212)
        case .eterna: return solid("ETR", 0x2E6B5C, 0xFFFFFF)
        case .proNegStd: return solid("PNS", 0xB9B3A6, 0x121212)
        case .proNegHi: return solid("PNH", 0xC98F84, 0x121212)
        case .eternaBleachBypass: return solid("EBB", 0x8E9A92, 0x121212)
        case .sepia: return solid("SEP", 0x8A5A3C, 0xFFFFFF)
        case .acros, .acrosYe, .acrosR, .acrosG: return monochrome("ACR")
        case .monochrome, .monochromeYe, .monochromeR, .monochromeG: return monochrome("MON")
        }
    }

    var dsCode: String { dsStyle.code }
    var dsFill: Color { dsStyle.fill.color }
    var dsText: Color { dsStyle.text.color }
}

/// A recipe with no film simulation: the panel gray, with a dash for the code.
enum DSNoSimulation {
    static let code = "—"
    static let fill = DSColor.panel
    static let text = DSColor.textSecondary
}
