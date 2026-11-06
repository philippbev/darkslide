import XCTest
@testable import FujiCookbook

/// `0xD191` is D-Range Priority, and Dynamic Range is the field it locks out. The values (Off
/// `0x0000`, Weak `0x0001`, Strong `0x0002`, Auto `0x8000`) and the interlock are in
/// zgrimz/fujifilm-ptp-reference `docs/03-encodings.md#0xd191-d-range-priority` and
/// `docs/04-custom-slots.md#the-d-range-priority-interlock` [Measured: X-T50 fw 1.32].
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference: `docs/04-custom-slots.md#iso-gating`.
final class DRangePriorityTests: XCTestCase {

    private let registry = CameraModelRegistry.shared
    private var model: CameraModel { registry.demoModel }

    private func codes(_ s: RecipeSettings, slot: FujiPresetCodec.Slot) -> [UInt16] {
        FujiPresetCodec.encode(s, model: model, slot: slot).map(\.code)
    }
    private func bytes(_ s: RecipeSettings, slot: FujiPresetCodec.Slot, for p: FujiPTP.PresetProp) -> Data? {
        FujiPresetCodec.encode(s, model: model, slot: slot).first { $0.code == p.rawValue }?.bytes
    }
    /// A slot holding a recipe, plus whatever D-Range Priority the test needs it to have.
    private func slotHolding(_ drp: DRangePriority, dynamicRange: Int = 100) -> FujiPresetCodec.Slot {
        .holds([FujiPTP.PresetProp.filmSimulation.rawValue: FujiEncoding.packU16(1),
                FujiPTP.PresetProp.dynamicRange.rawValue: FujiEncoding.packU16(dynamicRange),
                FujiPTP.PresetProp.dRangePriority.rawValue:
                    FujiEncoding.packU16(FujiEncoding.dRangePriorityToValue[drp]!)])
    }

    // MARK: The encoding

    /// Auto is the high-bit sentinel, not an in-sequence 3 — so `packI16` would clamp it to
    /// `0x7FFF` and send something between Strong and nothing at all. This is the assertion that
    /// catches that, and it is the only value in the set where the choice of packer is visible.
    func testEveryValueRoundTripsIncludingTheAutoSentinel() throws {
        for drp in DRangePriority.allCases {
            let wire = try XCTUnwrap(FujiEncoding.dRangePriorityToValue[drp])
            let packed = FujiEncoding.packU16(wire)
            XCTAssertEqual(packed.count, 2, "\(drp.displayName)")
            let read = try XCTUnwrap(FujiEncoding.decodeUInt16(packed))
            XCTAssertEqual(FujiEncoding.valueToDRangePriority[Int(read)], drp, "\(drp.displayName)")
        }
        XCTAssertEqual(FujiEncoding.dRangePriorityToValue[.auto], 0x8000)
        XCTAssertEqual(FujiEncoding.packU16(0x8000), Data([0x00, 0x80]))
        XCTAssertNotEqual(FujiEncoding.packI16(0x8000), Data([0x00, 0x80]),
                          "packI16 clamps the sentinel — the reason this property is packed unsigned")
    }

    /// Off/Weak/Strong = 0/1/2 matches the mapping this app reads out of EXIF `0x1445`, a different
    /// namespace (zgrimz/fujifilm-ptp-reference
    /// `docs/10-jpeg-recipes.md#exif-is-a-separate-encoding-namespace`): weak support, not a second
    /// measurement.
    func testTheWireValuesAgreeWithTheEXIFDecoder() {
        for (tag, strength) in FujiMakerNote.dRangePriorityFixedStrengths {
            XCTAssertEqual(FujiEncoding.dRangePriorityToValue[strength], tag,
                           "EXIF 0x1445 reads \(strength.displayName) as \(tag)")
        }
    }

    /// A value the table doesn't know is a finding, not an Off. `flatToGrain` learned this the hard
    /// way — a confidently wrong decode hid the read-side 6/7 for months.
    func testAnUnknownValueIsRecordedRatherThanDecodedToOff() {
        let props: FujiPresetCodec.Props = [
            FujiPTP.PresetProp.filmSimulation.rawValue: FujiEncoding.packU16(1),
            FujiPTP.PresetProp.dRangePriority.rawValue: FujiEncoding.packU16(0x4242),
        ]
        let decoded = FujiPresetCodec.decode(props, name: nil, model: model)
        XCTAssertNil(decoded.settings.dRangePriority)
        XCTAssertTrue(decoded.divergences.contains { $0.code == FujiPTP.PresetProp.dRangePriority.rawValue },
                      "an unrecognised priority is a divergence the report carries")
    }

    // MARK: The interlock

