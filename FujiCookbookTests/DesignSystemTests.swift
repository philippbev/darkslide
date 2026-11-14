import XCTest
import SwiftUI
@testable import FujiCookbook

/// Guards what the design system promises and no screen can check by eye in both modes at once:
/// text contrast, the two values behind each color, a code and color for every film simulation,
/// and the arithmetic behind the barcode and the dial. Specification: `docs/fork/design-system.md`.
final class DesignSystemTests: XCTestCase {

    private typealias Tokens = DSColor.Tokens
    private let schemes: [ColorScheme] = [.light, .dark]

    // MARK: Colors

    /// Text on every ground it is specified for, as (text, ground). The specification asks for at
    /// least 4.5:1.
    private let textPairs: [(DSColorToken, DSColorToken)] = [
        (Tokens.textPrimary, Tokens.background),
        (Tokens.textPrimary, Tokens.surface),
        (Tokens.textPrimary, Tokens.panel),
        (Tokens.textPrimary, Tokens.key),
        (Tokens.textSecondary, Tokens.background),
        (Tokens.textSecondary, Tokens.surface),
        (Tokens.textSecondary, Tokens.panel),
        (Tokens.onSignal, Tokens.signal),
        (Tokens.signalText, Tokens.background),
        (Tokens.caution, Tokens.background),
        (Tokens.caution, Tokens.surface),
        (Tokens.signalText, Tokens.surface),
        (Tokens.filmEdgeText, Tokens.filmEdge)
    ]

