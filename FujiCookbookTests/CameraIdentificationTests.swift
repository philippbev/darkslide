import XCTest
@testable import FujiCookbook

/// Acceptance tests for camera identification.
///
/// The trap these guard: the X-T30 III normalizes to a string that contains "X-T30 II", and a
/// matcher that takes the longest id it can find inside the name by unanchored substring resolves
/// it to the X-T30 II — handing a shipping body the wrong film list and the wrong dial behaviour.
/// Two things prevent it: the X-T30 III has its own registry entry, and matching is anchored at
/// word boundaries so no longer name can inherit a shorter model's capabilities.
///
/// Menu facts for bodies the record leaves out (film lists, bank counts, controls) are the registry's,
/// which names the Fujifilm manual or firmware note behind each entry; the older bodies' manuals are
/// linked in `docs/supported-cameras.md#sources-for-older-bodies`.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/04-custom-slots.md#persistence-and-the-red-dot`,
/// `docs/07-cameras.md#bank-counts-from-fujifilms-manuals`, `docs/07-cameras.md#gfx100s`,
/// `docs/07-cameras.md#x-m5`, `docs/07-cameras.md#x-pro3`, and `docs/07-cameras.md#x-t20`.
final class CameraIdentificationTests: XCTestCase {

    /// The one substitution in the push that raised no issue: a recipe with no film simulation.
    /// `analyze` spoke only when a sim was set *and* unsupported, so nil went straight to the
    /// encoder's passthrough with no warning on the way.
    func testANilFilmSimulationIsAnIssueNotASilence() {
        let xT50 = CameraModelRegistry.shared.model(withID: "X-T50")!
        let issues = RecipeCompatibility.analyze(RecipeSettings(dynamicRange: .dr400), for: xT50)

        XCTAssertTrue(issues.contains { $0.kind == .filmSimulationUnset && $0.field == .filmSimulation },
                      "got: \(issues.map(\.kind))")
        // And the control: a set, supported sim raises nothing about the sim.
        let fine = RecipeCompatibility.analyze(RecipeSettings(filmSimulation: .realaAce), for: xT50)
        XCTAssertFalse(fine.contains { $0.field == .filmSimulation })
    }

    private let registry = CameraModelRegistry.shared
    private let xT30III = "FUJIFILM X-T30 III"

    // MARK: The X-T30 III

    func testXT30IIIResolvesToItself() {
        let id = registry.identify(productName: xT30III)
        XCTAssertEqual(id.model?.id, "X-T30 III")
        XCTAssertEqual(id.confidence, "exact")
        XCTAssertNotEqual(registry.model(matchingProductName: xT30III)?.id, "X-T30 II",
                          "a longer product name must not inherit a shorter model's capabilities")
    }

    /// Film simulations follow the processor: X-Trans 4 sensor, X-Processor 5, ships REALA ACE.
    func testXT30IIIIsNotToldItLacksRealaAce() {
        let resolved = registry.model(matchingProductName: xT30III)
        XCTAssertEqual(resolved?.processor, .xProcessor5)
        XCTAssertEqual(resolved?.sensorGeneration, .xTransIV)
        XCTAssertTrue(resolved?.supports(filmSimulation: .realaAce) ?? false,
                      "the app must not claim a shipping film simulation is unavailable")
        XCTAssertTrue(resolved?.supports(filmSimulation: .nostalgicNeg) ?? false)
    }

    func testXT30IIIIsWarnedAboutItsFilmSimulationDial() {
        XCTAssertTrue(registry.model(matchingProductName: xT30III)?.hasFilmSimulationDial ?? false)
    }

    /// Writable and still untested — which is the whole point of the pairing.
    ///
    /// Nobody has seen this body on hardware, but a read-only body can't produce the write evidence
    /// that would verify it, and the `.inferred` bodies already write on the same absence of
    /// evidence. So the assertion that matters is that writing is on, the push caveat is still
    /// shown, and naming came with it.
    func testXT30IIIWritesUnverifiedAndSaysSo() {
        let resolved = registry.model(matchingProductName: xT30III)
        XCTAssertTrue(resolved?.allowsWrite ?? false)
        XCTAssertNil(resolved?.writeSupport.blockReason, "a writable body owes no block reason")
        XCTAssertEqual(resolved?.verification, .inferred, "promoted on inference, not on a report")
        XCTAssertNotNil(resolved?.verification.pushCaveat, "and the user is told exactly that before a push")
        // A push names the bank it writes, so naming comes with writing. (Not a persistence
        // safeguard: property writes persist on their own, with or without a name.)
        XCTAssertTrue(resolved?.supportsSlotNaming ?? false)
    }

