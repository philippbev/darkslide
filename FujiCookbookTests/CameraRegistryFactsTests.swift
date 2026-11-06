import XCTest
@testable import FujiCookbook

/// Per-body facts the registry takes from Fujifilm's published specification pages, manuals and
/// firmware notes, pinned so a group edit cannot quietly hand a body a control or a film
/// simulation it does not have. The protocol record holds menu facts only for bodies with USB
/// observations; each registry entry names its source, and the older bodies' manuals are linked in
/// `docs/supported-cameras.md#sources-for-older-bodies`.
final class CameraRegistryFactsTests: XCTestCase {

    private let registry = CameraModelRegistry.shared

    private func model(_ id: String) throws -> CameraModel {
        try XCTUnwrap(registry.model(withID: id), "\(id) is not in the registry")
    }

    // MARK: - Film simulations

    /// Fujifilm's specification pages list 17 film simulations for both: Classic Neg. and ETERNA
    /// are there, ETERNA Bleach Bypass is not.
    func testTheX100VAndXPro3Have17FilmSimulationsWithoutBleachBypass() throws {
        for id in ["X100V", "X-Pro3"] {
            let body = try model(id)
            XCTAssertFalse(body.supports(filmSimulation: .eternaBleachBypass), "\(id) has no Bleach Bypass")
            XCTAssertTrue(body.supports(filmSimulation: .classicNeg), "\(id) has Classic Neg.")
            XCTAssertTrue(body.supports(filmSimulation: .eterna), "\(id) has ETERNA")
            XCTAssertEqual(body.supportedFilmSimulations.count, 17, "\(id) lists 17 film simulations")
            XCTAssertTrue(monochromeGroupIsLast(body), "\(id) keeps the monochrome group last")
        }
    }

    /// The edit that takes Bleach Bypass off two bodies must not reach the other late X-Processor 4
    /// bodies, which ship with it.
    func testTheOtherLateGenIVBodiesKeepBleachBypass() throws {
        for id in ["X-T4", "X-S10", "X-E4", "X-T30 II"] {
            let body = try model(id)
            XCTAssertTrue(body.supports(filmSimulation: .eternaBleachBypass), "\(id) has Bleach Bypass")
            XCTAssertEqual(body.supportedFilmSimulations.count, 18, "\(id) lists 18 film simulations")
        }
    }

    /// Fujifilm's 2020-06-30 firmware release (GFX 50S 4.00, GFX 50R 2.00) adds Classic Neg. and
    /// ETERNA; Bleach Bypass and Nostalgic Neg. never reached these X-Processor Pro bodies.
    func testTheGFX50SAndGFX50RHaveClassicNegFromFirmware() throws {
        for id in ["GFX50S", "GFX50R"] {
            let body = try model(id)
            XCTAssertTrue(body.supports(filmSimulation: .classicNeg), "\(id) has Classic Neg.")
            XCTAssertTrue(body.supports(filmSimulation: .eterna), "\(id) has ETERNA")
            XCTAssertFalse(body.supports(filmSimulation: .eternaBleachBypass), "\(id) has no Bleach Bypass")
            XCTAssertFalse(body.supports(filmSimulation: .nostalgicNeg), "\(id) has no Nostalgic Neg.")
            XCTAssertEqual(body.supportedFilmSimulations.count, 17, "\(id) lists 17 film simulations")
            XCTAssertTrue(monochromeGroupIsLast(body), "\(id) keeps the monochrome group last")
        }
    }

    /// Once a monochrome simulation appears, every later entry is monochrome: the picker's order.
    private func monochromeGroupIsLast(_ body: CameraModel) -> Bool {
        let sims = body.supportedFilmSimulations
        guard let first = sims.firstIndex(where: { $0.isMonochrome }) else { return true }
        return sims[first...].allSatisfy { $0.isMonochrome }
    }

    // MARK: - Tone steps

    /// Their manuals print HIGHLIGHT TONE and SHADOW TONE as +4…−2 in whole steps; half steps
    /// arrived with the X-T4's generation. The single toning axis keeps the manual's −9…+9.
    func testTheXT3AndXT30UseWholeToneSteps() throws {
        for id in ["X-T3", "X-T30"] {
            let body = try model(id)
            for field: RecipeField in [.highlightTone, .shadowTone] {
                XCTAssertEqual(body.range(for: field), NumericRange(min: -2, max: 4, step: 1),
                               "\(id) \(field.displayName) is whole-step")
            }
            XCTAssertEqual(body.range(for: .monochromaticColor), NumericRange(min: -9, max: 9, step: 1), id)
            XCTAssertNil(body.range(for: .clarity), "\(id) has no Clarity")
        }
    }

