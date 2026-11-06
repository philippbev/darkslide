import XCTest
@testable import FujiCookbook

/// A share card is a seventh read-only rendering of a recipe, and it used to format its own values.
/// These pin it to `RecipeSettingsFormatter` — the primitive the detail screen, the share
/// extension's card, the Kitchen read and the Camera Test all draw rows from — so the card cannot
/// drift away from what the rest of the app says about the same recipe.
///
/// The one deliberate difference is how the card says a field is overridden. The formatter appends
/// a sentence, which a ledger column two inches wide cannot hold and a poster has no app around it
/// to explain, so the card drops the fields the priority drives and prints the priority instead.
@MainActor
final class ShareCardContentPriorityTests: XCTestCase {

    private func settings(priority: DRangePriority?) -> RecipeSettings {
        RecipeSettings(
            filmSimulation: .classicNeg,
            grain: GrainEffect(strength: .strong, size: .large),
            colorChromeEffect: .strong,
            colorChromeFXBlue: .strong,
            whiteBalance: WhiteBalance(mode: .auto, shiftRed: 4, shiftBlue: -5, kelvin: nil),
            dynamicRange: .dr400,
            dRangePriority: priority,
            highlightTone: -2, shadowTone: 1, color: 4, sharpness: 0, highISONR: -4, clarity: -4)
    }

    private func content(priority: DRangePriority?) -> ShareCardContent {
        ShareCardContent(recipe: Recipe(name: "Coral Neg", credit: "lumenfoto",
                                        settings: settings(priority: priority)))
    }

    private func labels(_ c: ShareCardContent) -> [String] { c.lines.map(\.label) }
    private func value(_ c: ShareCardContent, _ label: String) -> String? {
        c.lines.first { $0.label == label }?.value
    }

    // MARK: The values are the app's

    func testValuesComeFromTheSharedFormatter() {
        let c = content(priority: nil)
        let s = settings(priority: nil)
        for line in c.lines {
            // Every printed value is one the formatter produced for some field of this recipe.
            let fromFormatter = RecipeField.allCases.compactMap {
                RecipeSettingsFormatter.valueString(for: $0, in: s)
            }
            XCTAssertTrue(fromFormatter.contains(line.value),
                          "\(line.label) prints \"\(line.value)\", which the formatter never produced")
        }
        // Spot-check the three the card used to format for itself, and differently.
        XCTAssertEqual(value(c, "Grain"), "Strong, Large")
        XCTAssertEqual(value(c, "WB"), "Auto · R+4 B−5")
        XCTAssertEqual(value(c, "Sharpness"), "+0", "the app signs a zero; the card no longer differs")
    }

    func testTheCardKeepsItsOwnShortLabels() {
        let c = content(priority: nil)
        // "White Balance" is the app's name for it and is right on a detail row; a card column is
        // not that wide.
        XCTAssertTrue(labels(c).contains("WB"))
        XCTAssertFalse(labels(c).contains("White Balance"))
        XCTAssertTrue(labels(c).contains("Noise Reduction"))
    }

    // MARK: Without the priority, nothing changes

    func testWithoutThePriorityTheOverriddenFieldsArePrinted() {
        for priority in [DRangePriority?.none, .some(.off)] {
            let c = content(priority: priority)
            XCTAssertEqual(c.lines.count, 11, "\(String(describing: priority))")
            XCTAssertEqual(value(c, "Dynamic Range"), "DR400")
            XCTAssertEqual(value(c, "Highlight"), "−2")
            XCTAssertEqual(value(c, "Shadow"), "+1")
            XCTAssertFalse(labels(c).contains("D-Range Priority"),
                           "a priority that is off is not a setting worth a row")
        }
    }

    // MARK: With it, the priority stands in their place