    /// The X-M5 shares the X-T30 III's entry and stands on more: its owner's full write pass
    /// through the app (fw 1.30, 2026-10-31) — pushed, power-cycled, menu-confirmed, restored — so
    /// it is `.ownerReport`, and the push caveat, which only `.inferred` carries, is gone.
    func testXM5WritesOnItsOwnersReportAndSaysSo() {
        let m5 = registry.model(withID: "X-M5")
        XCTAssertTrue(m5?.allowsWrite ?? false)
        XCTAssertEqual(m5?.verification, .ownerReport, "promoted on its owner's write pass, not on inference")
        XCTAssertNil(m5?.verification.pushCaveat, "the push screen flags only bodies nobody has reported a write to")
        XCTAssertTrue(m5?.supportsSlotNaming ?? false)
    }

    // MARK: The matcher itself, against a model list that lacks the X-T30 III

    /// The registry without the X-T30 III and X-M5 — so the test says what the *algorithm* does
    /// with the X-T30 III's name, independent of the entry that makes it exact.
    private var withoutTheIII: [CameraModel] { registry.models.filter { $0.id != "X-T30 III" && $0.id != "X-M5" } }

    func testWordBoundaryStopsTheXT30IIIFromMatchingTheXT30II() {
        let id = CameraModelRegistry.identify(xT30III, in: withoutTheIII, aliases: [:])
        XCTAssertEqual(id, .unknown, "X-T30 II, X-T30 and X-T3 are all followed by a letter or digit, not a boundary")
    }

    func testASuffixedNameStillGuessesAtABoundary() {
        let id = CameraModelRegistry.identify("FUJIFILM X-T5 TETHER", in: registry.models, aliases: [:])
        XCTAssertEqual(id.model?.id, "X-T5")
        XCTAssertEqual(id.confidence, "heuristic")
        XCTAssertFalse(id.isTrusted, "a guess reads, never writes")
        XCTAssertNotNil(id.guessBanner(productName: "FUJIFILM X-T5 TETHER"))
        XCTAssertEqual(WriteDecision.decide(identification: id, observed: ObservedCapabilities(),
                                            firmwareVersion: nil, serialHash: nil),
                       .undecided, "a guess is decided by its slot read, not by the match")
    }

    func testTheLongestBoundedIdWins() {
        let id = CameraModelRegistry.identify("X-T30 II (tether)", in: registry.models, aliases: [:])
        XCTAssertEqual(id.model?.id, "X-T30 II", "not X-T3, not X-T30")
        XCTAssertEqual(id.confidence, "heuristic")
    }

    func testASpacelessSpellingIsAnAlias() {
        let id = CameraModelRegistry.identify("FUJIFILM X-T30II", in: registry.models, aliases: [:])
        XCTAssertEqual(id.model?.id, "X-T30 II")
        XCTAssertEqual(id.confidence, "alias")
        XCTAssertTrue(id.isTrusted)
    }

    func testTheAliasTableIsConsulted() {
        let id = CameraModelRegistry.identify("FUJIFILM X-T5 MARK I", in: registry.models, aliases: ["X-T5 MARK I": "X-T5"])
        XCTAssertEqual(id.model?.id, "X-T5")
        XCTAssertEqual(id.confidence, "alias")
        XCTAssertEqual(id.reportLabel, "alias(FUJIFILM X-T5 MARK I)")
    }

    func testAnUnknownBodyResolvesToNil() {
        XCTAssertEqual(registry.identify(productName: "FUJIFILM X-T99"), .unknown)
        XCTAssertNil(registry.model(matchingProductName: "FUJIFILM X-T99"),
                     "a product name matching no registry entry must not resolve")
        XCTAssertEqual(registry.identify(productName: ""), .unknown)
        XCTAssertEqual(registry.identify(productName: "FUJIFILM"), .unknown, "the make alone is not a model")
    }

    /// The bodies that work today must keep working, and as exact matches.
    func testKnownBodiesStillResolveExactly() {
        for id in ["X-T50", "X-T5", "X100VI", "X-H2S", "X-Pro3", "X-T30 II", "X-M5", "X100F"] {
            let resolved = registry.identify(productName: "FUJIFILM \(id)")
            XCTAssertEqual(resolved.model?.id, id, "\(id) must keep resolving")
            XCTAssertEqual(resolved.confidence, "exact", "\(id) is an exact match")
        }
        XCTAssertEqual(registry.identify(productName: "x-t50").confidence, "exact", "case is not identity")
        XCTAssertEqual(registry.identify(productName: "  X-T50  ").confidence, "exact", "neither is whitespace")
    }

