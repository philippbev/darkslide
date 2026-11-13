import XCTest
import SwiftUI
@testable import FujiCookbook

/// Guards what the design system promises and no screen can check by eye in both modes at once:
/// text contrast, the two values behind each color, and a test strip for every film simulation.
final class DesignSystemTests: XCTestCase {

    private typealias Tokens = DSColor.Tokens

    /// Text on every ground it is specified for, as (text, ground). The specification asks for at
    /// least 4.5:1.
    private let textPairs: [(DSColorToken, DSColorToken)] = [
        (Tokens.textPrimary, Tokens.background),
        (Tokens.textPrimary, Tokens.surface),
        (Tokens.textPrimary, Tokens.surfaceSecondary),
        (Tokens.textSecondary, Tokens.background),
        (Tokens.textSecondary, Tokens.surface),
        (Tokens.onAccent, Tokens.accent),
        (Tokens.accentText, Tokens.background),
        (Tokens.accentText, Tokens.surface),
        (Tokens.accentText, Tokens.accentSoft),
        // A selected chip inverts: paper on ink.
        (Tokens.background, Tokens.textPrimary)
    ]

    func testTextContrastHoldsInLightAndDark() {
        for (text, ground) in textPairs {
            for scheme in [ColorScheme.light, .dark] {
                let ratio = DSContrast.ratio(text.hex(for: scheme), ground.hex(for: scheme))
                XCTAssertGreaterThanOrEqual(ratio, 4.5,
                    "\(text.name) on \(ground.name) in \(scheme) is \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    func testContrastArithmeticMatchesKnownValues() {
        XCTAssertEqual(DSContrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.001)
        XCTAssertEqual(DSContrast.ratio(0xFFFFFF, 0xFFFFFF), 1, accuracy: 0.001)
        // #767676 is the lightest gray that holds 4.5:1 on white.
        XCTAssertEqual(DSContrast.ratio(0x767676, 0xFFFFFF), 4.54, accuracy: 0.01)
    }

    func testEveryColorResolvesToItsLightAndDarkValue() {
        for token in Tokens.all {
            for (style, expected) in [(UIUserInterfaceStyle.light, token.light), (.dark, token.dark)] {
                let resolved = UIColor(token.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                let hex = UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8
                    | UInt32((blue * 255).rounded())
                XCTAssertEqual(hex, expected, "\(token.name) in style \(style.rawValue)")
                XCTAssertEqual(alpha, token.opacity, accuracy: 0.001, "\(token.name) opacity")
            }
        }
    }

    func testTokenNamesAreUnique() {
        XCTAssertEqual(Set(Tokens.all.map(\.name)).count, Tokens.all.count)
    }

    func testEveryFilmSimulationHasATestStripFromShadowsToHighlights() {
        for simulation in FilmSimulation.allCases {
            let patches = TestStripPalette.hexValues(for: simulation)
            XCTAssertEqual(patches.count, TestStripPalette.patchCount, "\(simulation)")
            let luminances = patches.map(DSContrast.relativeLuminance)
            XCTAssertEqual(luminances, luminances.sorted(), "\(simulation) doesn't run dark to light")
            XCTAssertEqual(Set(patches).count, patches.count, "\(simulation) repeats a patch")
        }
        XCTAssertEqual(TestStripPalette.colors(for: nil).count, TestStripPalette.patchCount)
    }

    func testSpacingSitsOnTheFourPointGrid() {
        for step in DSSpacing.scale {
            XCTAssertEqual(step.value.truncatingRemainder(dividingBy: 4), 0, step.name)
        }
        XCTAssertEqual(DSSpacing.scale.map(\.value), DSSpacing.scale.map(\.value).sorted())
    }

    func testControlsMeetTheTouchTarget() {
        XCTAssertGreaterThanOrEqual(DSSize.touchTarget, 44)
        XCTAssertGreaterThanOrEqual(DSSize.primaryButtonHeight, DSSize.touchTarget)
        XCTAssertGreaterThanOrEqual(DSSize.settingsRowHeight, DSSize.touchTarget)
    }

    func testSignedValuesUseARealMinusSign() {
        XCTAssertEqual(DSValueFormat.signed(2), "+2")
        XCTAssertEqual(DSValueFormat.signed(-5), "\u{2212}5")
        XCTAssertEqual(DSValueFormat.signed(0), "0")
        XCTAssertFalse(DSValueFormat.signed(-1).contains("-"), "a hyphen is not a minus sign")
    }
}