    /// The camera drives Dynamic Range while D-Range Priority is on and refuses every write to
    /// D190, so a recipe holding both gets the priority and not the range.
    func testAPriorityThatIsOnSuppressesTheDynamicRangeWrite() {
        let out = codes(RecipeSettings(dynamicRange: .dr400, dRangePriority: .strong),
                        slot: slotHolding(.off))
        XCTAssertTrue(out.contains(FujiPTP.PresetProp.dRangePriority.rawValue))
        XCTAssertFalse(out.contains(FujiPTP.PresetProp.dynamicRange.rawValue),
                       "D190 would be refused, and the recipe's own priority is what says so")
    }

    /// The boundary, measured rather than assumed: under D-Range Priority the camera refuses
    /// Highlight Tone and Shadow Tone with the range and takes every other field
    /// (`docs/04-custom-slots.md#the-d-range-priority-interlock`).
    func testAnActivePriorityTakesTheToneCurvesWithTheDynamicRange() {
        // Every field set, as the hardware run had it — otherwise the unset ones reach
        // `emitDefault` and the minimal slot fixture, which reports none of them, skips them for an
        // entirely different reason.
        var settings = RecipeSettings(filmSimulation: .classicChrome, dRangePriority: .strong)
        settings.grain = GrainEffect(strength: .strong, size: .large)
        settings.colorChromeEffect = .strong
        settings.colorChromeFXBlue = .strong
        settings.whiteBalance = WhiteBalance(mode: .daylight, shiftRed: 3, shiftBlue: -5, kelvin: nil)
        settings.dynamicRange = .dr400
        settings.highlightTone = -1
        settings.shadowTone = 1
        settings.color = 2
        settings.sharpness = -1
        settings.highISONR = -2
        settings.clarity = 2
        let out = codes(settings, slot: slotHolding(.off))

        for skipped in [FujiPTP.PresetProp.dynamicRange, .highlightTone, .shadowTone] {
            XCTAssertFalse(out.contains(skipped.rawValue),
                           "\(skipped.debugName) is the camera's while the priority is on")
        }
        for written in [FujiPTP.PresetProp.color, .sharpness, .clarity, .grain,
                        .colorChrome, .colorChromeFXBlue, .whiteBalance, .highISONR] {
            XCTAssertTrue(out.contains(written.rawValue),
                          "\(written.debugName) is untouched by the priority and still goes")
        }
    }

    /// And the advisory names each one it skipped, rather than leaving the reader to infer two of
    /// them from a sentence about the third.
    func testTheAdvisoryNamesEveryFieldThePriorityTakes() {
        var settings = RecipeSettings(filmSimulation: .classicChrome, dRangePriority: .strong)
        settings.dynamicRange = .dr400
        settings.highlightTone = -1
        settings.shadowTone = 1
        let issues = RecipeCompatibility.analyze(settings, for: model)

        for field in [RecipeField.dynamicRange, .highlightTone, .shadowTone] {
            XCTAssertTrue(issues.contains { $0.field == field && $0.kind == .notWritten },
                          "\(field.displayName) is named")
        }
        XCTAssertFalse(issues.contains { $0.field == .sharpness },
                       "and a field the priority doesn't touch is not")
    }

    /// The converse, and the case the editor cannot cover because the recipe never mentions a
    /// priority: setting a dynamic range asserts DR mode, so the push clears the priority to make
    /// it take. Both writes go, and the priority goes first.
    func testADynamicRangeTurnsOffAPriorityTheSlotIsHolding() throws {
        let out = FujiPresetCodec.encode(RecipeSettings(dynamicRange: .dr400),
                                         model: model, slot: slotHolding(.strong))
        let codes = out.map(\.code)

        let drpIndex = try XCTUnwrap(codes.firstIndex(of: FujiPTP.PresetProp.dRangePriority.rawValue))
        let drIndex = try XCTUnwrap(codes.firstIndex(of: FujiPTP.PresetProp.dynamicRange.rawValue))
        XCTAssertLessThan(drpIndex, drIndex,
                          "D191 before D190, or the dynamic range is refused by the state being cleared")

        XCTAssertEqual(out[drpIndex].bytes, FujiEncoding.packU16(0), "turned off")
        XCTAssertEqual(out[drIndex].bytes, FujiEncoding.packU16(400))
    }

    /// The no-op suppression that keeps a clean push clean. D191 is ISO-gated like D190, so at base
    /// ISO the camera refuses even a write of the value already there — which is what the old
    /// passthrough did on every push. Harmless while it was housekeeping; once it is a recipe field
    /// that refusal would demote the whole push to `partiallyApplied`.
    func testNothingIsWrittenWhenTheSlotAlreadyHoldsWhatTheRecipeWants() {
        XCTAssertFalse(codes(RecipeSettings(dynamicRange: .dr400), slot: slotHolding(.off))
            .contains(FujiPTP.PresetProp.dRangePriority.rawValue),
            "already Off — a write changes nothing, and at base ISO is refused")

        XCTAssertFalse(codes(RecipeSettings(dRangePriority: .strong), slot: slotHolding(.strong))
            .contains(FujiPTP.PresetProp.dRangePriority.rawValue),
            "already Strong, and the recipe agrees")

    }