    // MARK: Processor axis

    func testFilmSimulationsFollowTheProcessor() {
        let xT30II = registry.model(withID: "X-T30 II")!
        let xT30III = registry.model(withID: "X-T30 III")!
        XCTAssertEqual(xT30II.sensorGeneration, xT30III.sensorGeneration, "same sensor")
        XCTAssertNotEqual(xT30II.processor, xT30III.processor, "different processor")
        XCTAssertFalse(xT30II.supports(filmSimulation: .realaAce))
        XCTAssertTrue(xT30III.supports(filmSimulation: .realaAce))
        XCTAssertEqual(xT30III.supportedFilmSimulations, registry.model(withID: "X-T50")!.supportedFilmSimulations,
                       "the list is the processor's, not the entry's")
    }

    // MARK: - The GFX line

    /// The body behind the first GFX report. The name it puts in `GetDeviceInfo` has no space in
    /// it, which is what the registry id matches.
    func testTheGFX100SResolvesExactly() {
        let resolved = registry.identify(productName: "GFX100S")
        XCTAssertEqual(resolved.model?.id, "GFX100S")
        XCTAssertEqual(resolved.confidence, "exact")
        XCTAssertEqual(registry.identify(productName: "FUJIFILM GFX100S").model?.id, "GFX100S")
    }

    /// Fujifilm's own marketing spells these with a space and cameras don't always agree, so both
    /// spellings have to land — the derived spaceless alias is what makes that free.
    func testSpacingInAGFXNameDoesNotDecideIdentity() {
        for (reported, id) in [("FUJIFILM GFX 100S", "GFX100S"), ("GFX 50S", "GFX50S"),
                               ("GFX100II", "GFX100 II"), ("FUJIFILM GFX 100 II", "GFX100 II"),
                               ("GFX100SII", "GFX100S II")] {
            let resolved = registry.identify(productName: reported)
            XCTAssertEqual(resolved.model?.id, id, "“\(reported)” must resolve to \(id)")
            XCTAssertTrue(resolved.isTrusted, "“\(reported)” is a spelling, not a guess")
        }
    }

    /// The trap this registry has hit once already, in GFX shape: a longer name must not inherit a
    /// shorter body's capabilities. "GFX100S II" contains "GFX100S", and "GFX100 II" contains
    /// "GFX100".
    func testALongerGFXNameDoesNotInheritAShorterBody() {
        XCTAssertEqual(registry.identify(productName: "GFX100S II").model?.id, "GFX100S II")
        XCTAssertEqual(registry.identify(productName: "GFX100 II").model?.id, "GFX100 II")
        let withoutTheSequels = registry.models.filter { !$0.id.hasSuffix(" II") }
        XCTAssertEqual(CameraModelRegistry.identify("GFX100S II", in: withoutTheSequels, aliases: [:]), .unknown,
                       "the II suffix means another camera, never GFX100S plus noise")
    }