    func testTextContrastHoldsInLightAndDark() {
        for (text, ground) in textPairs {
            for scheme in schemes {
                let ratio = DSContrast.ratio(text.hex(for: scheme), ground.hex(for: scheme))
                XCTAssertGreaterThanOrEqual(ratio, 4.5,
                    "\(text.name) on \(ground.name) in \(scheme) is \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    /// The switch's track when on is the text color, so it stands off the ground in both modes. The
    /// v2 draft's fixed #121212 vanished on the dark ground (1.02:1).
    func testSwitchTrackStandsOffTheGround() {
        for scheme in schemes {
            let ratio = DSContrast.ratio(Tokens.textPrimary.hex(for: scheme), Tokens.background.hex(for: scheme))
            XCTAssertGreaterThanOrEqual(ratio, 3, "\(scheme)")
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
            for (style, scheme) in [(UIUserInterfaceStyle.light, ColorScheme.light), (.dark, .dark)] {
                let resolved = token.uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                let hex = UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8
                    | UInt32((blue * 255).rounded())
                XCTAssertEqual(hex, token.hex(for: scheme), "\(token.name) in \(scheme)")
                XCTAssertEqual(alpha, token.opacity(for: scheme), accuracy: 0.001, "\(token.name) opacity in \(scheme)")
            }
        }
    }

    func testTokensMatchTheSpecification() {
        XCTAssertEqual(Tokens.signal.light, 0x1F3BD6)
        XCTAssertEqual(Tokens.signal.dark, 0x3350F0)
        XCTAssertEqual(Tokens.signalText.dark, 0x7D93FF)
        XCTAssertEqual(Tokens.keyShadow.lightOpacity, 0.18)
        XCTAssertEqual(Tokens.keyShadow.darkOpacity, 0.60)
        XCTAssertEqual(Tokens.chromeGlass.light, Tokens.background.light)
        XCTAssertEqual(Tokens.chromeGlass.dark, Tokens.background.dark)
        XCTAssertEqual(Tokens.chromeGlass.lightOpacity, 0.88)
        XCTAssertEqual(Tokens.caution.light, 0x9A5200)
        XCTAssertEqual(Tokens.caution.dark, 0xE08C34)
    }

    /// `danger` is the system red itself, which iOS may retune between versions, so this reads the
    /// red the system gives now. On a key the label is bold 17 pt, large text, so 3:1 applies.
    func testDangerIsTheSystemRedAndReadsOnAKey() {
        for (style, scheme) in [(UIUserInterfaceStyle.light, ColorScheme.light), (.dark, .dark)] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let resolved = UIColor(DSColor.danger).resolvedColor(with: traits)
            let system = UIColor.systemRed.resolvedColor(with: traits)
            XCTAssertEqual(hex(of: resolved), hex(of: system), "\(scheme)")
            let ratio = DSContrast.ratio(hex(of: system), Tokens.key.hex(for: scheme))
            XCTAssertGreaterThanOrEqual(ratio, 3, "danger on key in \(scheme)")
        }
    }

    private func hex(of color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    func testTokenNamesAreUnique() {
        XCTAssertEqual(Set(Tokens.all.map(\.name)).count, Tokens.all.count)
    }

    // MARK: Film simulations

    func testEverySimulationHasACodeAndReadableText() {
        for simulation in FilmSimulation.allCases {
            let style = simulation.dsStyle
            XCTAssertFalse(style.code.isEmpty, "\(simulation)")
            XCTAssertLessThanOrEqual(style.code.count, 3, "\(simulation)")
            for scheme in schemes {
                let ratio = DSContrast.ratio(style.text.hex(for: scheme), style.fill.hex(for: scheme))
                XCTAssertGreaterThanOrEqual(ratio, 4.5,
                    "\(style.code) in \(scheme) is \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    func testFilterVariantsShareTheirBase() {
        for simulation in FilmSimulation.allCases {
            XCTAssertEqual(simulation.dsStyle, simulation.dsBase.dsStyle, "\(simulation)")
        }
        XCTAssertEqual(FilmSimulation.acrosR.dsCode, "ACR")
        XCTAssertEqual(FilmSimulation.monochromeYe.dsCode, "MON")
    }

    func testEachBaseSimulationHasItsOwnCode() {
        let bases = Set(FilmSimulation.allCases.map(\.dsBase))
        XCTAssertEqual(Set(bases.map(\.dsCode)).count, bases.count)
    }

    func testSimulationColorsMatchTheSpecification() {
        let expected: [FilmSimulation: (String, UInt32, UInt32)] = [
            .provia: ("PRV", 0x8FB8E8, 0x121212), .velvia: ("VLV", 0xD61F69, 0xFFFFFF),
            .astia: ("AST", 0xF4B6C8, 0x121212), .classicChrome: ("CC", 0x7E9488, 0x121212),
            .classicNeg: ("CN", 0xE3A82B, 0x121212), .nostalgicNeg: ("NN", 0xE8743B, 0x121212),
            .realaAce: ("RA", 0x3FA06A, 0x121212), .eterna: ("ETR", 0x2E6B5C, 0xFFFFFF),
            .proNegStd: ("PNS", 0xB9B3A6, 0x121212), .proNegHi: ("PNH", 0xC98F84, 0x121212),
            .eternaBleachBypass: ("EBB", 0x8E9A92, 0x121212), .sepia: ("SEP", 0x8A5A3C, 0xFFFFFF)
        ]
        for (simulation, (code, fill, text)) in expected {
            let style = simulation.dsStyle
            XCTAssertEqual(style.code, code)
            XCTAssertEqual(style.fill, DSColorToken(name: code, both: fill), code)
            XCTAssertEqual(style.text.light, text, code)
        }
        let acros = FilmSimulation.acros.dsStyle
        XCTAssertEqual([acros.fill.light, acros.fill.dark, acros.text.light, acros.text.dark],
                       [0x121212, 0xF2F2EF, 0xFFFFFF, 0x121212])
    }

    /// The specification keeps every simulation color away from the signal blue, so blue always
    /// means "active". Measured against `signal` as specified; Provia's pale blue does come close
    /// to `signalText` in dark mode (#8FB8E8 against #7D93FF), an open point in the specification.
    func testNoSimulationColorIsCloseToTheSignal() {
        func distance(_ a: UInt32, _ b: UInt32) -> Double {
            let channels = [16, 8, 0].map { (Double((a >> $0) & 0xFF), Double((b >> $0) & 0xFF)) }
            return channels.map { pow($0.0 - $0.1, 2) }.reduce(0, +).squareRoot()
        }
        for simulation in FilmSimulation.allCases {
            for scheme in schemes {
                let fill = simulation.dsStyle.fill.hex(for: scheme)
                XCTAssertGreaterThan(distance(fill, Tokens.signal.hex(for: scheme)), 100,
                                     "\(simulation.dsCode) in \(scheme)")
            }
        }
    }

    // MARK: Components

    func testBarcodeIsTheSameForTheSameSeed() {
        XCTAssertEqual(DSBarcode.widths(for: "034"), DSBarcode.widths(for: "034"))
        XCTAssertNotEqual(DSBarcode.widths(for: "034"), DSBarcode.widths(for: "035"))
        XCTAssertEqual(DSBarcode.widths(for: "").count, DSBarcode.elementCount)
    }

    func testBarcodeWidthsStayBetweenOneAndThreePoints() {
        for seed in ["", "034", UUID().uuidString, "Lua de Mel"] {
            let widths = DSBarcode.widths(for: seed)
            XCTAssertTrue(widths.allSatisfy { (1...3).contains($0) }, seed)
            XCTAssertGreaterThan(Set(widths).count, 1, "\(seed) gives a flat pattern")
        }
    }

    func testKnobRunsFromStopToStop() {
        XCTAssertEqual(DSKnobScale.angle(for: 0), -135)
        XCTAssertEqual(DSKnobScale.angle(for: 0.5), 0)
        XCTAssertEqual(DSKnobScale.angle(for: 1), 135)
        XCTAssertEqual(DSKnobScale.angle(for: -1), -135, "held at the stop")
        XCTAssertEqual(DSKnobScale.angle(for: 2), 135, "held at the stop")
        XCTAssertEqual(DSKnobScale.tickAngles.count, 11)
        XCTAssertEqual(DSKnobScale.tickAngles.first, -135)
        XCTAssertEqual(DSKnobScale.tickAngles.last, 135)
    }

    func testKnobMapsLinearValuesAndSteps() {
        // Color and tone: −4…+4 linear.
        XCTAssertEqual(DSKnobScale.position(of: -4, in: -4...4), 0)
        XCTAssertEqual(DSKnobScale.position(of: 0, in: -4...4), 0.5)
        XCTAssertEqual(DSKnobScale.angle(for: DSKnobScale.position(of: 2, in: -4...4)), 67.5)
        // Grain Off / Weak / Strong: evenly spread.
        XCTAssertEqual((0..<3).map { DSKnobScale.position(ofStep: $0, count: 3) }, [0, 0.5, 1])
        XCTAssertEqual(DSKnobScale.position(ofStep: 0, count: 1), 0.5)
    }

    // MARK: Metrics and formats

    func testSpacingSitsOnTheFourPointGrid() {
        for step in DSSpacing.scale {
            XCTAssertEqual(step.value.truncatingRemainder(dividingBy: 4), 0, step.name)
        }
        XCTAssertEqual(DSSpacing.scale.map(\.value), DSSpacing.scale.map(\.value).sorted())
    }

    func testRadiiAndLinesMatchTheSpecification() {
        XCTAssertEqual(DSRadius.archive, 0)
        XCTAssertEqual(DSRadius.key, 14)
        XCTAssertEqual(DSRadius.panel, 18)
        XCTAssertEqual(DSRadius.switchTrack, 8)
        XCTAssertEqual(DSRadius.switchKnob, 6)
        XCTAssertEqual(DSLine.rule, 1.5)
        XCTAssertEqual(DSLine.hairline, 1)
    }

    func testControlsMeetTheTouchTarget() {
        XCTAssertGreaterThanOrEqual(DSSize.touchTarget, 44)
        XCTAssertGreaterThanOrEqual(DSSize.iconKey, DSSize.touchTarget)
        XCTAssertGreaterThanOrEqual(DSSize.primaryKeyHeight, DSSize.touchTarget)
    }

    func testSignedValuesUseARealMinusSign() {
        XCTAssertEqual(DSValueFormat.signed(2), "+2")
        XCTAssertEqual(DSValueFormat.signed(-5), "\u{2212}5")
        XCTAssertEqual(DSValueFormat.signed(0), "0")
        XCTAssertFalse(DSValueFormat.signed(-1).contains("-"), "a hyphen is not a minus sign")
    }

    func testObjectNumbersHaveThreeDigits() {
        XCTAssertEqual(DSValueFormat.objectNumber(34), "034")
        XCTAssertEqual(DSValueFormat.objectNumber(0), "000")
        XCTAssertEqual(DSValueFormat.objectNumber(1234), "1234")
    }
}
