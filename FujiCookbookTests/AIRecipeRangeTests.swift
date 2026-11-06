import XCTest
@testable import FujiCookbook

/// A screenshot is read by a model that can misread it, and nothing between that model and the
/// library used to check whether the numbers it returned were numbers a Fujifilm camera can hold:
/// the tool schema asked for a bare `integer`/`number` and `toPortable` copied it straight through.
/// A "+2" misread as "+20" therefore reached the review editor, where the slider is bounded by
/// `DefaultRanges` and quietly pins the handle — showing a plausible value instead of the wrong one
/// the recipe actually carried, and saving that wrong one when the user tapped Save.
///
/// These pin both halves of the fence. The schema states the bounds so the model is told them, and
/// `toPortable` enforces them on the way back because no provider validates `minimum`/`maximum` on
/// tool input — the schema is a hint, not a guarantee.
final class AIRecipeRangeTests: XCTestCase {

    private func scanned(_ json: String) throws -> RecipeSettings {
        try JSONDecoder().decode(AIRecipePayload.self, from: Data(json.utf8))
            .toPortable(fallbackName: "Scanned Recipe").settings
    }

    /// The misread-decimal-point case, which is the one that motivated the fence.
    func testAWildlyMisreadNumberIsFencedToTheRange() throws {
        let s = try scanned("""
        {"color": 20, "sharpness": -20, "clarity": 11, "highISONR": -9}
        """)

        XCTAssertEqual(s.color, 4, "color, fenced to the top of its range")
        XCTAssertEqual(s.sharpness, -4, "sharpness, fenced to the bottom")
        XCTAssertEqual(s.clarity, 5, "clarity has the wider ±5 range")
        XCTAssertEqual(s.highISONR, -4, "high ISO NR")
    }

    /// Tones move in half stops, so a model that reads "1.3" off a blurry screenshot has to land on
    /// a value the camera can take rather than one only the app can store.
    func testAToneSnapsToTheHalfStopItMustBe() throws {
        let s = try scanned("""
        {"highlightTone": 1.3, "shadowTone": 9}
        """)

        XCTAssertEqual(s.highlightTone, 1.5, "highlight tone, rounded to the nearest half stop")
        XCTAssertEqual(s.shadowTone, 4, "shadow tone, fenced to the top of its range")
    }

    /// The fence must be invisible on every screenshot that was read correctly — which is nearly
    /// all of them.
    func testInRangeValuesAreLeftExactlyAsRead() throws {
        let s = try scanned("""
        {"filmSimulation": "CLASSIC_NEG", "color": 2, "sharpness": -2, "clarity": 0,
         "highISONR": -4, "highlightTone": 1.5, "shadowTone": -2}
        """)

        XCTAssertEqual(s.filmSimulation, .classicNeg)
        XCTAssertEqual(s.color, 2)
        XCTAssertEqual(s.sharpness, -2)
        XCTAssertEqual(s.clarity, 0)
        XCTAssertEqual(s.highISONR, -4)
        XCTAssertEqual(s.highlightTone, 1.5)
        XCTAssertEqual(s.shadowTone, -2)
    }

    /// White balance carries its bounds in `CameraModelRegistry` rather than `DefaultRanges`, so it
    /// is a separate path through the same fence.
    func testWhiteBalanceShiftAndKelvinAreFencedToo() throws {
        let shifted = try scanned("""
        {"whiteBalanceMode": "DAYLIGHT", "whiteBalanceShiftRed": 30, "whiteBalanceShiftBlue": -30}
        """)
        XCTAssertEqual(shifted.whiteBalance?.shiftRed, 9, "R shift, fenced to ±9")
        XCTAssertEqual(shifted.whiteBalance?.shiftBlue, -9, "B shift")

        let cold = try scanned("""
        {"whiteBalanceMode": "KELVIN", "whiteBalanceKelvin": 1000}
        """)
        XCTAssertEqual(cold.whiteBalance?.kelvin, 2500, "Kelvin, fenced to the bottom of the dial")
    }

    /// The bounds the model is told and the bounds we enforce come from one source; this fails if
    /// they ever stop doing so.
    func testTheSchemaPublishesTheSameBoundsItEnforces() {
        let properties = AIRecipeSchema.recipeProperties()

        func bounds(_ key: String) -> (min: Double, max: Double)? {
            guard let property = properties[key] as? [String: Any],
                  let low = property["minimum"] as? NSNumber,
                  let high = property["maximum"] as? NSNumber else { return nil }
            return (low.doubleValue, high.doubleValue)
        }

        for (key, field) in [("color", RecipeField.color), ("sharpness", .sharpness),
                             ("clarity", .clarity), ("highISONR", .highISONR),
                             ("highlightTone", .highlightTone), ("shadowTone", .shadowTone)] {
            let expected = DefaultRanges.range(for: field)
            let stated = bounds(key)
            XCTAssertEqual(stated?.min, expected.min, "\(key) minimum")
            XCTAssertEqual(stated?.max, expected.max, "\(key) maximum")
        }

        XCTAssertEqual(bounds("whiteBalanceShiftRed")?.max,
                       CameraModelRegistry.whiteBalanceShiftRange.max, "WB shift maximum")
        XCTAssertEqual(bounds("whiteBalanceKelvin")?.min,
                       CameraModelRegistry.kelvinRange.min, "Kelvin minimum")
    }

    /// A tone is the only kind of field that may arrive fractional, and the schema says so — the
    /// integer fields must not carry a `multipleOf` that contradicts their `"type": "integer"`.
    func testOnlyFractionalFieldsAreTypedAsNumbers() {
        let properties = AIRecipeSchema.recipeProperties()

        func type(_ key: String) -> String? {
            (properties[key] as? [String: Any])?["type"] as? String
        }

        XCTAssertEqual(type("highlightTone"), "number", "tones move in half stops")
        XCTAssertEqual(type("shadowTone"), "number")
        XCTAssertEqual(type("color"), "integer")
        XCTAssertEqual(type("clarity"), "integer")
        XCTAssertEqual(type("whiteBalanceKelvin"), "integer", "Kelvin steps by 10, but is whole")
        XCTAssertNil((properties["color"] as? [String: Any])?["multipleOf"],
                     "an integer field's step is already implied by its type")
    }
}
