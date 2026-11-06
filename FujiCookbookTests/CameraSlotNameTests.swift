import XCTest
@testable import FujiCookbook

/// The slot-name rule, pinned. 25 characters of printable ASCII, verified on an X-T50.
///
/// Worth pinning tightly because the numbers this replaces were guesses that survived a long time
/// (32 behind a `VERIFY exact max on hardware` comment, 16 on the Demo Camera) and because the
/// output of `generate` is written to `0xD18D`, the bank's name on the camera.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#0xd18d-bank-name`.
final class CameraSlotNameTests: XCTestCase {

    // MARK: Length

    func testANameAtTheLimitIsUntouched() {
        let exact = String(repeating: "A", count: 25)
        XCTAssertEqual(CameraSlotName.sanitize(exact), exact)
    }

    func testANameOverTheLimitIsTruncated() {
        XCTAssertEqual(CameraSlotName.sanitize(String(repeating: "A", count: 26)),
                       String(repeating: "A", count: 25))
    }

    /// A cut that lands right after a space would otherwise send a trailing blank to the camera.
    func testTruncationNeverLeavesATrailingSpace() {
        // Chosen so character 25 is exactly the space: the raw cut is "Kodachrome 64 Warm Tones ".
        let result = CameraSlotName.sanitize("Kodachrome 64 Warm Tones Extra")
        XCTAssertEqual(result, "Kodachrome 64 Warm Tones")
        XCTAssertEqual(result.count, 24)
        XCTAssertFalse(result.hasSuffix(" "))
    }

    /// Filtering has to happen before truncating, or `prefix` spends its budget on characters that
    /// were about to be dropped and a legal 20-character name comes back as 15.
    func testFilteringHappensBeforeTruncating() {
        // 25 disallowed scalars, then a legal name that must survive whole.
        let noisy = String(repeating: "€", count: 25) + "Velvia Punchy"
        XCTAssertEqual(CameraSlotName.sanitize(noisy), "Velvia Punchy")
    }

    // MARK: A disambiguation counter has to survive the cut

    /// The bug: `RecipeImporter` appends " (2)" to disambiguate two same-named recipes, and a plain
    /// truncation then removed it — both recipes reached the camera as "A Very Long Recipe Name T",
    /// which is precisely what the suffix was added to prevent.
    func testADisambiguationCounterSurvivesTruncation() {
        let original = CameraSlotName.sanitize("A Very Long Recipe Name That Overflows")
        let copy = CameraSlotName.sanitize("A Very Long Recipe Name That Overflows (2)")

        XCTAssertEqual(original, "A Very Long Recipe Name T")
        XCTAssertEqual(copy, "A Very Long Recipe Na (2)")
        XCTAssertNotEqual(original, copy, "the whole point: the camera can tell them apart")
        XCTAssertEqual(copy.count, 25)
    }

    func testTheCounterIsKeptWhateverItsWidth() {
        XCTAssertEqual(CameraSlotName.sanitize("A Very Long Recipe Name That Overflows (17)"),
                       "A Very Long Recipe N (17)")
    }

    /// A counter so wide it would leave nothing to read is worse than no counter.
    func testACounterWithNoRoomLeftFallsBackToPlainTruncation() {
        let absurd = "Recipe (\(String(repeating: "9", count: 40)))"
        XCTAssertEqual(CameraSlotName.sanitize(absurd).count, 25)
        XCTAssertTrue(CameraSlotName.sanitize(absurd).hasPrefix("Recipe ("))
    }

    /// Only a real " (12)" counts. A name that merely ends in a parenthesis keeps ordinary
    /// truncation, or "Shot Wide Open Aperture (open)" would get a word rescued at the front's
    /// expense for no reason.
    func testANameEndingInAParenthesisIsNotMistakenForACounter() {
        XCTAssertEqual(CameraSlotName.sanitize("Shot Wide Open Aperture (open)"),
                       "Shot Wide Open Aperture (")
    }

    func testACounterWithoutItsLeadingSpaceIsNotACounter() {
        XCTAssertEqual(CameraSlotName.sanitize("A Very Long Recipe Name Thats(2)"),
                       "A Very Long Recipe Name T")
    }

    // MARK: Character set

    func testEveryCharacterTheCameraAcceptsSurvives() {
        // Printable ASCII, 0x20...0x7E, built independently of the implementation.
        let all = String(String.UnicodeScalarView((0x20...0x7E).map { Unicode.Scalar($0)! }))
        for character in all {
            let probe = "a\(character)b"
            XCTAssertEqual(CameraSlotName.sanitize(probe), probe,
                           "“\(character)” is on the X-T50's list and must survive")
        }
    }