    /// A recipe that says nothing about either still clears the priority, because saying nothing is
    /// a look too: a recipe is a description, and one that inherited the destination bank's priority
    /// rendered differently on every bank it touched. Off is the default, so Off is what a bank
    /// holding Strong is moved to — and the dynamic range then follows, at its own default of Auto.
    func testARecipeWithNoOpinionStillResolvesToTheDefaults() throws {
        let out = FujiPresetCodec.encode(RecipeSettings(filmSimulation: .provia),
                                         model: model, slot: slotHolding(.strong))
        let codes = out.map(\.code)

        let drpIndex = try XCTUnwrap(codes.firstIndex(of: FujiPTP.PresetProp.dRangePriority.rawValue))
        XCTAssertEqual(out[drpIndex].bytes, FujiEncoding.packU16(0), "turned off, not inherited")
        XCTAssertEqual(out.first { $0.code == FujiPTP.PresetProp.dynamicRange.rawValue }?.bytes,
                       FujiEncoding.packI16(FujiEncoding.drAutoSlotValue),
                       "and the range the priority was masking resolves to Auto")
    }

    /// The exception, and the one place "leave it alone" survives: a bank that never reported the
    /// property. An unanswered read is not a licence to overwrite what we could not see.
    func testASilentSlotIsNotGivenADefault() {
        let silent: FujiPresetCodec.Slot = .holds(
            [FujiPTP.PresetProp.filmSimulation.rawValue: FujiEncoding.packU16(1)])
        let out = codes(RecipeSettings(filmSimulation: .provia), slot: silent)

        XCTAssertFalse(out.contains(FujiPTP.PresetProp.dRangePriority.rawValue))
        XCTAssertFalse(out.contains(FujiPTP.PresetProp.dynamicRange.rawValue))
    }

    /// …and it is never silent. Every other way a recipe field fails to reach the camera puts a row
    /// on the results screen; a default that was never sent leaves none, so the push would report
    /// "Written and verified" over a look the bank does not hold. This is the query that stops that,
    /// pinned against `encode`'s own output so the two cannot drift apart.
    func testWhatTheCodecSkipsIsExactlyWhatThePushReports() {
        let silent: FujiPresetCodec.Slot = .holds(
            [FujiPTP.PresetProp.filmSimulation.rawValue: FujiEncoding.packU16(1)])
        let settings = RecipeSettings(filmSimulation: .provia)

        let reported = FujiPresetCodec.defaultsNotWrittenForSilentRead(settings, model: model, slot: silent)
        XCTAssertFalse(reported.isEmpty, "the fixture reports only D192, so the rest are skipped")

        let written = Set(codes(settings, slot: silent))
        for prop in reported {
            XCTAssertFalse(written.contains(prop.rawValue),
                           "\(prop.debugName) is reported as unsent, so it must not be sent")
        }
        // The other direction: a default the codec *did* write must not be reported as skipped.
        for prop in FujiPresetCodec.defaultedFields where written.contains(prop.rawValue) {
            XCTAssertFalse(reported.contains(prop),
                           "\(prop.debugName) was written, so reporting it would be crying wolf")
        }
    }

    /// A bank that answers for everything gets its defaults, and nothing is reported as unsent.
    func testAnAnsweringSlotReportsNothingUnsent() {
        let full: FujiPresetCodec.Slot = .holds([
            FujiPTP.PresetProp.filmSimulation.rawValue: FujiEncoding.packU16(1),
            FujiPTP.PresetProp.dynamicRange.rawValue: FujiEncoding.packU16(100),
            FujiPTP.PresetProp.dRangePriority.rawValue: FujiEncoding.packU16(0),
            FujiPTP.PresetProp.grain.rawValue: FujiEncoding.packU16(1),
            FujiPTP.PresetProp.colorChrome.rawValue: FujiEncoding.packU16(1),
            FujiPTP.PresetProp.colorChromeFXBlue.rawValue: FujiEncoding.packU16(1),
        ])
        XCTAssertEqual(FujiPresetCodec.defaultsNotWrittenForSilentRead(RecipeSettings(), model: model, slot: full),
                       [])
        XCTAssertEqual(FujiPresetCodec.defaultsNotWrittenForSilentRead(RecipeSettings(), model: model, slot: .empty),
                       [], "an empty slot is seeded, not skipped")
    }

