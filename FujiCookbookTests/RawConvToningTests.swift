import XCTest
@testable import FujiCookbook

/// What the develop path does with Monochromatic Color, and on which simulations.
///
/// The push codec and this profile are the two wire paths that read `nil` differently from a
/// value, and they have to draw the Sepia line in the same place: the camera greys Monochromatic
/// Color for Sepia (X-T50, 2026-09-20), so the push stopped sending it — and until this file
/// existed the develop still wrote a Sepia recipe's warm–cool value into the conversion profile.
/// The profile's field readers are private, so these prove it from the outside: two patches that
/// should differ only by a toning value are byte-identical when the simulation has no toning to
/// set, and are not when it does.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#polarity-and-use`, and
/// `docs/06-conversion-profile.md#monochromatic-color-cells-23-and-26`.
final class RawConvToningTests: XCTestCase {

    private let model = CameraModelRegistry.shared.demoModel

    private func patched(_ settings: RecipeSettings) throws -> Data {
        let base = FujiRawConvProfile.demoGFXBaseProfile()
        let layout = try XCTUnwrap(FujiRawConvProfile.resolveLayout(base))
        return FujiRawConvProfile.patch(base: base, with: settings, model: model, layout: layout)
    }

    func testSepiaDoesNotWriteAToningValueIntoTheProfile() throws {
        let with = try patched(RecipeSettings(filmSimulation: .sepia, monochromaticColorWC: 3, monochromaticColorMG: -2))
        let without = try patched(RecipeSettings(filmSimulation: .sepia))
        XCTAssertEqual(with, without, "a Sepia recipe's toning must not reach the profile")
    }

    /// The cells X RAW Studio writes for the two axes, read by position rather than through
    /// `FujiRawConvProfile.Field`, so a wrong case value can't agree with itself. Captured on an
    /// X-T50 (fw 1.32) converting under ACROS: WC +7 wrote `70` to cell 23 and MG −4 wrote `−40`
    /// to cell 26, and the JPEGs' MakerNotes read back +7 and −4.
    func testWarmCoolGoesToCell23AndMagentaGreenToCell26() throws {
        let profile = try patched(RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 7, monochromaticColorMG: -4))
        func cell(_ index: Int) -> Int32 {
            let off = FujiRawConvProfile.canonicalBase + index * FujiRawConvProfile.fieldSize
            return profile[off..<off + 4].withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) }
        }
        XCTAssertEqual(cell(23), 70)
        XCTAssertEqual(cell(26), -40)
        let layout = try XCTUnwrap(FujiRawConvProfile.resolveLayout(profile))
        let decoded = FujiRawConvProfile.decode(profile, layout: layout)
        XCTAssertEqual(decoded.monochromaticColorWC, 7)
        XCTAssertEqual(decoded.monochromaticColorMG, -4)
    }

    /// The contrast case, so the rule is about Sepia rather than about toning in general.
    func testAcrosStillWritesItsToningIntoTheProfile() throws {
        let with = try patched(RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 3))
        let without = try patched(RecipeSettings(filmSimulation: .acros))
        XCTAssertNotEqual(with, without, "an ACROS warm–cool value is written")
        let layout = try XCTUnwrap(FujiRawConvProfile.resolveLayout(with))
        XCTAssertEqual(FujiRawConvProfile.decode(with, layout: layout).monochromaticColorWC, 3)
    }

    /// Bytes left in the toning field of a Sepia profile are whatever it last held under another
    /// simulation; decoding them would invent a value nobody could have set.
    func testASepiaProfilesLeftoverToningBytesAreNotReadAsARecipeValue() throws {
        // Write toning under ACROS, then switch the same profile to Sepia, which leaves the field alone.
        let acros = try patched(RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 3))
        let layout = try XCTUnwrap(FujiRawConvProfile.resolveLayout(acros))
        let sepia = FujiRawConvProfile.patch(base: acros, with: RecipeSettings(filmSimulation: .sepia),
                                             model: model, layout: layout)
        let decoded = FujiRawConvProfile.decode(sepia, layout: layout)
        XCTAssertEqual(decoded.filmSimulation, .sepia)
        XCTAssertNil(decoded.monochromaticColorWC, "a Sepia profile has no warm–cool value to report")
        XCTAssertNil(decoded.monochromaticColorMG, "nor a magenta–green one")
    }
}