    /// The X-Processor 4 group writes, and so does the GFX100RF; the other four GFX do not.
    ///
    /// The GFX100S has the report. The GFX100 and GFX 50S II were promoted with it on being the
    /// *same registry entry* — same fields, film list, ranges and processor — which is a stronger
    /// claim than the architecture inference the `.inferred` X-Trans bodies ship on. The GFX100RF
    /// writes on a published record (banks read, written and named through
    /// ImageCaptureCore), at `.community`. The 50S/50R (X-Processor Pro) and 100 II / 100S II
    /// (X-Processor 5) share no entry with a reported body and stay read-only — the GFX100RF's
    /// record is its own, not its processor group's.
    ///
    /// The Kitchen is a second, narrower axis on the same line, and it does not follow the write
    /// list: only the GFX100S converts, because only the GFX100S has produced a `0xD185` blob.
    func testTheWritableGFXBodiesAreADeliberateList() {
        let gfx = registry.models.filter { $0.sensorGeneration == .gfx }
        XCTAssertEqual(gfx.count, 8, "GFX 50S, 50R, 100, 100S, 50S II, 100 II, 100S II, 100RF")
        XCTAssertEqual(Set(gfx.filter(\.allowsWrite).map(\.id)), ["GFX100", "GFX100S", "GFX50S II", "GFX100RF"],
                       "a GFX body joining or leaving the write list should be a deliberate edit")
        XCTAssertEqual(registry.model(withID: "GFX100RF")?.verification, .community,
                       "a published record, not a write through this app")
        XCTAssertEqual(Set(gfx.filter { $0.allowsWrite && $0.id != "GFX100RF" }.map(\.processor)), [.xProcessor4],
                       "apart from the GFX100RF, the write list is exactly the group the reported body sits in")
        // The measurement does not travel with the promotion: six is a fact about the GFX100S.
        XCTAssertEqual(Set(gfx.filter { $0.allowsWrite && $0.id != "GFX100S" }.map(\.slotCount)), [7],
                       "the siblings keep the assumption the connect walk corrects at runtime")
        // The Kitchen does not follow the write list. A harvest returned the GFX100S's 0xD185 —
        // 621 bytes / 28 params / IOPCode FF149502, resolving at base 0x1FD
        // (zgrimz/fujifilm-ptp-reference `docs/06-conversion-profile.md#lengths-seen`) — and it
        // answers for the body that produced it and no other. A per-body assertion in
        // the loop below could not say that.
        XCTAssertEqual(Set(gfx.filter(\.supportsRawConversion).map(\.id)), ["GFX100S"],
                       "the GFX100S produced a profile; the other six never have")
        for model in gfx {
            XCTAssertTrue(model.supportsSlotProtocol, "\(model.id) must have its slots read")
            XCTAssertFalse(model.hasFilmSimulationDial, "\(model.id) has no film simulation dial")
            if case .blocked = model.writeSupport {
                XCTFail("\(model.id): no GFX body has a recorded bank-path failure to quote")
            }
        }
    }

    /// Measured, not assumed. `SetDevicePropValue 0xD18C = 7` answers `0x200A` on the GFX100S while
    /// 1–6 are accepted (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md#how-many-banks`,
    /// [Owner report: GFX100S fw 2.13]), and it is the one registry entry whose `slotCount` is lowered
    /// from 7. Every other entry carries the assumption, which the connect walk corrects at runtime.
    func testTheGFX100SCountsSixSlotsAndNoOtherBodyChanged() {
        XCTAssertEqual(registry.model(withID: "GFX100S")?.slotCount, 6)
        for model in registry.models where model.id != "GFX100S" {
            XCTAssertEqual(model.slotCount, 7, "\(model.id) should still carry the assumption")
        }
    }

    /// Fujifilm's manuals, checked body by body, and kept as a second number rather
    /// than folded into `slotCount` — see that field's doc comment for why lowering the ceiling is a
    /// one-way door. This pins the six bodies the manuals disagree with the registry on, the one
    /// body where manual and measurement agree, and a representative seven.
    func testDocumentedSlotCountsFollowFujifilmsManuals() {
        let documented = Dictionary(uniqueKeysWithValues:
            registry.models.compactMap { m in m.documentedSlotCount.map { (m.id, $0) } })
        // Mode-dial bodies capped at the dial's C positions.
        for id in ["X-S10", "X-S20", "X-M5"] {
            XCTAssertEqual(documented[id], 4, "\(id): the mode dial has C1–C4")
        }
        for id in ["GFX100S", "GFX50S II", "GFX100 II", "GFX100S II"] {
            XCTAssertEqual(documented[id], 6, "\(id): PSAM-dial GFX, C1–C6")
        }
        // Menu-recalled bodies, and the GFX100 which has no mode dial.
        for id in ["X-T50", "X-T30 III", "X-H2", "GFX100"] {
            XCTAssertEqual(documented[id], 7, "\(id)")
        }
        // The ceiling never dropped below the manual: that is the whole design.
        for model in registry.models {
            if let d = model.documentedSlotCount {
                XCTAssertGreaterThanOrEqual(model.slotCount, d,
                    "\(model.id): slotCount is the walk's ceiling and must not undercut the manual")
            }
        }
        // The GFX100S's lowered count agrees with its manual, as the USB and manual counts agree on
        // every body that has both (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md#how-many-banks`).
        let gfx100S = registry.model(withID: "GFX100S")!
        XCTAssertEqual(gfx100S.slotCount, gfx100S.documentedSlotCount)
    }