    /// The X-Pro3 and X100V print HIGHLIGHT and SHADOW TONE as +4…−2 in whole steps, where the
    /// X-T4 of the same generation takes half steps; Clarity and the two ±18 toning axes stay.
    func testTheXPro3AndX100VUseWholeToneStepsAndKeepClarityAndToning() throws {
        for id in ["X-Pro3", "X100V"] {
            let body = try model(id)
            for field: RecipeField in [.highlightTone, .shadowTone] {
                XCTAssertEqual(body.range(for: field), NumericRange(min: -2, max: 4, step: 1),
                               "\(id) \(field.displayName) is whole-step")
            }
            XCTAssertEqual(body.range(for: .clarity), NumericRange(min: -5, max: 5, step: 1), id)
            XCTAssertEqual(body.range(for: .monochromaticColor), NumericRange(min: -18, max: 18, step: 1), id)
        }
        XCTAssertEqual(try model("X-T4").range(for: .highlightTone)?.step, 0.5, "the X-T4 keeps half steps")
    }

    /// The other late X-Processor 4 bodies and every X-Processor 5 body keep half steps, and every
    /// X-Processor Pro body is whole-step, so an edit cannot drift onto the wrong group.
    func testToneStepsFollowTheProcessorEverywhereButFourBodies() {
        for body in registry.models where !["X-T3", "X-T30", "X-Pro3", "X100V"].contains(body.id) {
            if body.processor == .exrProcessor {
                XCTAssertNil(body.range(for: .highlightTone), "\(body.id) carries no range at all")
                continue
            }
            let expected: Double = body.processor == .xProcessorPro ? 1 : 0.5
            XCTAssertEqual(body.range(for: .highlightTone)?.step, expected, body.id)
            XCTAssertEqual(body.range(for: .shadowTone)?.step, expected, body.id)
        }
    }

    // MARK: - White balance modes

    /// The WHITE BALANCE menu per body, from Fujifilm's manuals: the presets everywhere; Kelvin and
    /// Underwater on all but the X-M1; the two Auto priorities only where a manual prints them.
    func testWhiteBalanceModesFollowFujifilmsManuals() throws {
        let base: Set<WhiteBalanceMode> = [.auto, .daylight, .shade, .fluorescent1, .fluorescent2,
                                           .fluorescent3, .incandescent]
        let priorities: Set<WhiteBalanceMode> = [.autoWhitePriority, .autoAmbiencePriority]
        let withPriorities: Set<String> = ["X-T4", "X-S10", "X-E4", "X-T30 II", "X-T30 III", "X-T5", "X-T50",
                                           "X-H2", "X-H2S", "X100VI", "X-S20", "X-E5", "X-M5", "GFX100S",
                                           "GFX50S II", "GFX100 II", "GFX100S II", "GFX100RF"]
        for body in registry.models where body.id != CameraModelRegistry.demoModelID {
            XCTAssertTrue(body.supportedWhiteBalanceModes.isSuperset(of: base), body.id)
            if body.id == "X-M1" {
                XCTAssertEqual(body.supportedWhiteBalanceModes, base, "the X-M1 has no Kelvin or Underwater")
            } else {
                XCTAssertTrue(body.supportedWhiteBalanceModes.isSuperset(of: [.kelvin, .underwater]), body.id)
            }
            XCTAssertEqual(body.supportedWhiteBalanceModes.isSuperset(of: priorities), withPriorities.contains(body.id),
                           "\(body.id): the Auto priorities follow the manual, not the processor")
            if body.processor == .exrProcessor || body.processor == .xProcessorPro {
                XCTAssertTrue(body.supportedWhiteBalanceModes.isDisjoint(with: priorities), body.id)
            }
        }
        XCTAssertEqual(registry.demoModel.supportedWhiteBalanceModes, Set(WhiteBalanceMode.allCases))
        XCTAssertTrue(try model("X100V").supports(whiteBalanceMode: .kelvin))
        XCTAssertFalse(try model("X100V").supports(whiteBalanceMode: .autoWhitePriority))
    }

    // MARK: - X-Trans I, II and the X-Trans III additions

    private static let legacyIDs = ["X-Pro1", "X-E1", "X-M1", "X100S", "X-T1", "X-E2", "X-E2S", "X-T10", "X70", "X100T"]

