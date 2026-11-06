import XCTest
@testable import FujiCookbook

@MainActor
final class NumericFormattingSafetyTests: XCTestCase {
    func testToneFormattingKeepsOrdinaryValuesAndHandlesNumbersOutsideIntRange() {
        XCTAssertEqual(RecipeSettingsFormatter.tone(0), "+0")
        XCTAssertEqual(RecipeSettingsFormatter.tone(-0.0), "+0")
        XCTAssertEqual(RecipeSettingsFormatter.tone(2), "+2")
        XCTAssertEqual(RecipeSettingsFormatter.tone(-0.5), "−0.5")
        XCTAssertEqual(RecipeSettingsFormatter.tone(1e20), "+100000000000000000000")
        XCTAssertEqual(RecipeSettingsFormatter.tone(-1e20), "−100000000000000000000")
        for value in [1e100, -1e100, Double.greatestFiniteMagnitude, Double(Int.max)] {
            let text = RecipeSettingsFormatter.tone(value)
            XCTAssertFalse(text.isEmpty)
            XCTAssertNotEqual(text, "Invalid value")
            XCTAssertTrue(text.hasPrefix(value < 0 ? "−" : "+"))
        }
    }

    func testNonfiniteLegacyTonesHaveAnExplicitDisplayValue() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(RecipeSettingsFormatter.tone(value), "Invalid value")
        }
    }

    func testSignedIntegersKeepAllDigitsIncludingThePlatformBounds() {
        XCTAssertEqual(RecipeSettingsFormatter.signed(Int.max), "+9223372036854775807")
        XCTAssertEqual(RecipeSettingsFormatter.signed(Int.min), "−9223372036854775808")
        XCTAssertEqual(RecipeSettingsFormatter.signed(4_294_967_296), "+4294967296")
    }

    func testUnknownLargeNumbersSurviveDisplayAndJSONRoundTrip() throws {
        for literal in ["1e100", "-1e100", "9223372036854775808", "1.7976931348623157e308"] {
            let original = try JSONDecoder().decode(JSONValue.self, from: Data(literal.utf8))
            XCTAssertFalse(original.displayString.isEmpty)
            let encoded = try JSONEncoder().encode(original)
            XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: encoded), original)
        }
        XCTAssertEqual(JSONValue.number(3).displayString, "3")
        XCTAssertEqual(JSONValue.number(-0.5).displayString, "-0.5")
    }

    func testPreviouslyStoredSettingsStillDecodeAndRenderWithoutImportValidation() throws {
        // The persisted settings decoder remains tolerant. Only external imports reject extreme
        // known scalars, so an old library stays readable and its cards must also stay safe.
        let data = Data(#"{"highlightTone":1e100,"shadowTone":-1e100}"#.utf8)
        let settings = try JSONDecoder().decode(RecipeSettings.self, from: data)
        XCTAssertEqual(settings.highlightTone, 1e100)
        XCTAssertEqual(settings.shadowTone, -1e100)
        let rows = RecipeSettingsFormatter.rows(for: settings)
        XCTAssertTrue(rows.contains { $0.field == .highlightTone && $0.value.hasPrefix("+") })
        XCTAssertTrue(rows.contains { $0.field == .shadowTone && $0.value.hasPrefix("−") })
        XCTAssertTrue(RecipeSettingsFormatter.chips(for: settings).contains { $0.hasPrefix("HL +") })
    }
}