    func testPunctuationTheOldAlphanumericSetRejectedNowSurvives() {
        // The set this replaced was alphanumerics + " -_." only.
        XCTAssertEqual(CameraSlotName.sanitize("Portra #400 @ 50% {v2}"), "Portra #400 @ 50% {v2}")
    }

    func testAnEmDashIsStrippedWithoutLeavingADoubleSpace() {
        // Exactly what `ReadRecipeView.suggestedName` produces for a RAF import. The em dash goes,
        // the space it sat between does not double up, and the result is one character over the cap
        // — so this also pins that the year gets cut rather than a stray space surviving.
        XCTAssertEqual(CameraSlotName.sanitize("Classic Chrome — Jan 3, 2026"),
                       "Classic Chrome Jan 3, 202")
    }

    func testEmojiAreStripped() {
        XCTAssertEqual(CameraSlotName.sanitize("Sunset 🌅 Warm"), "Sunset Warm")
    }

    func testDiacriticsAreFoldedRatherThanDropped() {
        XCTAssertEqual(CameraSlotName.sanitize("Provençal Café"), "Provencal Cafe")
    }

    /// Folding is locale-sensitive — a Turkish locale treats a dotless i differently — so the rule
    /// pins POSIX and a recipe's slot name never depends on the phone's region setting. Asserted as
    /// a property rather than a literal, because exactly which letters Foundation folds is its call,
    /// not ours; what must hold is that the answer is pure ASCII and the same everywhere.
    func testFoldingDoesNotDependOnTheDeviceLocale() {
        let result = CameraSlotName.sanitize("Istanbul Işık")
        XCTAssertTrue(result.unicodeScalars.allSatisfy(CameraSlotName.isAllowed), "got “\(result)”")
        XCTAssertTrue(result.hasPrefix("Istanbul "))
    }

    // MARK: Whitespace

    func testLeadingAndTrailingSpacesAreTrimmed() {
        XCTAssertEqual(CameraSlotName.sanitize("   Velvia   "), "Velvia")
    }

    func testRunsOfSpacesCollapse() {
        XCTAssertEqual(CameraSlotName.sanitize("Kodak    Gold  200"), "Kodak Gold 200")
    }

    // MARK: The fast path must agree with the slow path

    /// `sanitize` returns its input unchanged when the input is already canonical. If that predicate
    /// were laxer than the transform, the same string would sanitize differently depending on which
    /// path ran — so every case in this file has to be a fixed point of a second pass.
    func testSanitizingIsIdempotent() {
        let inputs = ["Velvia", "  Kodak    Gold  200 ", "Provençal Café", "Sunset 🌅 Warm",
                      String(repeating: "A", count: 40), "Classic Chrome — Jan 3, 2026",
                      "Portra #400 @ 50% {v2}", "", "   ", "日本語", "a b",
                      // The counter-aware truncation has its own chance to break the fixed point.
                      "A Very Long Recipe Name That Overflows (2)",
                      "A Very Long Recipe Na (2)", "Shot Wide Open Aperture (open)",
                      "Recipe (\(String(repeating: "9", count: 40)))", "Velvia (2)"]
        for input in inputs {
            let once = CameraSlotName.sanitize(input)
            XCTAssertEqual(CameraSlotName.sanitize(once), once,
                           "sanitizing “\(input)” twice must equal sanitizing it once")
        }
    }

    // MARK: Generation never yields an empty name

    /// An empty `0xD18D` write would leave the bank with no name of its own on the camera, so a
    /// name with nothing salvageable falls back to something a user can tell apart.
    func testANameWithNothingSalvageableFallsBackToTheFilmSimulation() {
        XCTAssertEqual(CameraSlotName.generate(from: "日本語", fallback: "Classic Neg"), "Classic Neg")
    }

    func testANameWithNothingSalvageableAndNoFilmSimulationStillHasAName() {
        XCTAssertEqual(CameraSlotName.generate(from: "日本語"), CameraSlotName.fallbackName)
        XCTAssertEqual(CameraSlotName.generate(from: ""), CameraSlotName.fallbackName)
        XCTAssertEqual(CameraSlotName.generate(from: "   "), CameraSlotName.fallbackName)
    }

