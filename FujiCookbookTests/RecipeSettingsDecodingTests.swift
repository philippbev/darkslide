import XCTest
@testable import FujiCookbook

/// Decoding tolerates two things and nothing else: a nested grain or white balance with no
/// discriminator reads as unset rather than as a default, and an enum raw value this version doesn't
/// model reads as unset rather than failing the whole recipe.
final class RecipeSettingsDecodingTests: XCTestCase {
    /// Every field set, so a test that spoils one field can check that the rest survive.
    private static let fullSettings = RecipeSettings(
        filmSimulation: .classicChrome, monochromaticColorWC: 1, monochromaticColorMG: -1,
        grain: GrainEffect(strength: .weak, size: .large), colorChromeEffect: .strong, colorChromeFXBlue: .weak,
        whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: 2, shiftBlue: -3, kelvin: 5500),
        dynamicRange: .dr200, dRangePriority: .weak, highlightTone: -1.5, shadowTone: 0.5, color: 2,
        sharpness: -1, highISONR: -2, clarity: 3, exposureBias: 0.5, noiseReduction: 1)

    private func decode(_ json: String) throws -> RecipeSettings {
        try JSONDecoder().decode(RecipeSettings.self, from: Data(json.utf8))
    }

    /// `fullSettings` encoded, then changed by `edit` before decoding, the way a newer build's
    /// payload differs from what this one writes.
    private func decodeFullSettings(editing edit: (inout [String: Any]) -> Void) throws -> RecipeSettings {
        let encoded = try JSONEncoder().encode(Self.fullSettings)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        edit(&payload)
        return try JSONDecoder().decode(RecipeSettings.self,
                                        from: JSONSerialization.data(withJSONObject: payload))
    }

    func testEveryKnownValueRoundTrips() throws {
        XCTAssertEqual(try decodeFullSettings { _ in }, Self.fullSettings)
    }

    func testAnEmptyGrainOrWhiteBalanceObjectDecodesAsUnset() throws {
        let settings = try decode(#"{"grain": {}, "whiteBalance": {}}"#)
        XCTAssertNil(settings.grain)
        XCTAssertNil(settings.whiteBalance)
    }

    func testAPartialGrainOrWhiteBalanceObjectFillsItsDefaults() throws {
        let settings = try decode(#"{"grain": {"strength": "WEAK"}, "whiteBalance": {"mode": "AUTO"}}"#)
        XCTAssertEqual(settings.grain, GrainEffect(strength: .weak, size: nil))
        XCTAssertEqual(settings.whiteBalance, WhiteBalance(mode: .auto, shiftRed: 0, shiftBlue: 0, kelvin: nil))
    }

    /// `CUSTOM_1`…`CUSTOM_3` were modes once; a camera's measured white balance isn't a recipe
    /// parameter, so a file or store that still carries one reads as no white balance.
    func testARetiredOrUnknownWhiteBalanceModeDecodesAsUnset() throws {
        let settings = try decode(#"{"whiteBalance": {"mode": "CUSTOM_1", "shiftRed": 2, "shiftBlue": -1}}"#)
        XCTAssertNil(settings.whiteBalance)
    }

    func testAnUnknownFilmSimulationDecodesAsUnsetAndKeepsTheRest() throws {
        let settings = try decodeFullSettings { $0["filmSimulation"] = "FUTURE_SIMULATION" }
        var expected = Self.fullSettings
        expected.filmSimulation = nil
        XCTAssertEqual(settings, expected)
    }

    func testAnUnknownDynamicRangeDecodesAsUnsetAndKeepsTheRest() throws {
        let settings = try decodeFullSettings { $0["dynamicRange"] = "DR800" }
        var expected = Self.fullSettings
        expected.dynamicRange = nil
        XCTAssertEqual(settings, expected)
    }

    /// `strength` is what says a grain was stored at all, so an unknown one leaves no grain setting,
    /// whatever the size.
    func testAnUnknownGrainStrengthDecodesAsNoGrainAndKeepsTheRest() throws {
        let settings = try decodeFullSettings { $0["grain"] = ["strength": "EXTRA_STRONG", "size": "LARGE"] }
        var expected = Self.fullSettings
        expected.grain = nil
        XCTAssertEqual(settings, expected)
    }

    /// An unknown size reads as an absent one: the grain keeps its strength.
    func testAnUnknownGrainSizeKeepsTheStrength() throws {
        let settings = try decodeFullSettings { $0["grain"] = ["strength": "STRONG", "size": "MEDIUM"] }
        XCTAssertEqual(settings.grain, GrainEffect(strength: .strong, size: nil))
    }

    /// The diagnostic names the field so a report can say what was dropped, and never carries the
    /// stored value, which is the user's.
    func testADroppedValueIsLoggedByFieldNameOnly() throws {
        AppLog.clear(.data)
        _ = try decodeFullSettings { $0["colorChromeFXBlue"] = "SECRET_STRENGTH" }
        let messages = AppLog.entries(in: .data).map(\.message)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages.allSatisfy { $0.contains("colorChromeFXBlue") }, "\(messages)")
        XCTAssertFalse(messages.contains { $0.contains("SECRET_STRENGTH") }, "\(messages)")
    }
}
