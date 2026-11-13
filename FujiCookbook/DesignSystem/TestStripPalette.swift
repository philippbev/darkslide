import SwiftUI

/// The five patches of a film simulation's test strip, shadows to highlights.
///
/// A fixed table for now: one strip per film family, drawn to suggest the look rather than
/// measured from it. Deriving the patches from a recipe's settings is a later step.
enum TestStripPalette {
    static let patchCount = 5

    static func hexValues(for simulation: FilmSimulation) -> [UInt32] {
        switch simulation {
        case .provia: return [0x2A3038, 0x4F5D6E, 0x7C8A9A, 0xAEB8C2, 0xE2E6EA]
        case .velvia: return [0x3A1414, 0x8A2B28, 0xC24A3F, 0xE58A6A, 0xF6D9C2]
        case .astia: return [0x22333F, 0x3F6480, 0x6E97B4, 0xA9C6D8, 0xE6EFF4]
        case .classicChrome: return [0x2B2417, 0x5E4C2A, 0x99804A, 0xC4B083, 0xE9E1CB]
        case .proNegHi: return [0x3A241E, 0x7A4C40, 0xB8826F, 0xDBB3A3, 0xF3E3DB]
        case .proNegStd: return [0x3B2F2A, 0x75625A, 0xA68C80, 0xCDBBB2, 0xEEE6E1]
        case .classicNeg: return [0x2E1D12, 0x70421F, 0xA86B42, 0xD3A27C, 0xF0DCC6]
        case .nostalgicNeg: return [0x3D2A12, 0x8A5F26, 0xC79454, 0xE5C28E, 0xF7E9CF]
        case .eterna: return [0x1C2A25, 0x3D5449, 0x5E7A6E, 0x9DB1A6, 0xDCE5DF]
        case .eternaBleachBypass: return [0x1E2424, 0x4A5454, 0x7D8A8A, 0xB3BCBC, 0xE4E8E8]
        case .realaAce: return [0x24301A, 0x4F6A36, 0x78995E, 0xB0C89B, 0xE6EFD9]
        case .acros, .acrosYe, .acrosR, .acrosG: return [0x0E0E10, 0x3A3A3D, 0x6E6E72, 0xABABAE, 0xEDEDEE]
        case .monochrome, .monochromeYe, .monochromeR, .monochromeG:
            return [0x1A1A1B, 0x4A4A4B, 0x7C7C7D, 0xB2B2B3, 0xE8E8E8]
        case .sepia: return [0x2C2118, 0x6B543D, 0xA88A6B, 0xD2BC9F, 0xF1E7D6]
        }
    }

    /// A strip for a recipe with no film simulation: neutral grays.
    static let neutralHexValues: [UInt32] = [0x1A1A1B, 0x4A4A4B, 0x7C7C7D, 0xB2B2B3, 0xE8E8E8]

    static func colors(for simulation: FilmSimulation?) -> [Color] {
        (simulation.map(hexValues(for:)) ?? neutralHexValues).map { Color(dsHex: $0) }
    }
}