    func testGenerationNeverReturnsAnEmptyStringForAnyInput() {
        for input in ["", " ", "🌅", "日本語", "———", "ß", "\u{0}", "\n\t"] {
            XCTAssertFalse(CameraSlotName.generate(from: input).isEmpty,
                           "“\(input)” must still produce a writable slot name")
        }
    }

    // MARK: Live entry

    /// The bug this method exists to avoid: `sanitize` trims, so running it per keystroke deletes
    /// the space in "Kodak " the instant it's typed and a two-word name can never be entered.
    func testTypingASpaceMidNameIsNotEaten() {
        XCTAssertEqual(CameraSlotName.filterForEntry("Kodak "), "Kodak ")
    }

    func testEntryStillEnforcesTheCharacterSetAndLength() {
        XCTAssertEqual(CameraSlotName.filterForEntry("Sun🌅set"), "Sunset")
        XCTAssertEqual(CameraSlotName.filterForEntry(String(repeating: "A", count: 40)).count, 25)
    }

    // MARK: Naming the offender

    func testTheRejectedCharacterIsReportedAsTyped() {
        XCTAssertEqual(CameraSlotName.firstDisallowed(in: "Classic Chrome — Jan"), "—")
        XCTAssertEqual(CameraSlotName.firstDisallowed(in: "Café"), "é")
        XCTAssertNil(CameraSlotName.firstDisallowed(in: "Portra #400 @ 50%"))
    }
}

/// The charset as the *camera models* see it. Separate from `CameraSlotNameTests` because this is
/// what actually reaches `0xD18D`, and it was widened independently of the length change.
final class CameraModelSlotNameTests: XCTestCase {

    private var namingModels: [CameraModel] {
        CameraModelRegistry.shared.models.filter(\.supportsSlotNaming)
    }

    func testEveryNamingBodyUsesTheVerifiedLimit() {
        XCTAssertFalse(namingModels.isEmpty, "precondition")
        for model in namingModels {
            XCTAssertEqual(model.slotNameMaxLength, CameraSlotName.maxLength,
                           "\(model.id) should be on the verified limit, including the demo body")
        }
    }

    /// The punctuation the old alphanumeric set stripped on its way to the camera.
    func testPunctuationTheCameraAcceptsReachesTheWire() {
        for model in namingModels {
            XCTAssertEqual(model.sanitizedSlotName(from: "Portra #400 @ 50%"), "Portra #400 @ 50%",
                           "on \(model.id)")
        }
    }

    /// `CharacterSet.alphanumerics` is the Unicode set, so these used to go out as UTF-16 to a
    /// camera that had never been asked whether it wanted them.
    func testNonASCIILettersNoLongerReachTheWire() {
        for model in namingModels {
            let applied = model.sanitizedSlotName(from: "Ω 日本 é")
            XCTAssertTrue(applied.unicodeScalars.allSatisfy(CameraSlotName.isAllowed),
                          "\(model.id) produced “\(applied)”")
        }
    }

    /// The wire guard folds accents the way the generator does, so a legacy override typed before
    /// the limits existed reaches the camera as "Cafe", not "Caf".
    func testTheWireGuardFoldsAccentsLikeTheGenerator() {
        for model in namingModels {
            XCTAssertEqual(model.sanitizedSlotName(from: "Café Crème"), "Cafe Creme", "on \(model.id)")
        }
    }

    /// A restore sends a name the camera gave back through the wire guard, so the guard leaves the
    /// spacing of an all-ASCII name alone.
    func testTheWireGuardKeepsTheSpacingOfACameraName() {
        for model in namingModels {
            XCTAssertEqual(model.sanitizedSlotName(from: "Kodak  Gold"), "Kodak  Gold", "on \(model.id)")
        }
    }

    /// The name write must never be empty, whatever it was handed.
    func testTheWireGuardNeverProducesAnEmptyName() {
        for model in namingModels {
            for input in ["", "   ", "日本語", "🌅"] {
                XCTAssertFalse(model.sanitizedSlotName(from: input).isEmpty,
                               "\(model.id) on “\(input)”")
            }
        }
    }

    /// A legacy override typed before any limit existed is clamped here, at the wire, rather than
    /// being rewritten in the user's library.
    func testALegacyOverlongNameIsClampedAtTheWire() throws {
        let model = try XCTUnwrap(namingModels.first)
        let applied = model.sanitizedSlotName(from: String(repeating: "A", count: 40))
        XCTAssertEqual(applied.count, CameraSlotName.maxLength)
    }
}