    /// Film lists from Fujifilm's manuals: ten on X-Trans I and the X100S, eleven from the X-T1 on
    /// (Classic Chrome), five on the X-M1; no ACROS, Classic Neg. or ETERNA on any of them.
    func testTheXTransIAndIIBodiesHaveTheirManualsFilmLists() throws {
        let tens = ["X-Pro1", "X-E1", "X100S"]
        let elevens = ["X-T1", "X-E2", "X-E2S", "X-T10", "X70", "X100T"]
        for id in tens + elevens + ["X-M1"] {
            let body = try model(id)
            for sim: FilmSimulation in [.acros, .classicNeg, .eterna, .eternaBleachBypass, .nostalgicNeg, .realaAce] {
                XCTAssertFalse(body.supports(filmSimulation: sim), "\(id) has no \(sim.displayName)")
            }
            XCTAssertTrue(monochromeGroupIsLast(body), id)
        }
        for id in tens {
            let body = try model(id)
            XCTAssertEqual(body.supportedFilmSimulations.count, 10, id)
            XCTAssertFalse(body.supports(filmSimulation: .classicChrome), "\(id) has no Classic Chrome")
            XCTAssertTrue(body.supports(filmSimulation: .proNegHi) && body.supports(filmSimulation: .monochromeYe), id)
        }
        for id in elevens {
            let body = try model(id)
            XCTAssertEqual(body.supportedFilmSimulations.count, 11, id)
            XCTAssertTrue(body.supports(filmSimulation: .classicChrome), "\(id) has Classic Chrome")
        }
        let xM1 = try model("X-M1")
        XCTAssertEqual(xM1.supportedFilmSimulations.count, 5)
        XCTAssertFalse(xM1.supports(filmSimulation: .proNegHi), "the X-M1 has no PRO Neg pair")
        XCTAssertFalse(xM1.supports(filmSimulation: .monochromeYe), "the X-M1 has no filtered monochromes")
    }

    /// No grain, Color Chrome, D-Range Priority, Clarity or toning, and no numeric ranges: the
    /// manuals print the controls without values, so nothing here claims a limit.
    func testTheXTransIAndIIBodiesHaveNoGrainChromeOrToningAndNoRanges() throws {
        for id in Self.legacyIDs {
            let body = try model(id)
            XCTAssertEqual(body.processor, .exrProcessor, id)
            XCTAssertEqual(body.supportedFields,
                           [.filmSimulation, .whiteBalance, .dynamicRange, .highlightTone, .shadowTone,
                            .color, .sharpness, .highISONR], id)
            XCTAssertTrue(body.ranges.isEmpty, "\(id) claims no range")
            XCTAssertFalse(body.hasGrainSizeControl, id)
        }
    }

    /// The X-E3 is the X-Trans III group; the X-H1 adds ETERNA and D-Range Priority to it.
    func testTheXE3MatchesTheXTransIIIGroupAndTheXH1AddsEternaAndPriority() throws {
        let xT20 = try model("X-T20")
        let xE3 = try model("X-E3")
        let xH1 = try model("X-H1")
        XCTAssertEqual(xE3.supportedFields, xT20.supportedFields)
        XCTAssertEqual(xE3.supportedFilmSimulations, xT20.supportedFilmSimulations)
        XCTAssertEqual(xE3.ranges, xT20.ranges)
        XCTAssertTrue(xH1.supports(.dRangePriority), "D-Range Priority debuted on the X-H1")
        XCTAssertTrue(xH1.supports(filmSimulation: .eterna), "so did ETERNA")
        XCTAssertEqual(xH1.supportedFilmSimulations.count, 16)
        XCTAssertFalse(xH1.supports(.colorChromeEffect) || xH1.supports(.monochromaticColor) || xH1.supports(.clarity))
        XCTAssertEqual(xH1.range(for: .highlightTone)?.step, 1)
        XCTAssertFalse(xH1.hasGrainSizeControl)
    }

    /// Untested rather than blocked (the record holds no USB observation of any of them), without
    /// the bank protocol, and a Kitchen only where Fujifilm's X RAW Studio list reaches: the X-E3
    /// and X-H1.
    func testTheLegacyBodiesAreUntestedWithoutSlots() throws {
        let banks: [String: Int?] = ["X-Pro1": 7, "X-E1": 7, "X-M1": 1, "X100S": 3, "X-T1": 7, "X-E2": 7,
                                     "X-E2S": 7, "X-T10": 7, "X70": 7, "X100T": nil, "X-E3": 7, "X-H1": 7]
        for (id, documented) in banks {
            let body = try model(id)
            XCTAssertFalse(body.allowsWrite, id)
            XCTAssertFalse(body.supportsSlotProtocol, id)
            XCTAssertEqual(body.supportsRawConversion, body.sensorGeneration == .xTransIII, id)
            XCTAssertFalse(body.hasFilmSimulationDial, id)
            XCTAssertEqual(body.documentedSlotCount, documented, id)
            XCTAssertEqual(body.slotCount, 7, "\(id) keeps the registry's assumption")
            XCTAssertEqual(body.writeSupport, .untested, "\(id): no record of its banks, so no failure to quote")
        }
    }
}