    /// A product rule, asserted for the whole registry: a push names the bank it writes, so every
    /// writable body has naming on, and the push screen's naming-off copy ("keeps its default slot
    /// labels") stays unreachable. It is not a persistence safeguard — on an X-T50 property writes
    /// take effect and persist with or without a name (fw 1.32, 2026-10-15/16;
    /// zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md`) — so a body that genuinely cannot
    /// be named would be a UI decision, not a data-loss risk.
    func testNoWritableBodyHasSlotNamingOff() {
        for model in registry.models where model.allowsWrite {
            XCTAssertTrue(model.supportsSlotNaming,
                          "\(model.id) is writable with the name write disabled — a push would leave the bank unnamed")
            XCTAssertEqual(model.slotNameMaxLength, CameraSlotName.maxLength, "\(model.id)")
        }
    }

    /// Writable, and honest about how firmly: an owner's own write pass carried it end to end —
    /// pushed, power-cycled, still there, confirmed against the camera's menu. Somebody has written
    /// to it and reported back, so the seal is the plain one and the push screen carries no caveat;
    /// the Camera Test still tells a tester that nobody here can re-drive it.
    func testTheGFX100SIsWritableOnItsOwnersReport() {
        let gfx100S = registry.model(withID: "GFX100S")!
        XCTAssertTrue(gfx100S.allowsWrite)
        XCTAssertNil(gfx100S.writeSupport.blockReason)
        XCTAssertEqual(gfx100S.verification, .ownerReport,
                       "a GFX write has been verified — on its owner's hardware, 2026-09-15. Not "
                       + "`.community`, which is somebody else's report with no write through this app behind it")
        XCTAssertNil(gfx100S.verification.pushCaveat, "an owner's write pass is a reported write")
        XCTAssertNotNil(gfx100S.verification.testerNote, "and the Camera Test still says what it rests on")
        // And the identification has to be trusted too, or `WriteDecision` refuses it.
        let exact = registry.identify(productName: "GFX100S")
        let connected = ConnectedCamera(productName: "GFX100S", firmwareVersion: "2.13",
                                        identification: exact, isDemo: false,
                                        writeAccess: WriteDecision.decide(identification: exact, observed: ObservedCapabilities(),
                                                                          firmwareVersion: "2.13", serialHash: nil))
        XCTAssertTrue(connected.isWritable)
        XCTAssertNil(connected.writeBlockReason)
        XCTAssertEqual(connected.capabilityBadge.text, "Read & Write",
                       "the seal a GFX100S owner sees — the plain one, for a body whose owner wrote "
                       + "to it and reported back")

        // The same body matched by name pattern rather than exactly still reads only.
        let guess = registry.identify(productName: "GFX100S TETHER")
        let guessed = ConnectedCamera(productName: "GFX100S TETHER", firmwareVersion: nil,
                                      identification: guess, isDemo: false,
                                      writeAccess: WriteDecision.decide(identification: guess, observed: ObservedCapabilities(),
                                                                        firmwareVersion: nil, serialHash: nil))
        XCTAssertEqual(guessed.model?.id, "GFX100S")
        XCTAssertFalse(guessed.isWritable, "a guess is undecided until its slot read has answered")
    }

    /// Film lists follow the processor, and the GFX line is where that stops meaning "the same list
    /// as the X-Trans body with this processor": Nostalgic Neg reached the X-Processor 4 GFX bodies
    /// by firmware, and no X-Trans gen-IV body ever got it.
    func testGFXFilmListsFollowTheirOwnFirmware() {
        let gfx100S = registry.model(withID: "GFX100S")!
        XCTAssertEqual(gfx100S.processor, .xProcessor4)
        XCTAssertTrue(gfx100S.supports(filmSimulation: .nostalgicNeg))
        XCTAssertFalse(gfx100S.supports(filmSimulation: .realaAce), "REALA ACE is X-Processor 5")
        XCTAssertFalse(registry.model(withID: "X-T4")!.supports(filmSimulation: .nostalgicNeg),
                       "the X-Trans body with the same processor did not get it")

        let gfx100II = registry.model(withID: "GFX100 II")!
        XCTAssertEqual(gfx100II.supportedFilmSimulations, registry.model(withID: "X-T50")!.supportedFilmSimulations,
                       "X-Processor 5 is X-Processor 5")
    }

