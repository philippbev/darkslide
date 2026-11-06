import XCTest
@testable import FujiCookbook

/// Round-trip tests for the preset codec, and for the codec as the mock camera actually exercises
/// it — encode → write over the transport → read back → decode. The second path is the one that
/// matters most: it is the same code a push runs, so a regression in it is a regression in what
/// people's cameras receive.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#polarity-and-use`, `docs/03-encodings.md#0xd190-dynamic-range`,
/// `docs/03-encodings.md#0xd192-film-simulation`, `docs/03-encodings.md#0xd195-grain-effect`,
/// `docs/03-encodings.md#0xd199-white-balance-mode`, and
/// `docs/03-encodings.md#0xd1a5-x-raw-studios-live-image-size`.
final class FujiPresetCodecTests: XCTestCase {

    private let model = CameraModelRegistry.shared.demoModel

    /// The full property set for a recipe, as it would be written into a slot that has no entry:
    /// `.empty` is the one case that takes the codec's seed values for the housekeeping properties,
    /// so this is a complete slot the decoder can be pointed at.
    private func props(for settings: RecipeSettings) -> FujiPresetCodec.Props {
        var out: FujiPresetCodec.Props = [:]
        for (code, bytes) in FujiPresetCodec.encode(settings, model: model, slot: .empty) { out[code] = bytes }
        return out
    }

    // MARK: Sepia's toning is the camera's, not the recipe's

    /// The camera greys Monochromatic Color out for Sepia (X-T50, 2026-09-20), so writing it is
    /// writing a property the body will not honour — and `FujiPresetCodec.encodeRestore` already
    /// documents that the camera answers `0x201C` to exactly this write on a simulation that doesn't
    /// take it, which scores an otherwise complete restore as `partiallyApplied`.
    func testSepiaDoesNotWriteAToningValueTheCameraWillRefuse() {
        let sepia = RecipeSettings(filmSimulation: .sepia, monochromaticColorWC: 3, monochromaticColorMG: -2)
        let codes = Set(FujiPresetCodec.encode(sepia, model: model, slot: .empty).map(\.0))
        XCTAssertFalse(codes.contains(FujiPTP.PresetProp.monochromaticWC.rawValue),
                       "Sepia must not write the warm–cool axis")
        XCTAssertFalse(codes.contains(FujiPTP.PresetProp.monochromaticMG.rawValue),
                       "Sepia must not write the magenta–green axis")
    }