    // MARK: What a refused priority does to the three fields it withheld

    /// The withheld set is exactly the three the priority drives, and its bytes are the ones the
    /// same recipe would have written with the priority off. Two code paths compute those values;
    /// this is what keeps them from drifting apart.
    func testTheWithheldSetMatchesWhatAPriorityOffRecipeWouldHaveWritten() throws {
        var settings = RecipeSettings(filmSimulation: .classicChrome, dRangePriority: .strong)
        settings.dynamicRange = .dr400
        settings.highlightTone = -1.5
        settings.shadowTone = 1
        let slot = slotHolding(.off)

        let withheld = FujiPresetCodec.dRangePriorityWithheld(settings, model: model, slot: slot)
        XCTAssertEqual(Set(withheld.map(\.code)),
                       Set([FujiPTP.PresetProp.dynamicRange, .highlightTone, .shadowTone]
                            .map(\.rawValue)),
                       "the withheld set is the three the priority drives, no more and no less")

        var off = settings
        off.dRangePriority = .off
        for (code, bytes) in withheld {
            let prop = try XCTUnwrap(FujiPTP.PresetProp(rawValue: code))
            XCTAssertEqual(bytes, self.bytes(off, slot: slot, for: prop),
                           "\(prop.debugName) is held back at the value it would have been written")
        }
    }

    /// Nothing is held back when there is no priority to hold it back — the guard that stops a
    /// refused `D191` on some *other* recipe from writing a second copy of these three.
    func testNothingIsWithheldWhenTheRecipeHasNoPriority() {
        var settings = RecipeSettings(filmSimulation: .provia, dRangePriority: .off)
        settings.dynamicRange = .dr400
        XCTAssertTrue(FujiPresetCodec.dRangePriorityWithheld(settings, model: model,
                                                             slot: slotHolding(.off)).isEmpty)
        settings.dRangePriority = nil
        XCTAssertTrue(FujiPresetCodec.dRangePriorityWithheld(settings, model: model,
                                                             slot: slotHolding(.off)).isEmpty)
    }

    /// A slot that never answered for `D190` is still not written a dynamic range it never
    /// reported — the withheld path inherits `emitDefault`'s rule rather than reimplementing it.
    func testASilentSlotIsNotGivenADynamicRangeByTheWithheldPathEither() {
        let silent: FujiPresetCodec.Slot = .holds([
            FujiPTP.PresetProp.filmSimulation.rawValue: FujiEncoding.packU16(1),
            FujiPTP.PresetProp.dRangePriority.rawValue: FujiEncoding.packU16(0),
        ])
        let codes = FujiPresetCodec.dRangePriorityWithheld(
            RecipeSettings(filmSimulation: .provia, dRangePriority: .strong),
            model: model, slot: silent).map(\.code)
        XCTAssertFalse(codes.contains(FujiPTP.PresetProp.dynamicRange.rawValue),
                       "the bank never reported D190, so nothing invents one for it")
        XCTAssertTrue(codes.contains(FujiPTP.PresetProp.highlightTone.rawValue),
                      "the tones are written outright, so they are still held back")
    }

    /// A body with no D-Range Priority control has nowhere to put the recipe's, so nothing is
    /// driving Dynamic Range or the tones and all three are written normally. Keyed off the
    /// recipe's priority alone, a recipe carrying one lost all three on every such body — silently,
    /// because `RecipeCompatibility` gates its advisory on the same support check.
    func testABodyWithoutThePriorityStillWritesTheDynamicRangeAndTones() throws {
        let gfx50S = try XCTUnwrap(registry.model(withID: "GFX50S"))
        XCTAssertFalse(gfx50S.supports(.dRangePriority), "the premise of this test")

        var settings = RecipeSettings(filmSimulation: .provia, dRangePriority: .strong)
        settings.dynamicRange = .dr400
        settings.highlightTone = -1
        settings.shadowTone = 1
        let written = Set(FujiPresetCodec.encode(settings, model: gfx50S,
                                                 slot: slotHolding(.off)).map(\.code))

        for prop in [FujiPTP.PresetProp.dynamicRange, .highlightTone, .shadowTone] {
            XCTAssertTrue(written.contains(prop.rawValue),
                          "\(prop.debugName) has nothing to be overridden by on this body")
        }
        XCTAssertFalse(written.contains(FujiPTP.PresetProp.dRangePriority.rawValue),
                       "and the priority itself is not sent to a body that hasn't got it")
        XCTAssertTrue(FujiPresetCodec.dRangePriorityWithheld(settings, model: gfx50S,
                                                             slot: slotHolding(.off)).isEmpty,
                      "so there is nothing withheld to write back later either")
    }
}