    /// Color Chrome Effect debuted on the GFX 50S, so the two X-Processor Pro GFX bodies have a
    /// field the X-Trans III group does not — and still lack the gen-IV ones. Classic Neg. is a
    /// film simulation, not a field, and reached both by firmware (Fujifilm, 2020-06-30).
    func testTheGFX50SHasColorChromeAndNotTheGenIVFields() {
        let gfx50S = registry.model(withID: "GFX50S")!
        XCTAssertTrue(gfx50S.supports(.colorChromeEffect))
        XCTAssertFalse(registry.model(withID: "X-T20")!.supports(.colorChromeEffect))
        for absent: RecipeField in [.clarity, .colorChromeFXBlue, .monochromaticColor, .dRangePriority] {
            XCTAssertFalse(gfx50S.supports(absent), "\(absent) is not on an X-Processor Pro body")
        }
        XCTAssertTrue(gfx50S.supports(filmSimulation: .eterna))
        XCTAssertTrue(gfx50S.supports(filmSimulation: .classicNeg))
    }

    /// The GFX sensor is medium-format Bayer. Filing it under the nearest X-Trans generation would
    /// have made `sensorGeneration` a field nobody could trust, so it has its own case — and the
    /// feature gating that used to key off it now keys off the processor.
    func testGFXIsNotFiledUnderAnXTransGeneration() {
        for model in registry.models where model.id.hasPrefix("GFX") {
            XCTAssertEqual(model.sensorGeneration, .gfx, "\(model.id)")
        }
        XCTAssertTrue(registry.models.contains { $0.sensorGeneration == .xTransV }, "the X-Trans bodies kept theirs")
    }

    // MARK: - The slot-protocol capability

    /// The allowlist itself, asserted as a set rather than per-body: this is the list that decides
    /// which cameras never get a `0xD18C` write, so a body joining or leaving it should be a
    /// deliberate edit that fails this test, not a quiet side effect of adding a registry entry.
    /// The X-Pro3 joined on a published report that every bank operation fails on it at
    /// firmware 2.00; the read-only sweep is what would show whether the block is really absent.
    /// The X-Trans I, II and III bodies without a report are generation inference: no record shows
    /// the block on any of them.
    func testExactlyTheseBodiesLackTheSlotProtocol() {
        let without = Set(registry.models.filter { !$0.supportsSlotProtocol }.map(\.id))
        XCTAssertEqual(without, [
            "X-Pro1", "X-E1", "X-M1",
            "X100S", "X-T1", "X-E2", "X-E2S", "X-T10", "X70", "X100T",
            "X-Pro2", "X-T2", "X100F", "X-T20", "X-E3", "X-H1",
            "X-T3", "X-T30", "X-Pro3",
        ])
    }

    // MARK: - The legacy names

    /// The ten X-Trans I/II bodies, the X-E3 and the X-H1 resolve exactly from their product names.
    func testTheLegacyBodiesResolveExactly() {
        for id in ["X-Pro1", "X-E1", "X-M1", "X100S", "X-T1", "X-E2", "X-E2S", "X-T10", "X70", "X100T", "X-E3", "X-H1"] {
            let identification = registry.identify(productName: "FUJIFILM \(id)")
            XCTAssertEqual(identification.model?.id, id)
            if case .exact = identification {} else { XCTFail("\(id) is not an exact match: \(identification)") }
        }
    }

    /// "X-T1" is a prefix of "X-T10" and "X-E2" of "X-E2S", and the X100 bodies share a stem. The
    /// digit-or-letter boundary keeps each name on its own entry, and a longer name never falls
    /// back to the shorter id when its own entry is missing.
    func testAShorterLegacyIdDoesNotCaptureALongerName() {
        XCTAssertEqual(registry.identify(productName: "FUJIFILM X-T10 TETHER").model?.id, "X-T10")
        XCTAssertEqual(registry.identify(productName: "FUJIFILM X-E2S TETHER").model?.id, "X-E2S")
        XCTAssertEqual(registry.identify(productName: "FUJIFILM X100S TETHER").model?.id, "X100S")
        for (name, missing) in [("FUJIFILM X-T10", "X-T10"), ("FUJIFILM X-E2S", "X-E2S"), ("FUJIFILM X100T", "X100T")] {
            let without = registry.models.filter { $0.id != missing }
            XCTAssertEqual(CameraModelRegistry.identify(name, in: without, aliases: [:]), .unknown,
                           "\(name) must not fall back to a shorter id")
        }
    }

    // MARK: - The RAW-conversion capability