    func testThePriorityReplacesTheFieldsItDrives() {
        let c = content(priority: .strong)

        XCTAssertEqual(value(c, "D-Range Priority"), "Strong")
        for gone in ["Dynamic Range", "Highlight", "Shadow"] {
            XCTAssertFalse(labels(c).contains(gone),
                           "\(gone) is driven by the camera, so the card does not offer it as a choice")
        }
        XCTAssertEqual(c.lines.count, 9, "three fields out, one priority in")
    }

    func testThePriorityTakesTheFirstSlotOfTheRunItReplaces() {
        let off = labels(content(priority: nil))
        let on = labels(content(priority: .strong))
        // It stands exactly where Dynamic Range stood, so the block keeps its reading order.
        XCTAssertEqual(on.firstIndex(of: "D-Range Priority"), off.firstIndex(of: "Dynamic Range"))
        XCTAssertEqual(on.filter { $0 == "D-Range Priority" }.count, 1, "one row, not three")
        // Everything either side is untouched and still in order.
        XCTAssertEqual(Array(on.prefix(4)), Array(off.prefix(4)))
        XCTAssertEqual(Array(on.suffix(4)), Array(off.suffix(4)))
    }

    func testTheDroppedSetIsTheFormattersOwn() {
        let off = Set(labels(content(priority: nil)))
        let on = Set(labels(content(priority: .strong)))
        let dropped = off.subtracting(on)
        // Pinned to the formatter rather than to a list here, so a fourth field brought under the
        // priority one day cannot leave the card printing it as a choice.
        XCTAssertEqual(dropped.count, RecipeApplicability.fieldsUnderPriority.count)
    }

    func testEveryPriorityThatIsOnCountsAsOn() {
        for priority: DRangePriority in [.auto, .weak, .strong] {
            let c = content(priority: priority)
            XCTAssertEqual(value(c, "D-Range Priority"), priority.displayName)
            XCTAssertFalse(labels(c).contains("Dynamic Range"), "\(priority)")
        }
    }

    // MARK: The card never prints the formatter's sentence

    func testTheLongNoteNeverReachesACard() {
        for priority: DRangePriority? in [nil, .off, .auto, .weak, .strong] {
            let c = content(priority: priority)
            for line in c.lines + c.linesWithFilmSimulation {
                XCTAssertFalse(line.value.contains(RecipeSettingsFormatter.priorityNote),
                               "\"\(line.value)\" would overflow a ledger column")
            }
        }
    }

    /// "D-Range Priority" is the longest label a card has ever printed, and the ledger presets pick
    /// their column count by measuring the widest label-and-value pair in the block. Every style
    /// still resolves at the shape it was drawn for, at no fewer columns than the design used.
    func testEveryStyleStillFitsOnceThePriorityRowAppears() throws {
        let c = content(priority: .strong)
        let shapes: [(ShareCardStyle, CGSize)] = [
            (.plain, CGSize(width: 1080, height: 1350)),
            (.story, CGSize(width: 1080, height: 1920)),
            (.feed, CGSize(width: 1080, height: 1350)),
            (.specimen, CGSize(width: 1080, height: 1080)),
            (.quarterGrid, CGSize(width: 1080, height: 1350))
        ]
        for (style, size) in shapes {
            let m = try XCTUnwrap(style.metrics(canvas: size, content: c), style.title)
            XCTAssertGreaterThanOrEqual(m.ledgerColumns, style.designColumns, style.title)
        }
    }

    /// A recipe that arrived under the older name — "Noise Reduction", what a body up to the X-T3
    /// calls High ISO NR — still gets its one noise row, through the fold in `RecipeSettings`.
    func testTheNoiseRowShowsAValueThatArrivedUnderTheOlderName() {
        let s = RecipeSettings(filmSimulation: .acros, noiseReduction: -3)
        let c = ShareCardContent(recipe: Recipe(name: "Mono", settings: s))
        XCTAssertEqual(c.lines.first { $0.label == "Noise Reduction" }?.value, "−3")
    }
}