    /// The contrast case: the same values on ACROS are written, so the rule is about Sepia rather
    /// than about monochrome.
    func testAcrosStillWritesItsToning() {
        let acros = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 3, monochromaticColorMG: -2)
        let codes = Set(FujiPresetCodec.encode(acros, model: model, slot: .empty).map(\.0))
        XCTAssertTrue(codes.contains(FujiPTP.PresetProp.monochromaticWC.rawValue))
        XCTAssertTrue(codes.contains(FujiPTP.PresetProp.monochromaticMG.rawValue))
    }

    /// Bytes sitting in those properties on a Sepia bank are whatever the slot last held under
    /// another simulation. Reading them back would invent a value nobody could have set.
    func testASepiaSlotsLeftoverToningBytesAreNotReadAsARecipeValue() {
        var props = self.props(for: RecipeSettings(filmSimulation: .sepia))
        props[FujiPTP.PresetProp.monochromaticWC.rawValue] = FujiEncoding.packI16(30)
        props[FujiPTP.PresetProp.monochromaticMG.rawValue] = FujiEncoding.packI16(-20)
        let decoded = FujiPresetCodec.decode(props, name: nil, model: model).settings
        XCTAssertNil(decoded.monochromaticColorWC, "a Sepia slot has no warm–cool value to report")
        XCTAssertNil(decoded.monochromaticColorMG)
    }

    private func assertRoundTrip(_ settings: RecipeSettings,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let profile = FujiPresetCodec.decode(props(for: settings), name: nil, model: model)
        // The control for the whole divergence feature. Everything here came out of our own
        // encoder, so a divergence would mean the decoder is flagging values it produced itself —
        // and a warning that fires on the one hardware-verified body is worse than no warning.
        XCTAssertEqual(profile.divergences, [], "a clean round trip must diverge from nothing",
                       file: file, line: line)
        XCTAssertEqual(profile.unsupportedFields, [:], "and preserve nothing", file: file, line: line)
        let decoded = profile.settings
        XCTAssertEqual(decoded.filmSimulation, settings.filmSimulation, "filmSimulation", file: file, line: line)
        XCTAssertEqual(decoded.dynamicRange, settings.dynamicRange, "dynamicRange", file: file, line: line)
        XCTAssertEqual(decoded.grain, settings.grain, "grain", file: file, line: line)
        XCTAssertEqual(decoded.colorChromeEffect, settings.colorChromeEffect, "colorChromeEffect", file: file, line: line)
        XCTAssertEqual(decoded.colorChromeFXBlue, settings.colorChromeFXBlue, "colorChromeFXBlue", file: file, line: line)
        XCTAssertEqual(decoded.whiteBalance, settings.whiteBalance, "whiteBalance", file: file, line: line)
        XCTAssertEqual(decoded.highlightTone, settings.highlightTone, "highlightTone", file: file, line: line)
        XCTAssertEqual(decoded.shadowTone, settings.shadowTone, "shadowTone", file: file, line: line)
        XCTAssertEqual(decoded.color, settings.color, "color", file: file, line: line)
        XCTAssertEqual(decoded.sharpness, settings.sharpness, "sharpness", file: file, line: line)
        XCTAssertEqual(decoded.highISONR, settings.highISONR, "highISONR", file: file, line: line)
        XCTAssertEqual(decoded.clarity, settings.clarity, "clarity", file: file, line: line)
    }

    func testColorRecipeRoundTrips() {
        assertRoundTrip(RecipeSettings(
            filmSimulation: .classicChrome,
            grain: GrainEffect(strength: .weak, size: .small),
            colorChromeEffect: .strong, colorChromeFXBlue: .weak,
            whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 2, shiftBlue: -3, kelvin: nil),
            dynamicRange: .dr400,
            highlightTone: -0.5, shadowTone: 1.0, color: 2, sharpness: -1, highISONR: -3, clarity: 1))
    }

    /// Monochrome drops `color` and picks up the toning axes, so it takes a different branch in
    /// both directions.
    func testMonochromeRecipeRoundTrips() {
        assertRoundTrip(RecipeSettings(
            filmSimulation: .acrosR, monochromaticColorWC: 2,
            grain: GrainEffect(strength: .strong, size: .large),
            colorChromeEffect: .off, colorChromeFXBlue: .off,
            whiteBalance: WhiteBalance(mode: .auto, shiftRed: 0, shiftBlue: 0, kelvin: nil),
            dynamicRange: .dr200,
            highlightTone: 1.0, shadowTone: 2.0, sharpness: 1, highISONR: -4, clarity: 3))
    }

    /// DR Auto is a sentinel on D190 (`0xFFFF` → −1), not a percentage, and for a long time neither
    /// direction handled it: the encoder passed the slot's own dynamic range through and reported it
    /// written, and the decoder filed the sentinel as an unrecognized divergence, so reading a slot
    /// the user had set to DR AUTO produced a recipe with no dynamic range at all.
    func testDynamicRangeAutoRoundTrips() {
        // Grain Off explicitly: the codec writes it for a recipe that sets none, so a round trip
        // that left it out would be comparing against a value the encoder had supplied.
        let settings = RecipeSettings(filmSimulation: .provia,
                                      grain: GrainEffect(strength: .off, size: nil),
                                      colorChromeEffect: .off, colorChromeFXBlue: .off,
                                      whiteBalance: WhiteBalance(mode: .auto, shiftRed: 0,
                                                                 shiftBlue: 0, kelvin: nil),
                                      dynamicRange: .auto,
                                      highlightTone: 0, shadowTone: 0, color: 0, sharpness: 0,
                                      highISONR: 0, clarity: 0)
        assertRoundTrip(settings)

        // The bytes themselves, so a change to the sentinel can't pass by matching itself.
        XCTAssertEqual(props(for: settings)[FujiPTP.PresetProp.dynamicRange.rawValue],
                       Data([0xFF, 0xFF]), "DR Auto writes 0xFFFF to D190")
    }

    /// Kelvin white balance carries a value no other mode does.
    func testKelvinWhiteBalanceRoundTrips() {
        assertRoundTrip(RecipeSettings(
            filmSimulation: .provia,
            grain: GrainEffect(strength: .off, size: nil),
            colorChromeEffect: .off, colorChromeFXBlue: .off,
            whiteBalance: WhiteBalance(mode: .kelvin, shiftRed: -4, shiftBlue: 5, kelvin: 5500),
            dynamicRange: .dr100,
            highlightTone: 0, shadowTone: 0, color: 0, sharpness: 0, highISONR: 0, clarity: 0))
    }

    /// The whole point of the mock: the same encode/decode the hardware path uses, driven through
    /// the transport contract. Grain deliberately goes through the X-T50's asymmetric D195 (writes
    /// take 1–5, reads report Off as 6/7), so a round trip that survives it is a real result.
    func testRoundTripThroughTheTransport() async throws {
        var faults = MockCameraFaults()
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        try await transport.open()

        let settings = RecipeSettings(
            filmSimulation: .classicNeg,
            grain: GrainEffect(strength: .weak, size: .large),
            colorChromeEffect: .weak, colorChromeFXBlue: .strong,
            whiteBalance: WhiteBalance(mode: .daylight, shiftRed: -2, shiftBlue: 4, kelvin: nil),
            dynamicRange: .dr400,
            highlightTone: 1.5, shadowTone: -1.0, color: -2, sharpness: 2, highISONR: -2, clarity: -3)

        try await transport.writeProperty(FujiPTP.Prop.slotSelector, FujiEncoding.packU16(3))
        for (code, bytes) in FujiPresetCodec.encode(settings, model: model, slot: .empty) {
            try await transport.writeProperty(code, bytes)
        }

        var readBack: FujiPresetCodec.Props = [:]
        for prop in FujiPTP.PresetProp.allCases {
            if let data = try await transport.readProperty(prop.rawValue) { readBack[prop.rawValue] = data }
        }
        let decoded = FujiPresetCodec.decode(readBack, name: nil, model: model).settings

        XCTAssertEqual(decoded.filmSimulation, settings.filmSimulation)
        XCTAssertEqual(decoded.grain, settings.grain, "D195 survived the write/read asymmetry")
        XCTAssertEqual(decoded.whiteBalance, settings.whiteBalance)
        XCTAssertEqual(decoded.highlightTone, settings.highlightTone)
        XCTAssertEqual(decoded.clarity, settings.clarity)
    }

    /// An unset Color Chrome effect is not preserved as "unset": the codec writes Off, and Off is
    /// what comes back. Worth pinning, because it means the app cannot tell a recipe that never
    /// specified Color Chrome from one that specified Off — and on a push, both switch it off.
    func testUnsetColorChromeDecodesAsOff() {
        let settings = RecipeSettings(filmSimulation: .provia, dynamicRange: .dr100)
        XCTAssertNil(settings.colorChromeEffect)
        let decoded = FujiPresetCodec.decode(props(for: settings), name: nil, model: model).settings
        XCTAssertEqual(decoded.colorChromeEffect, .off)
        XCTAssertEqual(decoded.colorChromeFXBlue, .off)
    }

    /// Grain Off is the case the asymmetry exists for: the app writes 1, the camera reports 6 or 7,
    /// and `readBackMatches` has to compare by decoded meaning rather than bytes to avoid a false
    /// mismatch on every single push.
    func testGrainOffSurvivesTheAsymmetryThroughTheTransport() async throws {
        var faults = MockCameraFaults()
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        try await transport.open()

        let wrote = FujiEncoding.packU16(1)   // Off, write-side encoding
        try await transport.writeProperty(FujiPTP.PresetProp.grain.rawValue, wrote)
        let read = try await transport.readProperty(FujiPTP.PresetProp.grain.rawValue)

        XCTAssertNotEqual(read, wrote, "the camera does not echo what was written for D195")
        let decoded = read.flatMap(FujiEncoding.decodeInt16).flatMap(FujiEncoding.flatToGrain)
        XCTAssertEqual(decoded?.strength, .off, "but it means the same thing")
        XCTAssertTrue(SlotWriteVerification.readBackMatches(FujiPTP.PresetProp.grain.rawValue,
                                                            wrote: wrote, read: read),
                      "so the read-back verifies")
        XCTAssertFalse(SlotWriteVerification.readBackMatches(FujiPTP.PresetProp.sharpness.rawValue,
                                                             wrote: wrote, read: read),
                       "and only D195 is compared by meaning")
    }

    // MARK: Divergence — values a body returns that this app's tables don't contain

    /// `decode` with one property overridden, the way a body with different encodings answers.
    private func decode(overriding prop: FujiPTP.PresetProp, with bytes: Data) -> DecodedProfile {
        var raw = props(for: RecipeSettings(
            filmSimulation: .classicChrome,
            grain: GrainEffect(strength: .weak, size: .small),
            colorChromeEffect: .strong, colorChromeFXBlue: .weak,
            whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 0, shiftBlue: 0, kelvin: nil),
            dynamicRange: .dr400,
            highlightTone: 0, shadowTone: 0, color: 0, sharpness: 0, highISONR: 0, clarity: 0))
        raw[prop.rawValue] = bytes
        return FujiPresetCodec.decode(raw, name: nil, model: model)
    }

    /// The worst decode in the file, and the reason this feature exists: every other miss produced a
    /// *missing* value, which reads as "not read". This one produced a specific, plausible, wrong
    /// one, on the field a recipe is most often judged by.
    func testUnknownWhiteBalanceModeIsNotReportedAsAuto() {
        let profile = decode(overriding: .whiteBalance, with: FujiEncoding.packU16(0x8099))

        XCTAssertNil(profile.settings.whiteBalance, "never guess a mode we did not read")
        XCTAssertEqual(profile.divergences.count, 1)
        XCTAssertEqual(profile.divergences.first?.code, FujiPTP.PresetProp.whiteBalance.rawValue)
        XCTAssertEqual(profile.divergences.first?.kind, .unrecognized)
        XCTAssertEqual(profile.unsupportedFields.count, 1, "and keep the raw value where it can be read")
        XCTAssertTrue(profile.divergences.first!.summary.contains("0x8099"),
                      "the raw value is the fact I need; got \(profile.divergences.first!.summary)")
    }

    /// Custom 1–3 is a white balance the user measured on that camera; the X-T50 reads Custom 1 as
    /// `0x8008` (fw 1.32, 2026-10-15). The app knows the value, so a bank on it is not a bank the app
    /// "couldn't read" — and it is still not a recipe value, so the field stays unset and the recipe
    /// pushes Auto like any recipe without a white balance.
    func testCustomWhiteBalanceIsRecognisedButNeverARecipeValue() {
        let profile = decode(overriding: .whiteBalance, with: FujiEncoding.packU16(0x8008))

        XCTAssertNil(profile.settings.whiteBalance, "a measurement on one camera is not a recipe value")
        XCTAssertEqual(profile.divergences.count, 1)
        XCTAssertEqual(profile.divergences.first?.kind, .cameraOnly(label: "Custom 1"))
        XCTAssertEqual(profile.unsupportedFields, [:], "known, so nothing to flag as unread or to preserve")
        XCTAssertEqual(profile.cameraOnlyFields, [RecipeField.whiteBalance.displayName: "Custom 1"])

        let written = FujiPresetCodec.encode(profile.settings, model: model, slot: .holds(profile.rawProperties))
        XCTAssertEqual(written.first { $0.code == FujiPTP.PresetProp.whiteBalance.rawValue }?.bytes,
                       FujiEncoding.packU16(0x0002),
                       "pushed back as Auto, the app's default for a recipe with no white balance")
    }

    func testUnknownFilmSimulationByteIsRecorded() {
        let profile = decode(overriding: .filmSimulation, with: FujiEncoding.packU16(0x00F0))

        XCTAssertNil(profile.settings.filmSimulation)
        XCTAssertEqual(profile.divergences.map(\.code), [FujiPTP.PresetProp.filmSimulation.rawValue])
    }

    /// `valueToEffectIfKnown` answers nil for a value it doesn't know, never `.off`, which would be
    /// indistinguishable from a camera genuinely set to Off.
    func testUnknownColourChromeValueIsNotReportedAsOff() {
        let profile = decode(overriding: .colorChrome, with: FujiEncoding.packU16(9))

        XCTAssertNil(profile.settings.colorChromeEffect)
        XCTAssertEqual(profile.divergences.map(\.code), [FujiPTP.PresetProp.colorChrome.rawValue])
    }

    func testUnknownHighISONRValueIsRecorded() {
        let profile = decode(overriding: .highISONR, with: FujiEncoding.packU16(0x9000))

        XCTAssertNil(profile.settings.highISONR)
        XCTAssertEqual(profile.divergences.map(\.code), [FujiPTP.PresetProp.highISONR.rawValue])
    }

    /// An unknown grain value decodes to no grain, and the raw value is recorded rather than lost.
    func testAnUnknownGrainValueIsDroppedAndRecorded() {
        let profile = decode(overriding: .grain, with: FujiEncoding.packU16(12))

        XCTAssertNil(profile.settings.grain)
        XCTAssertEqual(profile.divergences.map(\.code), [FujiPTP.PresetProp.grain.rawValue])
    }

    /// A body storing tone ×100 rather than ×10. It decodes to a plausible number, so only the
    /// model's own range catches it — and the value is kept, because -50 is still the best reading
    /// of what the camera holds.
    func testOutOfRangeToneIsKeptButFlagged() {
        let profile = decode(overriding: .highlightTone, with: FujiEncoding.packI16(-500))

        XCTAssertEqual(profile.settings.highlightTone, -50, "kept, not dropped")
        XCTAssertEqual(profile.divergences.count, 1)
        guard case .outOfRange = profile.divergences.first?.kind else {
            return XCTFail("expected an out-of-range divergence, got \(String(describing: profile.divergences.first?.kind))")
        }
        XCTAssertEqual(profile.unsupportedFields, [:],
                       "an out-of-range value is in the settings; listing it as preserved would be a second account of one number")
    }

    // MARK: Every film simulation

    /// Only four of twenty simulations had ever been through `encode` in a test; the
    /// `0x11 classicNeg` / `0x13 nostalgicNeg` / `0x14 realaAce` block had never. A transposed byte
    /// in `filmSimToByte` would write one simulation while the app displayed another, verify against
    /// itself, and report applied — which is the exact shape of a mismatch nobody can see.
    func testEveryFilmSimulationRoundTrips() {
        for sim in FilmSimulation.allCases {
            var settings = sim.isMonochrome
                ? RecipeSettings(filmSimulation: sim, monochromaticColorWC: 1,
                                 grain: GrainEffect(strength: .weak, size: .small),
                                 colorChromeEffect: .off, colorChromeFXBlue: .off,
                                 whiteBalance: WhiteBalance(mode: .auto, shiftRed: 0, shiftBlue: 0, kelvin: nil),
                                 dynamicRange: .dr200,
                                 highlightTone: 0, shadowTone: 0, sharpness: 0, highISONR: 0, clarity: 0)
                : RecipeSettings(filmSimulation: sim,
                                 grain: GrainEffect(strength: .weak, size: .small),
                                 colorChromeEffect: .off, colorChromeFXBlue: .off,
                                 whiteBalance: WhiteBalance(mode: .auto, shiftRed: 0, shiftBlue: 0, kelvin: nil),
                                 dynamicRange: .dr200,
                                 highlightTone: 0, shadowTone: 0, color: 0, sharpness: 0, highISONR: 0, clarity: 0)
            settings.filmSimulation = sim
            assertRoundTrip(settings)
            // And the byte itself, so a table error can't hide behind a symmetric inverse.
            let bytes = props(for: settings)[FujiPTP.PresetProp.filmSimulation.rawValue]
            XCTAssertEqual(bytes.flatMap(FujiEncoding.decodeInt16), FujiEncoding.filmSimToByte[sim],
                           "\(sim) wrote the wrong D192 byte")
        }
        XCTAssertEqual(Set(FujiEncoding.filmSimToByte.values).count, FilmSimulation.allCases.count,
                       "two simulations share a byte")
    }

    // MARK: A read that came back with nothing

    /// `readProperty` answers nil *without throwing* when a body replies `0x2001 OK` with no data
    /// phase (no recorded body does; the fault models the case), so an occupied slot's property goes
    /// missing from the base read looking exactly like an empty slot's. `encode` used to resolve that by writing a
    /// hardcoded default — ten of them — which the read-back then confirmed, because the camera was
    /// reading back the value the push had just invented.
    private func encoded(_ settings: RecipeSettings, slot: FujiPresetCodec.Slot) -> FujiPresetCodec.Props {
        var out: FujiPresetCodec.Props = [:]
        for (code, bytes) in FujiPresetCodec.encode(settings, model: model, slot: slot) { out[code] = bytes }
        return out
    }

    /// Every seeded property, over a slot that answered for none of them but is known to be
    /// occupied. Not one of them may be written.
    func testAnUnreadPropertyIsNotWrittenOnAnOccupiedSlot() {
        let full = props(for: RecipeSettings(filmSimulation: .classicChrome, dynamicRange: .dr200))
        for prop in FujiPresetCodec.seedValues.keys {
            var base = full
            base[prop.rawValue] = nil
            // A recipe that sets none of the three fields with a non-passthrough branch, so every
            // seeded property reaches `passthrough` the way a housekeeping one does.
            let out = encoded(RecipeSettings(), slot: .holds(base))
            XCTAssertNil(out[prop.rawValue],
                         "\(prop.debugName) was invented from a read that answered nothing")
        }
    }

    /// The worst of the ten, on its own: no film simulation in the recipe and none in the read, on a
    /// slot that is plainly occupied. PROVIA would change the whole look of the slot.
    func testAnUnreadFilmSimulationIsNotOverwrittenWithProvia() {
        var base = props(for: RecipeSettings(filmSimulation: .classicChrome, dynamicRange: .dr200))
        base[FujiPTP.PresetProp.filmSimulation.rawValue] = nil
        var settings = RecipeSettings()
        XCTAssertNil(settings.filmSimulation)
        settings.sharpness = 1

        let out = encoded(settings, slot: .holds(base))

        XCTAssertNil(out[FujiPTP.PresetProp.filmSimulation.rawValue],
                     "the slot keeps whatever it holds; PROVIA is not a reading of it")
        XCTAssertNotNil(out[FujiPTP.PresetProp.sharpness.rawValue], "the recipe still writes")
    }

    /// An unset Dynamic Range writes Auto — the camera deciding, which is what "no opinion about
    /// dynamic range" means — so the bank's own DR400 is replaced rather than kept; inheriting it
    /// would make the same recipe pushed to two banks produce two looks. Auto on the wire is the
    /// `0xFFFF` sentinel, the same thing a recipe that says DR Auto writes.
    ///
    /// The exception is the bank that never reported a dynamic range. An unanswered read is not a
    /// licence to overwrite what we could not see.
    func testAnUnsetDynamicRangeWritesAutoUnlessTheSlotWentSilent() {
        let d190 = FujiPTP.PresetProp.dynamicRange.rawValue
        var settings = RecipeSettings(filmSimulation: .provia)
        settings.dynamicRange = nil

        var base = props(for: RecipeSettings(filmSimulation: .provia, dynamicRange: .dr400))
        XCTAssertEqual(encoded(settings, slot: .holds(base))[d190],
                       FujiEncoding.packI16(FujiEncoding.drAutoSlotValue),
                       "the recipe has no opinion, so the camera gets to have one")

        base[d190] = nil
        XCTAssertNil(encoded(settings, slot: .holds(base))[d190],
                     "but a slot that answered nothing is left alone")
    }

    /// A slot with no entry at all has nothing to preserve, so the seed values establish one —
    /// PROVIA among them. A push to hardware never encodes for an empty slot (`SlotWriter` treats
    /// every bank it read as held); the Demo Camera's seeded slots do.
    func testAnEmptySlotIsStillSeededWithTheDefaults() {
        let out = encoded(RecipeSettings(), slot: .empty)
        for (prop, seed) in FujiPresetCodec.seedValues {
            XCTAssertEqual(out[prop.rawValue], FujiEncoding.packU16(seed),
                           "\(prop.debugName) did not seed the new slot")
        }
        XCTAssertEqual(out[FujiPTP.PresetProp.filmSimulation.rawValue]
                        .flatMap(FujiEncoding.decodeInt16).flatMap { FujiEncoding.byteToFilmSim[$0] },
                       .provia)
    }

    /// A D192 that is present but not two bytes long. The slot counts as occupied — occupancy is
    /// D192's presence — and used to decode to a nil sim with no divergence, because the note lived
    /// inside the `if let`.
    func testAShortFilmSimulationPayloadIsRecordedNotSwallowed() {
        var raw = props(for: RecipeSettings(filmSimulation: .provia, dynamicRange: .dr100))
        raw[FujiPTP.PresetProp.filmSimulation.rawValue] = Data([0x01])   // one byte

        let profile = FujiPresetCodec.decode(raw, name: nil, model: model)

        XCTAssertNil(profile.settings.filmSimulation)
        XCTAssertEqual(profile.divergences.map(\.code), [FujiPTP.PresetProp.filmSimulation.rawValue])
        XCTAssertEqual(profile.unsupportedFields.count, 1, "and the raw fact is preserved")
    }

    // MARK: Properties a body refuses

    private func codes(_ settings: RecipeSettings, model: CameraModel,
                       slot: FujiPresetCodec.Slot) -> Set<UInt16> {
        Set(FujiPresetCodec.encode(settings, model: model, slot: slot).map(\.code))
    }

    /// Part of a GFX100S bank, enough to exercise the passthrough path. C1–C6 in
    /// zgrimz/fujifilm-ptp-reference `evidence/gfx100s-20260915-194552` each hold these values
    /// [Owner report: GFX100S fw 2.13].
    private var gfxHeld: FujiPresetCodec.Props {
        [FujiPTP.PresetProp.imageSize.rawValue: FujiEncoding.packU16(14),
         FujiPTP.PresetProp.imageQuality.rawValue: FujiEncoding.packU16(2),
         FujiPTP.PresetProp.dRangePriority.rawValue: FujiEncoding.packU16(0),
         FujiPTP.PresetProp.filmSimulation.rawValue: FujiEncoding.packU16(1),
         FujiPTP.PresetProp.smoothSkin.rawValue: FujiEncoding.packU16(1),
         FujiPTP.PresetProp.lensModulationOptimizer.rawValue: FujiEncoding.packU16(1),
         FujiPTP.PresetProp.colorSpace.rawValue: FujiEncoding.packU16(1),
         FujiPTP.Prop.liveImageSize: FujiEncoding.packU16(14)]
    }

    /// D1A5 is live Image Size, excluded by namespace even when historical input includes it.
    /// D191 is omitted here only because the bank already holds the requested default Off.
    func testAGFX100SPushExcludesLiveImageSize() throws {
        let gfx = try XCTUnwrap(CameraModelRegistry.shared.model(withID: "GFX100S"))
        let out = codes(RecipeSettings(filmSimulation: .provia), model: gfx, slot: .holds(gfxHeld))

        XCTAssertFalse(out.contains(FujiPTP.Prop.liveImageSize))
        XCTAssertFalse(out.contains(FujiPTP.PresetProp.dRangePriority.rawValue),
                       "not withheld — simply nothing this recipe asks to change")
        // Not a narrowing: the other carried-through housekeeping still goes.
        XCTAssertTrue(out.contains(FujiPTP.PresetProp.imageSize.rawValue))
        XCTAssertTrue(out.contains(FujiPTP.PresetProp.colorSpace.rawValue))
    }

    /// Synthetic bank seeds also exclude live properties. Hardware pushes do not seed
    /// unreadable banks; this codec branch constructs the demo's initial fixture state.
    func testAnEmptyGFX100SSlotIsNotSeededWithIt() throws {
        let gfx = try XCTUnwrap(CameraModelRegistry.shared.model(withID: "GFX100S"))
        let out = codes(RecipeSettings(), model: gfx, slot: .empty)

        XCTAssertFalse(out.contains(FujiPTP.Prop.liveImageSize))
        XCTAssertTrue(out.contains(FujiPTP.PresetProp.imageSize.rawValue), "the rest still seeds")
        // D191 is seeded on an empty slot, where the seed is the only thing that decides what a
        // brand-new bank holds. Off is what it has always meant; it just has a name now.
        XCTAssertTrue(out.contains(FujiPTP.PresetProp.dRangePriority.rawValue),
                      "an empty bank is given D-Range Priority Off rather than left undefined")
    }

    /// The tripwire. Withholding is only ever safe for a property the app carries through rather
    /// than authors: a recipe field withheld here would silently drop a setting the user chose, and
    /// the push would report success for a value that never left the phone.
    func testWithholdingCanOnlyEverApplyToHousekeeping() {
        for model in CameraModelRegistry.shared.models {
            for prop in FujiPresetCodec.unwritableProperties(on: model) {
                XCTAssertNil(prop.recipeField,
                             "\(model.id) withholds \(prop.debugName), which is a recipe field")
            }
        }
    }

    /// The encoder force-unwraps the white-balance table, so every mode a recipe can hold must be in it.
    func testEveryWhiteBalanceModeHasAWireValue() {
        for mode in WhiteBalanceMode.allCases {
            XCTAssertNotNil(FujiEncoding.wbModeToValue[mode], mode.displayName)
        }
    }
}