    /// The Kitchen's allowlist, asserted as a set — the analogue of the slot-protocol list above,
    /// and missing until 2026-09-17 even though this is the gate that decides which bodies the app
    /// uploads a RAF to and writes `0xD185` on. No count in the name: this list moves with every
    /// promotion, where the slot-protocol one is closed.
    ///
    /// Two of these rest on a blob somebody actually read. The X-T50 was driven end to end here; the
    /// GFX100S's owner ran the profile harvest — 621 bytes / 28 params / IOPCode FF149502, resolving
    /// at base 0x1FD (zgrimz/fujifilm-ptp-reference `evidence/gfx100s-20260917-211657`). The rest are architecture
    /// inference: gen IV and gen V share the shape the X-T50 was verified on, and gen III rests on
    /// Fujifilm's own USB conversion support, the X-T20's conversion descriptor and published X100F
    /// conversions, in the X-H1's 601-byte shape.
    func testTheKitchenAllowlistIsExactlyTheseBodies() {
        let converts = Set(registry.models.filter(\.supportsRawConversion).map(\.id))
        XCTAssertEqual(converts, [
            "X-Pro2", "X-T2", "X100F", "X-T20", "X-E3", "X-H1",
            "X-T3", "X-T30",
            "X-T4", "X-Pro3", "X100V", "X-S10", "X-E4", "X-T30 II",
            "X-T30 III", "X-M5",
            "X-T5", "X-T50", "X-H2", "X-H2S", "X100VI", "X-S20", "X-E5",
            "GFX100S",
            CameraModelRegistry.demoModelID,
        ])
        XCTAssertEqual(Set(registry.models.filter { $0.sensorGeneration == .gfx && $0.supportsRawConversion }.map(\.id)),
                       ["GFX100S"],
                       "one GFX body produced a profile; the six without one are not promoted with it")
        let deadEnds = Set(registry.models.filter { !$0.supportsSlotProtocol && !$0.supportsRawConversion }.map(\.id))
        XCTAssertEqual(deadEnds, ["X-Pro1", "X-E1", "X-M1", "X100S", "X-T1", "X-E2", "X-E2S", "X-T10", "X70", "X100T"],
                       "only the X-Trans I and II bodies have neither slots nor a Kitchen; every other body without slots still develops")
    }

    /// The invariant that keeps the two axes from contradicting each other. A body the app writes
    /// recipes to must, by definition, have the protocol those writes travel over — an entry that
    /// claimed both would send `0xD18C` to a camera the registry says has no `0xD18C`.
    func testNoWritableModelLacksTheSlotProtocol() {
        for model in registry.models where model.allowsWrite {
            XCTAssertTrue(model.supportsSlotProtocol,
                          "\(model.id) is writable but claims no slot protocol")
        }
    }
}

/// The identification reaching `CameraConnector`: what a guessed or unknown body may do.
@MainActor
final class IdentificationGatingTests: XCTestCase {

    private func connect(_ productName: String) async -> (CameraServices, MockCameraTransport) {
        var faults = MockCameraFaults()
        faults.productName = productName
        return await connect(faults)
    }

    private func connect(_ faults: MockCameraFaults) async -> (CameraServices, MockCameraTransport) {
        var faults = faults
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        return (manager, transport)
    }

    private var recipe: RecipeSettings { RecipeSettings(filmSimulation: .classicChrome, dynamicRange: .dr400) }

    /// A guess reads behind its banner and, once its own slot read has proved the bank path, writes:
    /// the match decides what to decode with, the walk decides whether to write.
    func testAGuessedBodyWritesOnceItsSlotsHaveBeenRead() async throws {
        let (m, t) = await connect("FUJIFILM X-T50 TETHER")
        XCTAssertEqual(m.session.connected?.identification.confidence, "heuristic")
        XCTAssertEqual(m.session.model?.id, "X-T50", "the guess is usable for reading")
        XCTAssertEqual(m.slotReader.slots.count, 7, "reads went ahead")
        XCTAssertTrue(m.session.canPush, "and the walk, not the match, is what allows writing")
        XCTAssertNil(m.session.pushBlockReason)
        XCTAssertFalse(m.session.canConvert, "RAW conversion still needs a trusted match")
        guard case .granted(let permission) = m.session.connected?.writeAccess else {
            return XCTFail("expected a granted permission, got \(String(describing: m.session.connected?.writeAccess))")
        }
        XCTAssertEqual(permission.grounds, .walk)
        XCTAssertEqual(permission.stage, .unverified)

        let r = await m.slotWriter.push(settings: recipe, name: "Guess", toSlot: 1)
        XCTAssertEqual(r.outcome, .applied)
        try await t.writeProperty(FujiPTP.Prop.slotSelector, FujiEncoding.packU16(1))
        let held = try await t.readProperty(FujiPTP.PresetProp.filmSimulation.rawValue)
        XCTAssertEqual(held.flatMap(FujiEncoding.decodeInt16).flatMap { FujiEncoding.byteToFilmSim[$0] }, .classicChrome)
        XCTAssertEqual(m.reports.report?.camera.identification, "heuristic(X-T50)")
        XCTAssertTrue(m.reports.report?.notes.contains { $0.contains("heuristic") } ?? false)
    }

    func testAnExactBodyKeepsItsAllowlistVerdict() async {
        let (m, _) = await connect("FUJIFILM X-T50")
        XCTAssertEqual(m.session.connected?.identification.confidence, "exact")
        XCTAssertTrue(m.session.canPush)
        XCTAssertNil(m.session.pushBlockReason)
        XCTAssertEqual(m.reports.report?.camera.identification, "exact")
    }

    /// Exact, and writable since 2026-09-16 — the body that used to prove the read-only path now
    /// proves the identification one instead. REALA ACE reaching readable C1 is the assertion that carries
    /// it: this simulation exists on the X-T30 III's own entry and not on the X-T30 II the
    /// substring matcher used to resolve it to, so a slot holding it could only have come from the
    /// right entry.
    func testTheXT30IIIIsExactAndWritesItsOwnFilmSimulations() async {
        let (m, t) = await connect("FUJIFILM X-T30 III")
        XCTAssertEqual(m.session.model?.id, "X-T30 III")
        XCTAssertEqual(m.session.connected?.identification.confidence, "exact")
        XCTAssertTrue(m.session.canPush)
        XCTAssertNil(m.session.pushBlockReason)
        XCTAssertEqual(m.session.connected?.capabilityBadge.text, "Read & Write · not yet tested",
                       "writable on inference still tells the user nobody has reported a write")
        var wanted = recipe
        wanted.filmSimulation = .realaAce
        XCTAssertTrue(RecipeCompatibility.analyze(wanted, for: m.session.model!).isEmpty, "REALA ACE raises no warning on a body that ships it")
        let r = await m.slotWriter.push(settings: wanted, name: "III", toSlot: 1)
        XCTAssertEqual(r.outcome, .applied)
        try? await t.writeProperty(FujiPTP.Prop.slotSelector, FujiEncoding.packU16(1))
        let held = (try? await t.readProperty(FujiPTP.PresetProp.filmSimulation.rawValue))
            .flatMap(FujiEncoding.decodeInt16)
            .flatMap { FujiEncoding.byteToFilmSim[$0] }
        XCTAssertEqual(held, .realaAce, "the slot holds the simulation only this body's entry allows")
    }

    /// The X-M5, end to end by its product string: exact, writable on its owner's report, a dial
    /// body, and four banks where the walk assumes seven — landing exactly on the manual's count,
    /// which the report files as expected rather than as a finding. `PushAuditTests` proves the
    /// three walk outcomes on a synthetic X-S20; this pins the body itself, the way a tester's
    /// camera presents.
    func testTheXM5IsExactWritableAndFourBanksDeep() async {
        let (m, _) = await connect(.xM5)
        XCTAssertEqual(m.session.model?.id, "X-M5")
        XCTAssertEqual(m.session.connected?.identification.confidence, "exact")
        XCTAssertTrue(m.session.canPush)
        XCTAssertNil(m.session.pushBlockReason)
        XCTAssertEqual(m.session.connected?.capabilityBadge.text, "Read & Write",
                       "an owner's reported write earns the plain seal")
        XCTAssertEqual(m.session.model?.hasFilmSimulationDial, true, "the write pass inserts the dial-at-C step")
        XCTAssertEqual(m.session.model?.documentedSlotCount, 4)
        XCTAssertEqual(m.slotReader.slots.count, 4)
        XCTAssertEqual(m.reports.report?.slots.probedSlotCount, 4)
        let notes = m.reports.report?.notes ?? []
        XCTAssertTrue(notes.contains { $0.contains("expected") && $0.contains("4 banks") },
                      "the refusal at C5 is the manual confirmed, not a finding: \(notes)")
        XCTAssertFalse(notes.contains { $0.contains("Fewer than documented") })
        XCTAssertFalse(notes.contains { $0.contains("exposes more than the menu") })
    }
}
