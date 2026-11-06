import XCTest
@testable import FujiCookbook

/// The guided Camera Test's rules, exercised without a camera.
///
/// Everything asserted here decides what a tester is asked to do, and several of the branches exist
/// for bodies nobody here owns — so the only way they are ever run before a tester runs them is
/// here.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference: `docs/01-transport.md#camera-setup`,
/// `docs/03-encodings.md#0xd195-grain-effect`, `docs/04-custom-slots.md#reading-a-bank`,
/// `docs/04-custom-slots.md#why-a-write-is-refused`, `docs/04-custom-slots.md#iso-gating`, and
/// `docs/06-conversion-profile.md#lengths-seen`.
@MainActor
final class GuidedTestFlowTests: XCTestCase {

    private var registry: CameraModelRegistry { .shared }

    private func facts(_ modelID: String, connected: Bool = true, occupied: Bool = true,
                       guessed: Bool = false) -> CameraFacts {
        let model = registry.model(withID: modelID)
        return CameraFacts(
            isConnected: connected,
            isRecognized: model != nil,
            hasSlotProtocol: model?.supportsSlotProtocol ?? false,
            canWrite: !guessed && (model?.allowsWrite ?? false),
            canConvert: !guessed && (model?.supportsRawConversion ?? false),
            hasOccupiedSlots: occupied,
            hasFilmSimulationDial: model?.hasFilmSimulationDial ?? false,
            transport: "usb",
            productName: model?.displayName,
            modelID: model?.id,
            serialHash: "abc123")
    }

    private var unknownFacts: CameraFacts {
        CameraFacts(isConnected: true, isRecognized: false, hasSlotProtocol: false,
                    transport: "usb", productName: "FUJIFILM X-T99", identification: "unknown")
    }

    /// A body no entry matches that named itself over `GetDeviceInfo` and whose slot read granted
    /// it (`MockCameraFaults.unlistedBody`), as `GuidedTestRunner.facts` reports it: no model id,
    /// because the provisional model's placeholder id is stored nowhere.
    private var unlistedFacts: CameraFacts {
        CameraFacts(isConnected: true, isRecognized: true, hasSlotProtocol: true, canWrite: true,
                    hasOccupiedSlots: true, transport: "usb", productName: "FUJIFILM X-T99",
                    identification: "unlisted", verification: "inferred", firmwareVersion: "1.00",
                    serialHash: "unlisted-body", badge: "Read & Write · not yet tested")
    }

    /// The same body when its selector answered `0x200A`: named, with no slots to read and no write.
    private var unlistedRefusedFacts: CameraFacts {
        var facts = unlistedFacts
        facts.isRecognized = false
        facts.hasSlotProtocol = false
        facts.canWrite = false
        facts.hasOccupiedSlots = false
        facts.badge = "Read-only · no USB slots"
        return facts
    }

    /// Walk the main line from `start`, following each step's own answer, and return the path.
    private func walk(from start: GuidedTestStep, _ facts: CameraFacts) -> [GuidedTestStep] {
        var path = [start]
        var step = start
        while step != .review && step != .send && path.count < 30 {
            step = GuidedTestFlow.next(after: step, facts: facts)
            path.append(step)
        }
        return path
    }

    // MARK: Wave 1 routing

    /// The full read pass on a body the app writes to and develops on.
    func testAWritableBodyWalksEveryStep() {
        let path = walk(from: .connect, facts("X-T50"))
        XCTAssertEqual(path, [.connect, .confirmIdentity, .readSlots, .compareSlots,
                              .propertyReport, .grainProbe, .develop, .review])
    }

    /// The grain probe writes real values, and `probeWriteValues` refuses a body the app doesn't
    /// write to. The step is still *reached* — it records `notWritable`, which is a fact about the
    /// body — but it must never ask for consent to do something that cannot happen.
    func testAReadOnlyBodyIsNotAskedToConsentToAWriteItCannotMake() {
        // The X-T30 III until 2026-09-16, when it was promoted; a GFX body that has had no report
        // is what still sits at this level.
        let readOnly = facts("GFX100 II")
        XCTAssertFalse(readOnly.canWrite, "read-only pending a tester's report")
        XCTAssertEqual(walk(from: .connect, readOnly),
                       [.connect, .confirmIdentity, .readSlots, .compareSlots,
                        .propertyReport, .grainProbe, .develop, .review])

        let state = GuidedTestFlow.grainProbeState(facts: readOnly)
        XCTAssertEqual(state?.state, .notWritable)
        XCTAssertNil(GuidedTestFlow.grainProbeState(facts: facts("X-T50")),
                     "a writable body is asked, not decided for")
    }

    /// An unrecognized body has no slots to read and none to compare. Its read-only sweep is the
    /// whole of what it can contribute, and the flow must go straight there rather than walking a
    /// tester through three screens about slots that were never read.
    func testAnUnrecognizedBodyGoesStraightToTheSweep() {
        XCTAssertEqual(walk(from: .connect, unknownFacts),
                       [.connect, .propertyReport, .grainProbe, .develop, .review])
    }

    /// An unlisted body its slot read granted has slots to read, compare and write, and is walked
    /// like a listed one; the same body refused by its read is sent to the sweep like a body
    /// nothing names. Writing is decided at connect, so it never reaches the read steps undecided.
    func testAnUnlistedBodyIsWalkedWhereItsSlotReadGrantedItAndSweptWhereItRefused() {
        XCTAssertEqual(walk(from: .connect, unlistedFacts),
                       [.connect, .confirmIdentity, .readSlots, .compareSlots,
                        .propertyReport, .grainProbe, .develop, .review])
        XCTAssertNil(GuidedTestFlow.grainProbeState(facts: unlistedFacts), "the grain check is offered")
        XCTAssertEqual(walk(from: .connect, unlistedRefusedFacts),
                       [.connect, .propertyReport, .grainProbe, .develop, .review])
        XCTAssertEqual(GuidedTestFlow.grainProbeState(facts: unlistedRefusedFacts)?.state, .notWritable)

        let session = GuidedTestSession.beginContinuous(step: .connect)
        XCTAssertEqual(GuidedTestFlow.next(after: .connect, session: session, facts: unlistedFacts), .confirmIdentity)
        XCTAssertEqual(GuidedTestFlow.next(after: .connect, session: session, facts: unlistedRefusedFacts), .propertyReport)
        XCTAssertEqual(GuidedTestFlow.next(after: .connect, session: session, facts: unknownFacts), .propertyReport)
    }

    /// The bodies with no working direct bank path. In a wave-1 session they take the same path as
    /// an unrecognized body, past the identity check as well as the slot steps. A continuous session
    /// still asks them to confirm the model (`next(after:session:facts:)`).
    func testABodyWithNoSlotProtocolSkipsTheSlotStepsAndTheIdentityCheck() {
        let xt20 = facts("X-T20")
        XCTAssertFalse(xt20.hasSlotProtocol)
        XCTAssertEqual(walk(from: .connect, xt20),
                       [.connect, .propertyReport, .grainProbe, .develop, .review])

        // Not every body without slots has RAW conversion — the X-Trans I and II bodies have
        // neither — so a body without it is told apart by `canConvert`, not by guessing.
        XCTAssertTrue(facts("X-T3").canConvert)
        XCTAssertTrue(xt20.canConvert)
        XCTAssertNil(GuidedTestFlow.developState(facts: xt20))
        var noKitchen = xt20
        noKitchen.canConvert = false
        XCTAssertEqual(GuidedTestFlow.developState(facts: noKitchen)?.state, .notWritable)
    }

    /// A camera with seven empty slots has nothing to compare against its own menu.
    func testNoOccupiedSlotsSkipsTheComparison() {
        XCTAssertEqual(GuidedTestFlow.next(after: .readSlots, facts: facts("X-T50", occupied: false)),
                       .propertyReport)
        XCTAssertEqual(GuidedTestFlow.next(after: .readSlots, facts: facts("X-T50")), .compareSlots)
    }

    /// The most common failure on a new body. A connect that fails is not the end of the test — it
    /// is the branch that asks the five questions `connectionFailures[]` cannot answer for itself.
    func testAFailedConnectRoutesToTheQuestionsAndThenToReview() {
        let step = GuidedTestFlow.stepAfterConnect(status: .failed("No camera found."),
                                                   facts: CameraFacts())
        XCTAssertEqual(step, .noCamera)
        XCTAssertEqual(GuidedTestFlow.next(after: .noCamera, facts: CameraFacts()), .review)
    }

    func testAConnectThatSucceededGoesOnWithTheTest() {
        XCTAssertEqual(GuidedTestFlow.stepAfterConnect(status: .connected, facts: facts("X-T50")),
                       .confirmIdentity)
        XCTAssertEqual(GuidedTestFlow.stepAfterConnect(status: .disconnected, facts: CameraFacts()),
                       .connect, "nothing happened yet — stay put")
    }

    /// Why the connect step has to ask `stepAfterConnect` rather than advance the ordinary way.
    ///
    /// The generic rule cannot see a failure — to it, a camera that never answered is just an
    /// unrecognized one, and unrecognized bodies go and run the property sweep. For a while the
    /// connect step set `session.step = .noCamera` and then advanced generically, which overwrote
    /// it: a tester whose camera would not connect was sent to "Ask the camera what it accepts".
    func testTheGenericRuleCannotSeeAFailedConnect() {
        let nothing = CameraFacts()
        XCTAssertEqual(GuidedTestFlow.next(after: .connect, facts: nothing), .propertyReport,
                       "the generic rule sends a body it cannot identify to the sweep")
        XCTAssertEqual(GuidedTestFlow.stepAfterConnect(status: .failed("No camera found."),
                                                       facts: nothing), .noCamera,
                       "so the connect step must ask this one instead")
    }

    /// "Push another" goes backwards. Every other step in the write pass moves forward, so the
    /// generic rule is no use to it — `next(after: .moreTrials)` is where the flow ends up when
    /// the tester is *done*, which is the opposite answer.
    func testAnotherPushIsNotWhereTheGenericRuleGoes() {
        XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, facts: facts("X-T50")), .restoreOffer)
    }

    // MARK: Adopting a camera

    /// The flow asks the tester to unplug twice by name, and `adopt` runs at every step boundary.
    /// An unconditional copy erased the body the session was about at the moment they complied.
    func testUnpluggingDoesNotEraseTheBodyTheSessionIsAbout() {
        var session = GuidedTestSession.begin(wave: 1, step: .intro)
        session.adopt(camera: facts("X-T50"))
        XCTAssertEqual(session.cameraProductName, "FUJIFILM X-T50")
        XCTAssertEqual(session.transport, "usb")

        session.adopt(camera: CameraFacts())
        XCTAssertEqual(session.cameraProductName, "FUJIFILM X-T50",
                       "the cable came out; the camera did not change")
        XCTAssertEqual(session.transport, "usb")
        XCTAssertEqual(session.serialHash, "abc123")
    }

    /// And a genuinely different body still replaces it, which is what the field is for.
    func testADifferentBodyIsStillAdopted() {
        var session = GuidedTestSession.begin(wave: 1, step: .intro)
        session.adopt(camera: facts("X-T50"))
        session.adopt(camera: facts("X-T5"))
        XCTAssertEqual(session.cameraProductName, "FUJIFILM X-T5")
        XCTAssertFalse(GuidedTestFlow.describesSameBody(stored: session, facts: facts("X-T50")))
    }

    // MARK: Position

    /// The tester's place in the wave, which is the only thing on a step screen that says how much
    /// is left — the checklist that would otherwise say so is behind a Back chevron.
    func testPositionCountsTheMainLine() {
        XCTAssertEqual(GuidedTestFlow.position(of: .intro, wave: 1)?.index, 1)
        XCTAssertEqual(GuidedTestFlow.position(of: .send, wave: 1)?.index, 10)
        XCTAssertEqual(GuidedTestFlow.position(of: .send, wave: 1)?.total, 10)
        XCTAssertEqual(GuidedTestFlow.positionLabel(of: .compareSlots, wave: 1), "Part One · 5 of 10")
        XCTAssertEqual(GuidedTestFlow.positionLabel(of: .writeIntro, wave: 2), "Part Two · 1 of 13")
    }

    /// A continuous session counts stages, not steps, and the Camera tab's resume row reads the same
    /// label as the step screen's bar.
    func testAContinuousSessionCountsStages() {
        let session = GuidedTestSession.beginContinuous()
        XCTAssertEqual(GuidedTestFlow.positionLabel(of: .intro, in: session), "Prepare · 1 of 6")
        XCTAssertEqual(GuidedTestFlow.positionLabel(of: .compareSlots, in: session), "Read · 2 of 6")
        XCTAssertEqual(GuidedTestFlow.positionLabel(of: .review, in: session), "Finish · 6 of 6")
    }

    /// `.noCamera` is a branch, not a stage. Numbering it would claim the wave has eleven steps
    /// for the testers who reach it and ten for everyone else.
    func testABranchStepHasNoNumber() {
        XCTAssertNil(GuidedTestFlow.position(of: .noCamera, wave: 1))
        XCTAssertEqual(GuidedTestFlow.positionLabel(of: .noCamera, wave: 1), "Part One")
    }

    // MARK: Wave 2 routing

    func testTheWritePassAsksAboutTheDialOnlyWhereThereIsOne() {
        XCTAssertTrue(facts("X-T50").hasFilmSimulationDial)
        XCTAssertEqual(GuidedTestFlow.next(after: .backup, facts: facts("X-T50")), .dialCheck)
        XCTAssertFalse(facts("X-T5").hasFilmSimulationDial)
        XCTAssertEqual(GuidedTestFlow.next(after: .backup, facts: facts("X-T5")), .chooseRecipe)
    }

    func testTheWritePassWalksPushThenPowerCycleThenTheChecks() {
        XCTAssertEqual(walk(from: .writeIntro, facts("X-T5")),
                       [.writeIntro, .backup, .chooseRecipe, .chooseSlot, .push,
                        .powerCycle, .recheckSlot, .photoCheck, .moreTrials, .restoreOffer, .review])
    }

    /// The question a GFX owner is actually asking: does the Camera Test reach writing on their
    /// camera. For the X-Processor 4 group it does; for the other four the same clean read goes
    /// straight to Develop. The GFX100 and GFX 50S II crossed that line on 2026-09-16 with the GFX100S.
    func testTheWritingChecksReachTheXProcessor4GFXBodiesAndNoOther() {
        func readAndMatched(_ modelID: String) -> GuidedTestSession {
            var session = GuidedTestSession.beginContinuous(step: .compareSlots)
            session.adopt(camera: facts(modelID))
            session.identification = "exact"
            session.identity = .init(confirmed: true)
            session.propertyReport = .init(state: .ran, count: 24)
            session.slotComparisons = [.init(slot: 1, confirmedMatching: true,
                                             checkedAt: CameraCompatibilityReport.timestamp())]
            return session
        }

        for id in ["GFX100S", "GFX100", "GFX50S II"] {
            let body = facts(id)
            XCTAssertTrue(body.canWrite, "\(id): the registry promoted this body")
            XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: readAndMatched(id), facts: body),
                           .writeIntro, "\(id): a clean read must lead to the writing checks")
        }

        for id in ["GFX50S", "GFX50R", "GFX100 II", "GFX100S II"] {
            let other = facts(id)
            XCTAssertFalse(other.canWrite, "\(id) is read-only")
            XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: readAndMatched(id), facts: other),
                           .develop, "\(id) is read-only — a clean read must skip writing, not the test")
        }
    }

    /// Both of this body's write-adjacent branches are open now, and they arrived separately. The
    /// grain probe followed `canWrite` (2026-09-16). The develop step followed the profile harvest
    /// that answered the Kitchen question on 2026-09-17 — 621 bytes / 28 params, layout resolved at
    /// 0x1FD. `developState` returning nil is the whole difference: the step stops explaining itself
    /// and becomes a real develop, and the harvest it used to offer moves to the siblings.
    func testTheGFX100SGetsTheGrainProbeAndNowTheKitchenToo() {
        let gfx100S = facts("GFX100S")
        XCTAssertNil(GuidedTestFlow.grainProbeState(facts: gfx100S),
                     "nil means the probe is offered rather than explained away")
        XCTAssertNil(GuidedTestFlow.developState(facts: gfx100S),
                     "and the develop step is a develop now, not an explanation")
        XCTAssertFalse(GuidedTestFlow.offersProfileHarvest(facts: gfx100S),
                       "a develop is a harvest with more attached, so the harvest is not offered here")

        // The siblings that have produced nothing are where the harvest lives now — which is also
        // what keeps a writable body in the registry for that step to be demonstrated on.
        var sibling = facts("GFX100")
        XCTAssertEqual(GuidedTestFlow.developState(facts: sibling)?.state, .notWritable)
        sibling.canHarvestProfile = true   // the helper leaves this false; `GuidedTestRunner.facts` sets it
        XCTAssertTrue(GuidedTestFlow.offersProfileHarvest(facts: sibling))
    }

    // MARK: Resuming

    func testResumeOffersAStoredSessionForTheSameBody() {
        let xt5 = facts("X-T5")
        var session = GuidedTestSession.begin(wave: 1, step: .compareSlots)
        session.adopt(camera: xt5)

        XCTAssertEqual(GuidedTestFlow.resumeDecision(stored: session, facts: xt5),
                       .offerResume(.compareSlots))
        XCTAssertEqual(GuidedTestFlow.resumeDecision(stored: nil, facts: xt5), .fresh)

        session.outcome = .completed
        XCTAssertEqual(GuidedTestFlow.resumeDecision(stored: session, facts: xt5), .fresh,
                       "a finished test is not something to resume")
    }

    /// The tester unplugged an X-T5 mid-test and plugged in an X-T50. Filing one camera's answers
    /// under the other's name is the one mistake this record cannot survive.
    func testResumeRefusesADifferentBody() {
        var session = GuidedTestSession.begin(wave: 1, step: .compareSlots)
        session.adopt(camera: facts("X-T5"))
        XCTAssertEqual(GuidedTestFlow.resumeDecision(stored: session, facts: facts("X-T50")),
                       .differentBody(stored: "FUJIFILM X-T5"))
    }

    /// The power-cycle step means a session is routinely resumed with nothing plugged in. Refusing
    /// there would strand the tester at the exact step that asks them to unplug.
    func testResumeIsOfferedWhenNoCameraIsConnected() {
        var session = GuidedTestSession.begin(wave: 2, step: .powerCycle)
        session.adopt(camera: facts("X-T5"))
        XCTAssertEqual(GuidedTestFlow.resumeDecision(stored: session, facts: CameraFacts()),
                       .offerResume(.powerCycle))
    }

    /// Two bodies of the same model. The serial hash is what separates them, and when both sides
    /// carry one it has to be believed.
    func testTwoBodiesOfOneModelAreNotTheSameCamera() {
        var session = GuidedTestSession.begin(wave: 1, step: .readSlots)
        session.adopt(camera: facts("X-T5"))
        var second = facts("X-T5")
        second.serialHash = "a-different-body"
        XCTAssertFalse(GuidedTestFlow.describesSameBody(stored: session, facts: second))

        // A body that refuses GetDeviceInfo has no hash on either side; the name is all there is.
        session.serialHash = nil
        second.serialHash = nil
        XCTAssertTrue(GuidedTestFlow.describesSameBody(stored: session, facts: second))
    }

    // MARK: Verdicts

    /// The verdict is derived from the rows, never typed. A summary that could disagree with the
    /// answers under it would be the one line in this record nobody could check.
    func testTheVerdictFollowsTheRows() {
        var comparison = GuidedTestSession.SlotComparison(
            slot: 2,
            rows: [.init(field: "grain", label: "Grain Effect", appShowed: "Weak, Large"),
                   .init(field: "clarity", label: "Clarity", appShowed: "+2")])
        XCTAssertEqual(comparison.verdict, "notChecked")

        comparison.confirmedMatching = true
        XCTAssertEqual(comparison.verdict, "matches")

        comparison.rows[0].differs = true
        comparison.rows[0].cameraShows = "Weak, Small"
        XCTAssertEqual(comparison.verdict, "differs",
                       "one flagged setting outranks a tester's earlier 'everything matches'")
    }

    /// The comparison screen shows what the app displayed, and says which fields it admits it
    /// couldn't read — those are the ones only the camera's own menu can settle.
    func testTheComparisonCarriesTheRowsAndTheAdmittedGaps() {
        let model = registry.model(withID: "X-T5")!
        let slot = CameraSlot(index: 3, label: "C3", name: "Sunny 16", isOccupied: true,
                              settings: RecipeSettings(filmSimulation: .classicChrome,
                                                       dynamicRange: .dr200, highlightTone: 1),
                              rawProperties: [:],
                              unsupportedFields: ["White Balance": .string("0x8009")])
        let comparison = GuidedTestFlow.comparison(for: slot, model: model)

        XCTAssertEqual(comparison.slot, 3)
        XCTAssertEqual(comparison.name, "Sunny 16")
        XCTAssertEqual(comparison.filmSimulation, "Classic Chrome")
        XCTAssertEqual(comparison.fieldsAppCouldNotRead, ["White Balance"])
        XCTAssertEqual(comparison.rows.map(\.field), ["filmSimulation", "dynamicRange", "highlightTone"])
        XCTAssertEqual(comparison.rows.first?.appShowed, "Classic Chrome")
    }

    // MARK: Seeding the comparison before the cable comes out

    /// The compare step asks the tester to unplug — a camera in USB RAW Conv./Backup Restore has
    /// given its display to the host, so its IQ menu is only reachable with the cable out. And
    /// `disconnect()` empties `camera.slotReader.slots`. So every occupied slot has to be snapshotted while
    /// the camera is still attached, or the screen is empty exactly when it is needed.
    func testEveryOccupiedSlotIsSnapshottedBeforeTheCableComesOut() {
        let model = registry.model(withID: "X-T5")!
        let live = [occupiedSlot(2, name: "ACROS Street"),
                    CameraSlot(index: 3, label: "C3", name: nil, isOccupied: false, settings: nil,
                               rawProperties: [:], unsupportedFields: [:]),
                    occupiedSlot(5, name: "Sunny 16")]

        let seeded = GuidedTestFlow.seedComparisons(into: [], slots: live, model: model)

        XCTAssertEqual(seeded.map(\.slot), [2, 5], "an empty slot has nothing to compare")
        XCTAssertEqual(seeded.first?.name, "ACROS Street")
        XCTAssertFalse(seeded.first?.rows.isEmpty ?? true, "the rows are the whole point of the snapshot")
    }

    /// The tester unplugs, compares C2, plugs back in and comes back. Re-seeding must not rebuild
    /// their answers from a fresh read — the snapshot has to keep meaning what it meant when they
    /// were looking at it.
    func testSeedingLeavesAnsweredComparisonsAlone() {
        let model = registry.model(withID: "X-T5")!
        var answered = GuidedTestFlow.comparison(for: occupiedSlot(2, name: "ACROS Street"), model: model)
        answered.rows[0].differs = true
        answered.rows[0].cameraShows = "Weak, Small"
        answered.checkedAt = CameraCompatibilityReport.timestamp()

        let seeded = GuidedTestFlow.seedComparisons(into: [answered],
                                                    slots: [occupiedSlot(2, name: "ACROS Street"),
                                                            occupiedSlot(5, name: "Sunny 16")],
                                                    model: model)

        XCTAssertEqual(seeded.count, 2)
        XCTAssertEqual(seeded.first, answered, "the tester's answers survived a re-seed")
        XCTAssertEqual(seeded.last?.verdict, "notChecked")
    }

    /// Re-entering the step with the camera unplugged reads `camera.slotReader.slots` as empty. That must be a
    /// no-op, not a wipe of everything recorded so far.
    func testSeedingWithNoCameraAttachedKeepsWhatIsThere() {
        let model = registry.model(withID: "X-T5")!
        let existing = GuidedTestFlow.seedComparisons(into: [],
                                                      slots: [occupiedSlot(2, name: "ACROS Street")],
                                                      model: model)

        XCTAssertEqual(GuidedTestFlow.seedComparisons(into: existing, slots: [], model: model),
                       existing)
    }

    /// The screen renders from the snapshot, so its title can't come from the live slot.
    func testTheSnapshotCanNameItselfWithNoCameraAttached() {
        let model = registry.model(withID: "X-T5")!
        let named = GuidedTestFlow.comparison(for: occupiedSlot(2, name: "ACROS Street"), model: model)
        XCTAssertEqual(named.label, "C2")
        XCTAssertEqual(named.displayName, "ACROS Street")

        let unnamed = GuidedTestFlow.comparison(for: occupiedSlot(4, name: nil), model: model)
        XCTAssertEqual(unnamed.displayName, "Classic Chrome", "falls back to the film simulation")
    }

    /// Seven slots that are all *present and unoccupied* — a camera nobody has programmed — not the
    /// same thing as no slots read at all. The compare step's list comes from this, so an empty
    /// result is what tells it to say so rather than draw an empty card.
    func testAnUnprogrammedCameraSeedsNoComparisons() {
        let model = registry.model(withID: "X-T5")!
        let unprogrammed = (1...7).map {
            CameraSlot(index: $0, label: "C\($0)", name: nil, isOccupied: false, settings: nil,
                       rawProperties: [:], unsupportedFields: [:])
        }
        XCTAssertTrue(GuidedTestFlow.seedComparisons(into: [], slots: unprogrammed, model: model).isEmpty)
    }

    private func occupiedSlot(_ index: Int, name: String?) -> CameraSlot {
        CameraSlot(index: index, label: "C\(index)", name: name, isOccupied: true,
                   settings: RecipeSettings(filmSimulation: .classicChrome,
                                            dynamicRange: .dr200, highlightTone: 1),
                   rawProperties: [:], unsupportedFields: [:])
    }

    // MARK: Persistence after a power cycle

    private func trial(wrote: [String: String]) -> GuidedTestSession.PushTrial {
        GuidedTestSession.PushTrial(recipe: "colour", recipeName: "CT Colour", slot: 3, wrote: wrote)
    }

    private func slot(_ props: [UInt16: Data], name: String? = nil) -> CameraSlot {
        CameraSlot(index: 3, label: "C3", name: name, isOccupied: true, settings: nil,
                   rawProperties: props, unsupportedFields: [:])
    }

    func testARecipeStillOnTheCameraReadsAsPersisted() {
        let sim = FujiPTP.PresetProp.filmSimulation.rawValue
        let result = GuidedTestFlow.persistence(
            trial: trial(wrote: [PTPHex.code(sim): "0B00"]),
            slot: slot([sim: FujiEncoding.packU16(0x0B)]), nameApplied: nil)
        XCTAssertTrue(result.persisted)
        XCTAssertTrue(result.differences.isEmpty)
    }

    /// The failure this whole step exists for: the push reported success, the read-back agreed, and
    /// the value is gone after the camera was switched off and on. Nothing else catches it.
    func testARecipeThatDidNotSurviveNamesTheSettingThatWentMissing() {
        let sim = FujiPTP.PresetProp.filmSimulation.rawValue
        let result = GuidedTestFlow.persistence(
            trial: trial(wrote: [PTPHex.code(sim): "0B00"]),
            slot: slot([sim: FujiEncoding.packU16(0x01)]), nameApplied: nil)

        XCTAssertFalse(result.persisted)
        XCTAssertEqual(result.differences.count, 1)
        XCTAssertEqual(result.differences.first?.field, "Film Simulation")
        XCTAssertEqual(result.differences.first?.wrote, "0B00")
        XCTAssertEqual(result.differences.first?.holds, "0100")
    }

    /// Grain is compared by decoded meaning, exactly as the push's own verification does: the X-T50
    /// accepts a write of 1 for Off and then reports 6 or 7. A byte comparison here would tell every
    /// tester who pushed grain Off that their recipe had been lost.
    func testGrainOffIsNotReportedAsLostBecauseTheCameraRenamedIt() {
        let grain = FujiPTP.PresetProp.grain.rawValue
        for readBack in [6, 7] {
            let result = GuidedTestFlow.persistence(
                trial: trial(wrote: [PTPHex.code(grain): "0100"]),
                slot: slot([grain: FujiEncoding.packU16(readBack)]), nameApplied: nil)
            XCTAssertTrue(result.persisted, "a read-side Off of \(readBack) is still Off")
        }
        // And a grain that genuinely changed is still caught.
        let result = GuidedTestFlow.persistence(
            trial: trial(wrote: [PTPHex.code(grain): "0100"]),
            slot: slot([grain: FujiEncoding.packU16(5)]), nameApplied: nil)
        XCTAssertFalse(result.persisted)
    }

    /// Housekeeping properties are passed through rather than authored, and some bodies refuse them
    /// routinely. One of those changing says nothing about whether the recipe survived.
    func testAHousekeepingPropertyDoesNotDecideWhetherTheRecipeSurvived() {
        let imageSize = FujiPTP.PresetProp.imageSize.rawValue
        let result = GuidedTestFlow.persistence(
            trial: trial(wrote: [PTPHex.code(imageSize): "0100"]),
            slot: slot([imageSize: FujiEncoding.packU16(2)]), nameApplied: nil)
        XCTAssertFalse(result.persisted, "housekeeping alone is no accepted recipe evidence")
        XCTAssertEqual(result.evidenceState, .notTested)
    }

    func testAMissingSlotAndAChangedNameAreBothReported() {
        let sim = FujiPTP.PresetProp.filmSimulation.rawValue
        let gone = GuidedTestFlow.persistence(trial: trial(wrote: [PTPHex.code(sim): "0B00"]),
                                              slot: nil, nameApplied: "CT Colour")
        XCTAssertFalse(gone.persisted, "the slot itself is not there to check")

        let renamed = GuidedTestFlow.persistence(
            trial: trial(wrote: [:]),
            slot: slot([:], name: "Sunny 16"), nameApplied: "CT Colour")
        XCTAssertEqual(renamed.nameHolds, false)
        XCTAssertFalse(renamed.persisted)
        XCTAssertEqual(renamed.evidenceState, .issueFound)
    }

    func testNameFailureCannotHideBehindMatchingRecipeFields() {
        let sim = FujiPTP.PresetProp.filmSimulation.rawValue
        let result = GuidedTestFlow.persistence(
            trial: trial(wrote: [PTPHex.code(sim): "0B00"]),
            slot: slot([sim: FujiEncoding.packU16(0x0B)], name: "Original"), nameApplied: "CT Priority")
        XCTAssertEqual(result.settingsState, .passed)
        XCTAssertEqual(result.nameState, .issueFound)
        XCTAssertFalse(result.persisted)
    }

    func testFailedRefreshAndMissingRestartAreNotPersistenceEvidence() {
        let sim = FujiPTP.PresetProp.filmSimulation.rawValue
        let write = trial(wrote: [PTPHex.code(sim): "0B00"])
        let cached = slot([sim: FujiEncoding.packU16(0x0B)])
        let failed = GuidedTestFlow.persistence(trial: write, slot: cached, nameApplied: nil,
                                                freshReadSucceeded: false)
        XCTAssertFalse(failed.persisted)
        XCTAssertEqual(failed.evidenceState, .couldNotVerify)
        let noRestart = GuidedTestFlow.persistence(trial: write, slot: cached, nameApplied: nil,
                                                   restartConfirmed: false)
        XCTAssertFalse(noRestart.persisted)
        XCTAssertEqual(noRestart.evidenceState, .notTested)
        let nothing = GuidedTestFlow.persistence(trial: trial(wrote: [:]), slot: cached, nameApplied: nil)
        XCTAssertFalse(nothing.persisted)
        XCTAssertEqual(nothing.evidenceState, .notTested)
    }

    func testContinuousFlowCompletesPriorityBeforeOfferingExtraTrials() {
        var session = GuidedTestSession.beginContinuous()
        session.writePass = .init(trials: [.init(recipe: "priority", recipeName: "CT Priority", slot: 3,
                                               wrote: ["0xD192": "1500"])],
                                  currentTrial: 0)
        XCTAssertEqual(GuidedTestFlow.next(after: .push, session: session, facts: facts("X-M5")), .powerCycle)
        session.writePass?.trials.append(.init(recipe: "colour", recipeName: "CT Colour", slot: 3,
                                             wrote: ["0xD192": "0B00"]))
        session.writePass?.currentTrial = 1
        XCTAssertEqual(GuidedTestFlow.next(after: .push, session: session, facts: facts("X-M5")), .moreTrials)
        session.plan?.optionalChecks.insert(.extraRestarts)
        XCTAssertEqual(GuidedTestFlow.next(after: .push, session: session, facts: facts("X-M5")), .powerCycle)
        XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, session: session, facts: facts("X-M5")), .develop)
        XCTAssertEqual(GuidedTestFlow.next(after: .develop, session: session, facts: facts("X-M5")), .restoreOffer)
    }

    private func additionalWriteSession(_ extras: Set<GuidedTestSession.OptionalCheck> = [.colour, .mono, .kelvin]) -> GuidedTestSession {
        var session = GuidedTestSession.beginContinuous(step: .moreTrials)
        session.identifiedModelID = "X-T50"
        session.identification = "exact"
        session.selectedWriteSlot = 2
        session.plan?.optionalChecks = extras
        session.writePass = .init()
        return session
    }

    private func recordWriteAttempt(_ recipeID: String, in session: inout GuidedTestSession,
                                    outcome: SlotOutcome = .applied) {
        let recipe = GuidedTestRecipes.recipe(id: recipeID, for: registry.model(withID: "X-T50")!)!
        session.writePass?.trials.append(.init(recipe: recipe.id, recipeName: recipe.name, slot: 2,
            pushedAt: Date(timeIntervalSince1970: 1_000), outcome: outcome))
        let index = (session.writePass?.trials.count ?? 1) - 1
        session.writePass?.currentTrial = index
    }

    func testSelectedWriteChecksRunPriorityColourMonoKelvinWhileUnplugged() {
        var session = additionalWriteSession()
        let unplugged = CameraFacts()
        XCTAssertEqual(GuidedTestFlow.writeRecipes(session: session).map(\.id), ["priority", "colour", "mono", "kelvin"])
        XCTAssertEqual(GuidedTestFlow.suggestedWriteRecipe(session: session)?.id, "priority")

        recordWriteAttempt("priority", in: &session)
        for (index, recipeID) in ["colour", "mono", "kelvin"].enumerated() {
            let expected = Array(["colour", "mono", "kelvin"].dropFirst(index))
            XCTAssertEqual(GuidedTestFlow.remainingWriteRecipes(session: session).map(\.id), expected)
            XCTAssertEqual(GuidedTestFlow.suggestedWriteRecipe(session: session)?.id, recipeID)
            XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, session: session, facts: unplugged), .chooseRecipe,
                           "selected checks must remain reachable after the unplugged photo check")
            recordWriteAttempt(recipeID, in: &session)
        }
        XCTAssertTrue(GuidedTestFlow.remainingWriteRecipes(session: session).isEmpty)
        XCTAssertNil(GuidedTestFlow.suggestedWriteRecipe(session: session))
        XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, session: session, facts: unplugged), .develop)
        XCTAssertEqual(session.writePass?.trials.map(\.recipe), ["priority", "colour", "mono", "kelvin"])
    }

    func testNoSelectedExtraWritesContinuesToDevelop() {
        var session = additionalWriteSession([])
        recordWriteAttempt("priority", in: &session)
        XCTAssertEqual(GuidedTestFlow.writeRecipes(session: session).map(\.id), ["priority"])
        XCTAssertTrue(GuidedTestFlow.remainingWriteRecipes(session: session).isEmpty)
        XCTAssertNil(GuidedTestFlow.suggestedWriteRecipe(session: session))
        XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, session: session, facts: CameraFacts()), .develop)
    }

    func testRepeatedAndUnsuccessfulAttemptsDoNotLoopAnExtraWrite() {
        var session = additionalWriteSession([.colour])
        recordWriteAttempt("priority", in: &session)
        recordWriteAttempt("colour", in: &session, outcome: .notWritten)
        XCTAssertTrue(GuidedTestFlow.remainingWriteRecipes(session: session).isEmpty,
                      "a recorded attempt must not trigger an automatic retry")
        XCTAssertNil(GuidedTestFlow.suggestedWriteRecipe(session: session))
        recordWriteAttempt("colour", in: &session)
        XCTAssertTrue(GuidedTestFlow.remainingWriteRecipes(session: session).isEmpty)
        XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, session: session, facts: CameraFacts()), .develop)
    }

    func testUnstartedTrialRemainsPendingWithoutChangingItsSavedDraft() {
        var session = additionalWriteSession()
        recordWriteAttempt("priority", in: &session)
        session.writePass?.trials.append(.init(id: "draft-colour", recipe: "colour", recipeName: "CT Colour", slot: 2,
                                               outcome: .notWritten, refusalReason: "Reconnect before writing."))
        session.writePass?.currentTrial = 1
        let original = session

        XCTAssertEqual(GuidedTestFlow.remainingWriteRecipes(session: session).map(\.id), ["colour", "mono", "kelvin"])
        XCTAssertEqual(GuidedTestFlow.suggestedWriteRecipe(session: session)?.id, "colour")
        XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, session: session, facts: CameraFacts()), .chooseRecipe)
        XCTAssertEqual(session, original, "planning must preserve an unsubmitted draft and its evidence")
        XCTAssertNil(session.writePass?.trial?.pushedAt)
    }

    func testSavedSessionRetainsPendingAdditionalWriteChecks() throws {
        var session = additionalWriteSession()
        recordWriteAttempt("priority", in: &session)
        recordWriteAttempt("colour", in: &session)
        session.writePass?.trials.append(.init(id: "draft-mono", recipe: "mono", recipeName: "CT Mono", slot: 2))
        session.writePass?.currentTrial = 2
        let data = try JSONEncoder().encode(session)
        let resumed = try JSONDecoder().decode(GuidedTestSession.self, from: data)

        XCTAssertEqual(resumed, session)
        XCTAssertEqual(GuidedTestFlow.remainingWriteRecipes(session: resumed).map(\.id), ["mono", "kelvin"])
        XCTAssertEqual(GuidedTestFlow.suggestedWriteRecipe(session: resumed)?.id, "mono")
        XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, session: resumed, facts: CameraFacts()), .chooseRecipe)
        XCTAssertEqual(resumed.writePass?.trial?.id, "draft-mono")
    }

    func testAdditionalRecipePresentationUsesSessionModelWhenAnotherBodyConnects() {
        var session = additionalWriteSession()
        recordWriteAttempt("priority", in: &session)
        let expected = ["priority", "colour", "mono", "kelvin"].compactMap {
            GuidedTestRecipes.recipe(id: $0, for: registry.model(withID: "X-T50")!)
        }
        XCTAssertEqual(GuidedTestFlow.writeRecipes(session: session), expected)
        XCTAssertEqual(GuidedTestFlow.next(after: .moreTrials, session: session, facts: facts("X-T20")), .chooseRecipe)
        XCTAssertEqual(GuidedTestFlow.writeRecipes(session: session), expected,
                       "a different live camera must not substitute its recipe settings into the stored test")
        XCTAssertEqual(GuidedTestFlow.suggestedWriteRecipe(session: session), expected.first { $0.id == "colour" })
    }

    /// The intro screen's promise must not be wider than the checklist that follows: an unlisted
    /// body is written to if its slots answer, as the untested note says, and developed on nowhere.
    /// A listed body keeps its card.
    func testTheCoverageCardPromisesAnUnlistedBodySavingAndNoDevelop() {
        let provisional = registry.provisionalModel(productName: "FUJIFILM X-T99")
        let unlisted = GuidedTestFlow.coverage(for: provisional, unlisted: true)
        XCTAssertEqual(unlisted.checks, [.reading, .saving])
        let untested = GuidedTestFlow.coverage(for: registry.model(withID: "GFX100 II"), unlisted: false)
        XCTAssertNotNil(untested.note)
        XCTAssertEqual(unlisted.note, untested.note, "decided by the slot read, in the untested entry's words")
        XCTAssertEqual(GuidedTestFlow.coverage(for: registry.model(withID: "GFX100"), unlisted: false).checks,
                       [.reading, .saving, .rawSettings])
        XCTAssertEqual(GuidedTestFlow.coverage(for: registry.model(withID: "X-T20"), unlisted: false).checks,
                       [.reading, .developing])
        XCTAssertEqual(GuidedTestFlow.coverage(for: registry.model(withID: "X-T50"), unlisted: false),
                       .init(checks: [.reading, .saving, .developing], note: nil))
        XCTAssertEqual(GuidedTestFlow.coverage(for: nil, unlisted: false).checks, [.reading, .saving, .developing])
    }

    /// An unlisted body has no registry entry to look recipes up by, and its provisional model's
    /// placeholder id is stored nowhere, so the session rebuilds that model from the product name
    /// it keeps: the write pass has recipes to offer, and the stored id stays nil.
    func testAnUnlistedBodyGetsItsRecipesFromTheProvisionalModel() {
        var session = GuidedTestSession.beginContinuous(step: .chooseRecipe)
        session.adopt(camera: unlistedFacts)
        session.plan?.optionalChecks = [.colour, .mono, .kelvin]
        XCTAssertNil(session.identifiedModelID, "the placeholder id is never stored")
        let provisional = registry.provisionalModel(productName: "FUJIFILM X-T99")
        XCTAssertEqual(session.cameraModel, provisional)
        XCTAssertEqual(GuidedTestFlow.writeRecipes(session: session),
                       ["priority", "colour", "mono", "kelvin"].compactMap { GuidedTestRecipes.recipe(id: $0, for: provisional) })
        XCTAssertEqual(GuidedTestFlow.suggestedWriteRecipe(session: session)?.id, "priority")
        XCTAssertEqual(GuidedTestFlow.writeRecipes(session: session),
                       GuidedTestFlow.writeRecipes(session: session), "rebuilt the same way every time")
    }

    /// A body nothing names has no model at all, provisional or otherwise.
    func testABodyNothingNamesHasNoRecipes() {
        var session = GuidedTestSession.beginContinuous(step: .chooseRecipe)
        session.adopt(camera: unknownFacts)
        XCTAssertNil(session.cameraModel)
        XCTAssertTrue(GuidedTestFlow.writeRecipes(session: session).isEmpty)
        XCTAssertNil(GuidedTestFlow.suggestedWriteRecipe(session: session))
    }

    func testContinuousIdentityCannotBeReboundByPluggingInAnotherBody() {
        var session = GuidedTestSession.beginContinuous()
        session.adopt(camera: facts("X-M5"))
        session.adopt(camera: facts("X-T50"))
        XCTAssertEqual(session.identifiedModelID, "X-M5")
    }

    func testAnUnwrittenTrialSkipsRestartButAnAcceptedNameStillGetsChecked() {
        var session = GuidedTestSession.beginContinuous()
        session.writePass = .init(trials: [.init(recipe: "priority", recipeName: "CT Priority", slot: 3,
                                               outcome: .notWritten)], currentTrial: 0)
        XCTAssertEqual(GuidedTestFlow.next(after: .push, session: session, facts: facts("X-M5")), .moreTrials)
        session.writePass?.trials[0].nameApplied = "CT Priority"
        XCTAssertEqual(GuidedTestFlow.next(after: .push, session: session, facts: facts("X-M5")), .powerCycle)
    }

    /// A refused first attempt wrote nothing, so it has nothing to check after a restart. The
    /// retry the camera accepts is the first real trial, and it gets the full check without the
    /// tester having to select extra restarts; a recipe after that is an extra, as before.
    func testARefusedFirstAttemptDoesNotUseUpTheRestartCheck() {
        var session = GuidedTestSession.beginContinuous()
        session.writePass = .init(trials: [.init(recipe: "priority", recipeName: "CT Priority", slot: 3,
                                               outcome: .notWritten),
                                           .init(recipe: "priority", recipeName: "CT Priority", slot: 2)],
                                  currentTrial: 1)
        XCTAssertEqual(session.writePass?.restartCheckTrial, 1, "the retry carries the planned check")

        session.writePass?.trials[1].outcome = .applied
        session.writePass?.trials[1].wrote = ["0xD192": "1500"]
        XCTAssertEqual(session.writePass?.restartCheckTrial, 1)
        XCTAssertEqual(GuidedTestFlow.next(after: .push, session: session, facts: facts("X-M5")), .powerCycle)

        session.writePass?.trials.append(.init(recipe: "colour", recipeName: "CT Colour", slot: 2,
                                             outcome: .applied, wrote: ["0xD192": "0B00"]))
        session.writePass?.currentTrial = 2
        XCTAssertEqual(GuidedTestFlow.next(after: .push, session: session, facts: facts("X-M5")), .moreTrials)
        XCTAssertEqual(session.writePass?.extraTrials.map(\.recipe), ["colour"])
    }

    func testUnpluggedMenuComparisonStillRoutesBothTestBodiesToWriting() {
        for modelID in ["X-M5", "X-T30 III"] {
            var session = GuidedTestSession.beginContinuous(step: .compareSlots)
            session.adopt(camera: facts(modelID))
            session.identification = "exact"
            session.identity = .init(confirmed: true)
            session.propertyReport = .init(state: .ran, count: 24)
            session.slotComparisons = [.init(slot: 1, confirmedMatching: true,
                                             checkedAt: CameraCompatibilityReport.timestamp())]
            XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: session, facts: CameraFacts()), .writeIntro)
            session.writePass = .init(dialConfirmed: false)
            XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: session, facts: CameraFacts()), .develop,
                           "a dial that can't be set pauses writing, not the whole test")
            session.writePass?.dialConfirmed = true
            session.identity?.confirmed = false
            XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: session, facts: CameraFacts()), .review)
            session.identity?.confirmed = true
            session.slotComparisons[0].rows = [.init(field: "grain", label: "Grain", appShowed: "Off", differs: true)]
            XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: session, facts: CameraFacts()), .review)
        }
    }

    /// The menu comparison is done unplugged, and a body with no registry entry has no entry to say
    /// whether writing follows. The connect's grant, kept on the session, answers; a session stored
    /// before it was kept still routes by its entry, which for an unlisted body is nothing.
    func testAnUnpluggedComparisonRoutesAnUnlistedBodyByTheGrantItsConnectRecorded() {
        var session = GuidedTestSession.beginContinuous(step: .compareSlots)
        session.adopt(camera: unlistedFacts)
        XCTAssertEqual(session.writeGranted, true)
        session.identity = .init(confirmed: true)
        session.propertyReport = .init(state: .ran, count: 24)
        session.slotComparisons = [.init(slot: 1, confirmedMatching: true,
                                         checkedAt: CameraCompatibilityReport.timestamp())]
        let unplugged = CameraFacts()
        XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: session, facts: unplugged), .writeIntro)
        XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: session, facts: unlistedFacts), .writeIntro,
                       "plugged back in, the live decision agrees")

        var refused = session
        refused.adopt(camera: unlistedRefusedFacts)
        XCTAssertEqual(refused.writeGranted, false)
        XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: refused, facts: unplugged), .develop)

        var legacy = session
        legacy.writeGranted = nil
        XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: legacy, facts: unplugged), .develop,
                       "with no grant kept and no entry, writing is not offered unplugged")

        // A listed body the registry has no word on is granted the same way, and its stored entry
        // alone would have skipped the write pass it had just been granted.
        var untested = GuidedTestSession.beginContinuous(step: .compareSlots)
        var granted = facts("GFX100 II")
        granted.canWrite = true
        untested.adopt(camera: granted)
        untested.identification = "exact"
        untested.identity = .init(confirmed: true)
        untested.propertyReport = .init(state: .ran, count: 24)
        untested.slotComparisons = session.slotComparisons
        XCTAssertFalse(registry.model(withID: "GFX100 II")?.allowsWrite ?? true, "precondition: the entry says untested")
        XCTAssertEqual(GuidedTestFlow.next(after: .compareSlots, session: untested, facts: unplugged), .writeIntro)
    }

    func testContinuousFlowSkipsConfirmedDialButPausesFailedEmptySlotReading() {
        var session = GuidedTestSession.beginContinuous()
        session.writePass = .init(dialConfirmed: true)
        XCTAssertEqual(GuidedTestFlow.next(after: .backup, session: session, facts: facts("X-M5")), .grainProbe)
        session.writePass?.dialConfirmed = false
        XCTAssertEqual(GuidedTestFlow.next(after: .backup, session: session, facts: facts("X-M5")), .dialCheck)
        XCTAssertEqual(GuidedTestFlow.next(after: .dialCheck, session: session, facts: facts("X-M5")), .develop,
                       "declining on the dial step lands where declining at the comparison does")
        session.writePass?.dialConfirmed = true
        XCTAssertEqual(GuidedTestFlow.next(after: .dialCheck, session: session, facts: facts("X-M5")), .grainProbe)
        session.writePass?.dialConfirmed = false
        session.propertyReport = .init(state: .failed)
        XCTAssertEqual(GuidedTestFlow.next(after: .readSlots, session: session, facts: facts("X-M5", occupied: false)), .review)
    }

    func testContinuousGrainCheckMustFinishBeforeChoosingARecipe() {
        var session = GuidedTestSession.beginContinuous(step: .grainProbe)
        XCTAssertEqual(GuidedTestFlow.next(after: .grainProbe, session: session, facts: facts("X-T50")), .grainProbe)
        for state: GuidedTestSession.ProbeOutcome.State in [.skipped, .notRun, .notWritable, .refused] {
            session.grainProbe = .init(state: state)
            XCTAssertEqual(GuidedTestFlow.next(after: .grainProbe, session: session, facts: facts("X-T50")), .grainProbe)
        }
        session.grainProbe = .init(state: .ran)
        XCTAssertEqual(GuidedTestFlow.next(after: .grainProbe, session: session, facts: facts("X-T50")), .chooseRecipe)
        session.grainProbe = .init(state: .failed)
        XCTAssertEqual(GuidedTestFlow.next(after: .grainProbe, session: session, facts: facts("X-T50")), .restoreOffer)
        session.grainProbe = .init(state: .notWritable)
        XCTAssertEqual(GuidedTestFlow.next(after: .grainProbe, session: session, facts: facts("GFX100 II")), .develop)
    }

    func testOlderSkippedGrainSessionsReturnToPrerequisiteOrRecovery() {
        var session = GuidedTestSession.beginContinuous(step: .push)
        session.grainProbe = .init(state: .skipped)
        for step: GuidedTestStep in [.chooseRecipe, .chooseSlot, .push] {
            XCTAssertEqual(GuidedTestFlow.writePrerequisiteStep(for: step, session: session), .grainProbe)
        }
        session.writePass = .init(trials: [.init(recipe: "priority", recipeName: "CT Priority", slot: 1,
                                                pushedAt: CameraCompatibilityReport.timestamp())])
        XCTAssertEqual(GuidedTestFlow.writePrerequisiteStep(for: .chooseRecipe, session: session), .restoreOffer)
        for step: GuidedTestStep in [.powerCycle, .photoCheck, .develop, .review] {
            XCTAssertEqual(GuidedTestFlow.writePrerequisiteStep(for: step, session: session), step)
        }
        session.grainProbe = .init(state: .ran)
        XCTAssertEqual(GuidedTestFlow.writePrerequisiteStep(for: .chooseRecipe, session: session), .chooseRecipe)
        let legacy = GuidedTestSession.begin(wave: 2, step: .push)
        XCTAssertEqual(GuidedTestFlow.writePrerequisiteStep(for: .push, session: legacy), .push)
    }

    func testUnknownMenuValuesStayUnverifiedAfterTheTesterRecordsThem() {
        var comparison = GuidedTestSession.SlotComparison(slot: 1, fieldsAppCouldNotRead: ["Grain"],
                                                          confirmedMatching: true)
        comparison.unreadableCameraShows = ["Grain": "Off"]
        comparison.checkedAt = CameraCompatibilityReport.timestamp()
        XCTAssertEqual(comparison.verdict, "unverified")
        XCTAssertTrue(comparison.rows.isEmpty, "the observation must not invent decoded settings")
        let session = GuidedTestSession.beginContinuous()
        var withObservation = session
        withObservation.slotComparisons = [comparison]
        let record = CameraCompatibilityReport.GuidedTestRecord(session: withObservation)
        XCTAssertEqual(record.slotComparisons?.first?.unreadableCameraShows, ["Grain": "Off"])
        XCTAssertEqual(record.slotComparisons?.first?.verdict, "unverified")
    }

    // MARK: Develop detection

    /// By timestamp, never by count: `develops` is capped at twenty and rebuilt on every connect, so
    /// a count taken before and after can fall as easily as rise.
    func testADevelopIsDetectedByWhenItHappened() {
        var report = CameraCompatibilityReport.beginUnreached()
        let entered = Date(timeIntervalSince1970: 1_757_000_000)
        XCTAssertFalse(GuidedTestFlow.developed(since: entered, in: report))

        report.record(develop: CookEvidence(), at: entered.addingTimeInterval(-60), modelID: "X-T5",
                      firmwareVersion: nil, succeeded: true, clampedFields: [], filmSimulation: nil)
        XCTAssertFalse(GuidedTestFlow.developed(since: entered, in: report),
                       "a cook from before the tester reached this step isn't this step's")

        report.record(develop: CookEvidence(), at: entered.addingTimeInterval(30), modelID: "X-T5",
                      firmwareVersion: nil, succeeded: false, clampedFields: [], filmSimulation: nil)
        XCTAssertTrue(GuidedTestFlow.developed(since: entered, in: report),
                      "a failed develop still happened — the question is whether they tried")
    }

    // MARK: Projection into the report

    func testTheRecordCarriesWhatTheTesterSaidAndWhatTheySkipped() {
        var session = GuidedTestSession.begin(wave: 1, step: .grainProbe)
        session.adopt(camera: facts("X-T5"))
        session.completedSteps = [.intro, .connect, .confirmIdentity]
        session.identity = .init(confirmed: true)
        session.propertyReport = .init(state: .ran, slot: 2, count: 26, readOnly: false)
        session.grainProbe = .init(state: .skipped, detail: "skipped by the tester")
        session.develop = .init(state: .notRun)
        session.freeText = "Dial was on C the whole time."
        var comparison = GuidedTestFlow.comparison(
            for: slot([:], name: "ACROS Street"),
            model: registry.model(withID: "X-T5"))
        comparison.rows = [.init(field: "grain", label: "Grain Effect", appShowed: "Weak, Large",
                                 differs: true, cameraShows: "Weak, Small")]
        comparison.checkedAt = Date()
        session.slotComparisons = [comparison]
        session.outcome = .sentEarly

        let record = CameraCompatibilityReport.GuidedTestRecord(session: session)

        XCTAssertEqual(record.wave, 1)
        XCTAssertEqual(record.outcome, "sentEarly")
        XCTAssertEqual(record.outcomeStep, "grainProbe")
        XCTAssertEqual(record.identity?.appShowedModelID, "X-T5")
        XCTAssertEqual(record.identity?.confirmed, true)
        XCTAssertEqual(record.slotComparisons?.count, 1)
        XCTAssertEqual(record.slotComparisons?.first?.verdict, "differs")
        XCTAssertEqual(record.slotComparisons?.first?.rows?.first?.cameraShows, "Weak, Small")
        XCTAssertEqual(record.slotComparisons?.first?.rows?.first?.field, "Grain Effect",
                       "spelled for a reader, not as a raw value")
        XCTAssertEqual(record.grainProbe?.state, "skipped")
        XCTAssertEqual(record.develop?.state, "notRun")
        XCTAssertEqual(record.freeText, "Dial was on C the whole time.")
        XCTAssertEqual(record.stepsCompleted, ["intro", "connect", "confirmIdentity"])
    }

    /// A slot the tester never opened must not appear as a slot they checked and had nothing to say
    /// about — silence and "it matched" are different answers.
    func testAnUncheckedSlotIsNotRecordedAsChecked() {
        var session = GuidedTestSession.begin(wave: 1, step: .compareSlots)
        session.slotComparisons = [GuidedTestSession.SlotComparison(slot: 1),
                                   GuidedTestSession.SlotComparison(slot: 2, checkedAt: Date())]
        let record = CameraCompatibilityReport.GuidedTestRecord(session: session)
        XCTAssertEqual(record.slotComparisons?.map(\.slot), [2])
    }

    /// The bank's ISO and image format are the two conditions a tester can read and the app can't,
    /// and they decide whether a refused Dynamic Range, D-Range Priority or Clarity write was the
    /// camera's gate or a finding. Noted, they travel; not noted, they stay absent rather than
    /// defaulting to base ISO or JPEG.
    func testTheComparisonCarriesTheBankConditionsTheTesterNoted() {
        var session = GuidedTestSession.begin(wave: 1, step: .compareSlots)
        var noted = GuidedTestSession.SlotComparison(slot: 1, checkedAt: Date())
        noted.isoShown = "1600"
        noted.imageFormatShown = .heif
        session.slotComparisons = [noted, GuidedTestSession.SlotComparison(slot: 2, checkedAt: Date())]

        let record = CameraCompatibilityReport.GuidedTestRecord(session: session)

        XCTAssertEqual(record.slotComparisons?[0].isoShown, "1600")
        XCTAssertEqual(record.slotComparisons?[0].imageFormatShown, "heif")
        XCTAssertNil(record.slotComparisons?[1].isoShown)
        XCTAssertNil(record.slotComparisons?[1].imageFormatShown)
    }

    /// Whether the tester prepared the write slot, and what AUTO UPDATE CUSTOM SETTING was set to,
    /// are what a reader needs before judging a refused gated write or a restart result.
    func testTheWritePassProjectsThePreparationAndTheAutoUpdateState() {
        var session = GuidedTestSession.begin(wave: 2, step: .send)
        var prepared = GuidedTestSession.PushTrial(recipe: "priority", recipeName: "CT Priority", slot: 7)
        prepared.preparation = .setForTest
        prepared.preparationConfirmedAt = Date(timeIntervalSince1970: 1_760_000_000)
        var left = GuidedTestSession.PushTrial(recipe: "colour", recipeName: "CT Colour", slot: 6)
        left.preparation = .leftUnchanged
        let unasked = GuidedTestSession.PushTrial(recipe: "mono", recipeName: "CT Mono", slot: 5)
        var pass = GuidedTestSession.WritePass(consentAt: Date(), trials: [prepared, left, unasked])
        pass.autoUpdateCustomSetting = .disable
        session.writePass = pass

        let record = CameraCompatibilityReport.GuidedTestRecord(session: session)

        XCTAssertEqual(record.writePass?.autoUpdateCustomSetting, "disable")
        XCTAssertEqual(record.writePass?.trials?[0].preparation, "setForTest")
        XCTAssertEqual(record.writePass?.trials?[0].preparationConfirmedAt,
                       Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(record.writePass?.trials?[1].preparation, "leftUnchanged")
        XCTAssertNil(record.writePass?.trials?[2].preparation, "an unasked question stays unknown")
    }

    func testAPastedNovelIsCappedRatherThanCarried() {
        var session = GuidedTestSession.begin(wave: 1, step: .review)
        session.freeText = String(repeating: "x", count: 9000)
        let record = CameraCompatibilityReport.GuidedTestRecord(session: session)
        XCTAssertEqual(record.freeText?.count,
                       CameraCompatibilityReport.GuidedTestRecord.maxFreeTextCharacters)
    }

    func testTheWritePassProjectsItsTrials() {
        var session = GuidedTestSession.begin(wave: 2, step: .send)
        session.outcome = .completed
        var trial = GuidedTestSession.PushTrial(recipe: "colour", recipeName: "CT Colour", slot: 5)
        trial.outcome = .applied
        trial.persistence = .init(persisted: false,
                                  differences: [.init(field: "Film Simulation", code: "0xD192",
                                                      wrote: "0B00", holds: "0100")])
        trial.photoMatchesRecipe = .no
        session.writePass = .init(consentAt: Date(),
                                  backup: .init(savedAt: Date(), activity: "Files"),
                                  dialConfirmed: true, trials: [trial],
                                  restores: [.init(slot: 5, outcome: .applied)])

        let record = CameraCompatibilityReport.GuidedTestRecord(session: session)
        XCTAssertNil(record.outcomeStep, "a completed test didn't stop anywhere")
        XCTAssertEqual(record.writePass?.trials?.count, 1)
        XCTAssertEqual(record.writePass?.trials?.first?.persistence?.persisted, false)
        XCTAssertEqual(record.writePass?.trials?.first?.persistence?.differences?.first?.holds, "0100")
        XCTAssertEqual(record.writePass?.trials?.first?.photoMatchesRecipe, "no")
        XCTAssertEqual(record.writePass?.restores?.first?.slot, 5)
        XCTAssertEqual(record.writePass?.dialConfirmed, true)
    }

    // MARK: Steps

    func testBothWavesEndOnSend() {
        XCTAssertEqual(GuidedTestFlow.mainLine(wave: 1).last, .send)
        XCTAssertEqual(GuidedTestFlow.mainLine(wave: 2).last, .send)
        XCTAssertTrue(GuidedTestFlow.mainLine(wave: 2).contains(.powerCycle))
        XCTAssertFalse(GuidedTestFlow.mainLine(wave: 1).contains(.push))
    }

    // MARK: Unplugs the tester was asked for

    /// The five steps that ask for the cable out, or for the camera off: the menu comparisons, the
    /// photo, the power cycle, and choosing a slot, which sends the tester into the menu to set the
    /// write slot's ISO and image format. The manager reads this to wait longer and to stop counting
    /// the drop against the "your cable is bad" throttle.
    func testTheStepsThatAskForAnUnplugSaySo() {
        let expects = Set(GuidedTestStep.allCases.filter(\.expectsUnplug))
        XCTAssertEqual(expects, [.compareSlots, .chooseSlot, .powerCycle, .recheckSlot, .photoCheck])
    }

    /// A body can take longer to reappear after a power cycle than the ordinary schedule waits
    /// (zgrimz/fujifilm-ptp-reference `docs/09-platform-notes.md#disconnection`), so the expected
    /// schedule has to outlast a camera's boot.
    func testTheExpectedRecoveryOutlastsACameraComingBackUp() {
        let ordinary = RecoveryPolicy.plan(expected: false)
        let expected = RecoveryPolicy.plan(expected: true)

        func span(_ plan: (delays: [UInt64], deviceWait: TimeInterval)) -> TimeInterval {
            plan.delays.reduce(0) { $0 + TimeInterval($1) / 1_000_000_000 }
                + TimeInterval(plan.delays.count) * plan.deviceWait
        }

        XCTAssertLessThan(span(ordinary), 20, "the ordinary plan is unchanged")
        XCTAssertGreaterThan(span(expected), 25,
                             "the expected plan outlasts a camera's boot")
        XCTAssertEqual(expected.delays.count, ordinary.delays.count,
                       "more patience per attempt, not more attempts")
    }

    /// Unplugging with nothing running is ordinary — people pull the cable without tapping
    /// Disconnect — and must end in the plain disconnected state, not the "disconnected during the
    /// operation" warning. A loss during a read, a write or a conversion keeps the warning.
    @MainActor
    func testOnlyALossDuringAnOperationCountsAsInterruptingOne() {
        typealias M = CameraConnector
        XCTAssertFalse(M.lossInterruptsOperation(status: .connected, exclusiveOperation: nil), "idle")
        XCTAssertFalse(M.lossInterruptsOperation(status: .failed("an earlier refusal"), exclusiveOperation: nil),
                       "an earlier failure on a live session is not something still running")

        XCTAssertTrue(M.lossInterruptsOperation(status: .working("Writing slot C3…"), exclusiveOperation: "push to C3"))
        XCTAssertTrue(M.lossInterruptsOperation(status: .connected, exclusiveOperation: "push to C3"),
                      "a push holds the gate across its refresh, whose status briefly reads connected")
        XCTAssertTrue(M.lossInterruptsOperation(status: .working("Reading slot C2…"), exclusiveOperation: nil),
                      "connect's own slot read and the Kitchen's conversions run ungated")
        XCTAssertTrue(M.lossInterruptsOperation(status: .connecting, exclusiveOperation: nil))
    }

    /// The expiry is the whole reason this is a date. A flag that leaked would hand a genuinely
    /// broken cable the patient schedule for the rest of the session.
    @MainActor
    func testTheExpectationExpires() {
        let m = CameraServices()
        m.connector.expectRemoval(true, for: 300)
        XCTAssertTrue(m.connector.removalIsExpected)

        m.connector.expectRemoval(true, for: -1)
        XCTAssertFalse(m.connector.removalIsExpected, "an elapsed window is not an expectation")

        m.connector.expectRemoval(false)
        XCTAssertNil(m.connector.removalExpectedUntil)
    }
    // MARK: Where the write pass lands

    private func slot(_ index: Int, name: String?, occupied: Bool) -> CameraSlot {
        CameraSlot(index: index, label: "C\(index)", name: name, isOccupied: occupied,
                   settings: nil, rawProperties: [:], unsupportedFields: [:])
    }

    /// An empty slot first — nothing of the tester's is then at stake.
    func testAnEmptySlotIsPreferred() {
        let slots = [slot(1, name: "SUNDAY", occupied: true),
                     slot(2, name: nil, occupied: false),
                     slot(3, name: nil, occupied: true)]
        XCTAssertEqual(GuidedTestFlow.defaultWriteSlot(in: slots), 2)
    }

    func testXM5ReusesAConfirmedGrainBankWithoutGivingUpAnEmptyBank() {
        var session = GuidedTestSession.beginContinuous()
        session.identifiedModelID = "X-M5"
        session.grainProbe = .init(state: .ran, slot: 1)
        session.setStillBankConfirmation(1, confirmed: true)
        let occupied = [slot(1, name: "Original", occupied: true), slot(2, name: nil, occupied: true)]
        XCTAssertEqual(GuidedTestFlow.suggestedWriteSlot(in: occupied, session: session), 1)
        let withEmpty = occupied + [slot(3, name: nil, occupied: false)]
        XCTAssertEqual(GuidedTestFlow.suggestedWriteSlot(in: withEmpty, session: session), 3)
        session.selectedWriteSlot = 2
        XCTAssertEqual(GuidedTestFlow.suggestedWriteSlot(in: withEmpty, session: session), 2,
                       "The tester's chosen bank takes precedence, with its own confirmation still required")
        session.selectedWriteSlot = nil
        session.setStillBankConfirmation(1, confirmed: false)
        XCTAssertEqual(GuidedTestFlow.suggestedWriteSlot(in: occupied, session: session), 2)
    }

    /// The GFX100S case. Every bank answers `0xD192`, so nothing reads as empty, and the *first*
    /// slot is the one most likely to hold a recipe someone made. An unnamed bank is what "nobody
    /// has used this" looks like on a body like that, and the highest-numbered one is the least
    /// likely to be someone's favourite.
    func testWithNothingEmptyTheHighestUnnamedSlotWins() {
        let slots = (1...6).map { slot($0, name: $0 == 1 ? "SUNDAY" : nil, occupied: true) }
        XCTAssertEqual(GuidedTestFlow.defaultWriteSlot(in: slots), 6)
    }

    /// And a camera whose every bank is named gets the last one, not the first.
    func testEveryBankNamedFallsBackToTheLast() {
        let slots = (1...4).map { slot($0, name: "RECIPE \($0)", occupied: true) }
        XCTAssertEqual(GuidedTestFlow.defaultWriteSlot(in: slots), 4)
    }

    /// A trial exists before a slot is chosen, and the hub can reach the push step directly.
    func testAPushIsNotOfferedBeforeASlotIsChosen() {
        var pass = GuidedTestSession.WritePass()
        pass.trials = [.init(recipe: "mono", recipeName: "CT Mono", slot: 0)]
        pass.currentTrial = 0

        XCTAssertNotNil(pass.trial, "the trial exists")
        XCTAssertNil(pass.trialWithASlot, "but not with a slot to write to")

        pass.trials[0].slot = 6
        XCTAssertEqual(pass.trialWithASlot?.slot, 6)
    }

    // MARK: The profile harvest

    /// Offered exactly where it can teach something: a body the app doesn't develop on, that can
    /// be sent a RAF. Everywhere else the answer is already known or there is nobody to ask.
    func testTheHarvestIsOfferedOnlyWhereTheKitchenIsOffAndTheBodyIsTrusted() {
        var facts = CameraFacts()
        facts.canConvert = false
        facts.canHarvestProfile = true
        XCTAssertTrue(GuidedTestFlow.offersProfileHarvest(facts: facts), "a trusted body the app doesn't develop on")

        facts.canConvert = true
        XCTAssertFalse(GuidedTestFlow.offersProfileHarvest(facts: facts),
                       "a body that converts has a develop step, which is a harvest and then some")

        facts.canConvert = false
        facts.canHarvestProfile = false
        XCTAssertFalse(GuidedTestFlow.offersProfileHarvest(facts: facts),
                       "a guessed body, or one with no upload path, is not sent a file")
    }

    /// The harvest is its own fact in the record, beside a develop that is still — truthfully —
    /// not writable.
    func testTheHarvestReachesTheReportBesideTheDevelopItDidNotReplace() {
        var session = GuidedTestSession.begin(wave: 1, step: .develop)
        session.develop = .init(state: .notWritable, detail: "RAW conversion isn't enabled for this body.")
        session.profileHarvest = .init(state: .ran, detail: "601-byte profile, layout resolved at base 0x1FD")

        let record = CameraCompatibilityReport.GuidedTestRecord(session: session)
        XCTAssertEqual(record.develop?.state, "notWritable", "nothing was developed, and it still says so")
        XCTAssertEqual(record.profileHarvest?.state, "ran")
        XCTAssertEqual(record.profileHarvest?.detail, "601-byte profile, layout resolved at base 0x1FD")
    }

    func testASessionWithoutAHarvestProjectsNone() {
        let record = CameraCompatibilityReport.GuidedTestRecord(session: GuidedTestSession.begin(wave: 1, step: .develop))
        XCTAssertNil(record.profileHarvest, "absent, not a state — the step was never reached")
    }

    // MARK: Honest coverage summary

    func testARequestedSecondComparisonStaysIncompleteUntilBothMatch() {
        var session = GuidedTestSession.beginContinuous(step: .compareSlots)
        session.plan?.optionalChecks.insert(.secondSlotComparison)
        var first = GuidedTestSession.SlotComparison(slot: 1)
        first.confirmedMatching = true
        first.checkedAt = Date()
        session.slotComparisons = [first, .init(slot: 2)]
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == "compare" }?.state, "Incomplete")

        session.slotComparisons[1].confirmedMatching = true
        session.slotComparisons[1].checkedAt = Date()
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == "compare" }?.state, "Passed")

        // Clearing old differences and leaving the screen is not the same as reconfirming a match.
        session.plan?.optionalChecks.remove(.secondSlotComparison)
        session.slotComparisons = [first]
        session.slotComparisons[0].confirmedMatching = false
        XCTAssertNotEqual(CameraTestSummary.rows(session).first { $0.id == "compare" }?.state, "Passed")
    }

    func testAReadEmptyCameraIsUnavailableComparisonCoverage() {
        var session = GuidedTestSession.beginContinuous(step: .writeIntro)
        session.completedSteps = [.readSlots]
        session.propertyReport = .init(state: .ran, count: 0)
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == "compare" }?.state, "Unavailable")

        session.propertyReport = .init(state: .failed)
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == "compare" }?.state, "Not checked",
                       "a failed read cannot establish that the camera's slots were empty")
    }

    func testKitchenSummarySeparatesProductionFromVerificationAndStorage() {
        let recipe = GuidedKitchenRecipe(id: "colour", name: "CT Colour", settings: .neutral)
        let run = GuidedKitchenRun(caseID: "develop", recipes: [recipe], fullResolution: true)
        var result = ConversionResult(sourceFilename: "private.RAF", success: true,
                                      clampedFields: ["Dynamic Range (DR200 → DR100)"])
        result.recoveryFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("private.jpg")
        result.evidence.profileVerified = true
        result.evidence.dynamicRange = "cappedToAsShot(200->100)"
        var completion = GuidedKitchenCompletion(run: run,
            cells: [.init(result: result, recipeID: recipe.id, fileIndex: 0)],
            savedBatchID: UUID(), saveFailed: false)
        var session = GuidedTestSession.beginContinuous(step: .develop)
        session.kitchenRuns = [run]
        session.kitchenCompletions = [completion]
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == run.id.uuidString }?.state, "Passed",
                       "an expected as-shot DR cap is an explained adjustment")
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == run.id.uuidString + "-look" }?.state, "Not checked",
                       "automatic conversion does not supply a visual observation")

        completion.saveFailed = true
        session.kitchenCompletions = [completion]
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == run.id.uuidString }?.state, "Issue found")
        XCTAssertTrue(CameraTestSummary.rows(session).first { $0.id == run.id.uuidString }?.detail.contains("could not be saved") == true)
        completion.saveFailed = false
        completion.cells[0].profileVerified = false
        session.kitchenCompletions = [completion]
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == run.id.uuidString }?.state, "Issue found")
        completion.cells[0].profileVerified = nil
        session.kitchenCompletions = [completion]
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == run.id.uuidString }?.state, "Could not verify")
        session.kitchenCompletions = []
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == run.id.uuidString }?.state, "Could not verify",
                       "a persisted started run with no completion is interrupted or unfinished")
    }

    func testRecordedWorkAndObservationsHaveCompletionChecksWithoutClaimingVerification() throws {
        var session = GuidedTestSession.beginContinuous(step: .review)
        session.propertyReport = .init(state: .ran, count: 26)
        session.grainProbe = .init(state: .ran, count: 10)
        var trial = GuidedTestSession.PushTrial(recipe: "priority", recipeName: "CT Priority", slot: 1)
        trial.outcome = .applied
        trial.photoMatchesRecipe = .yes
        session.writePass = .init(trials: [trial])
        let rows = CameraTestSummary.rows(session)
        for id in ["read", "grain", "trial-0-photo"] {
            let row = try XCTUnwrap(rows.first { $0.id == id })
            XCTAssertTrue(row.status.isCompleted)
            XCTAssertEqual(row.icon, "checkmark.circle")
            XCTAssertNotEqual(row.status, .passed, "completed observation is not automatic verification")
        }
        XCTAssertEqual(rows.first { $0.id == "read" }?.status, .recorded)
        XCTAssertEqual(rows.first { $0.id == "trial-0-photo" }?.status, .observed)
        XCTAssertEqual(rows.first { $0.id == "trial-0" }?.status, .passed)
        XCTAssertEqual(rows.first { $0.id == "trial-0" }?.icon, "checkmark.circle.fill")
    }

    func testUnselectedExtrasAreNeutralWhileSelectedMissingChecksRemainVisible() throws {
        var session = GuidedTestSession.beginContinuous(step: .review)
        let initial = CameraTestSummary.rows(session)
        let omitted = initial.filter { !$0.isIncluded }
        XCTAssertEqual(omitted.count, GuidedTestSession.OptionalCheck.allCases.count)
        XCTAssertTrue(omitted.allSatisfy { $0.status == .notIncluded && $0.icon == "minus" })
        XCTAssertTrue(initial.first { $0.id == "develop" }?.isIncluded == true,
                      "the baseline Develop remains visible when it has no attempt")

        session.plan?.optionalChecks = [.colour, .testKitchen, .dynamicRange]
        let selected = CameraTestSummary.rows(session)
        for id in ["extra-colour", "testKitchen", "dr-100", "dr-200", "dr-400", "dr-auto"] {
            let row = try XCTUnwrap(selected.first { $0.id == id })
            XCTAssertTrue(row.isIncluded)
            XCTAssertEqual(row.status, .notTested)
        }
        XCTAssertFalse(selected.contains { $0.id == "optional-colour" })
        XCTAssertTrue(selected.contains { $0.id == "optional-mono" && !$0.isIncluded })
    }

    func testDevelopRecipeUseIsDistinctFromSlotWritingAndAttemptedExtrasStayVisible() throws {
        let recipe = GuidedKitchenRecipe(id: "colour", name: "CT Colour", settings: .neutral)
        let develop = GuidedKitchenRun(caseID: "develop", recipes: [recipe], fullResolution: true)
        let kitchen = GuidedKitchenRun(caseID: "testKitchen", recipes: [recipe], fullResolution: false)
        var session = GuidedTestSession.beginContinuous(step: .review)
        session.kitchenRuns = [develop, kitchen]
        let rows = CameraTestSummary.rows(session)
        let developRow = try XCTUnwrap(rows.first { $0.id == develop.id.uuidString })
        XCTAssertEqual(developRow.title, "Develop with CT Colour")
        let writeRow = try XCTUnwrap(rows.first { $0.id == "optional-colour" })
        XCTAssertEqual(writeRow.title, "Write CT Colour to a camera slot")
        XCTAssertFalse(writeRow.isIncluded, "Develop does not prove a slot-write test happened")
        XCTAssertTrue(rows.first { $0.id == kitchen.id.uuidString }?.isIncluded == true,
                      "an attempted optional check remains in the main summary after deselection")
        XCTAssertEqual(rows.first { $0.id == kitchen.id.uuidString }?.status, .couldNotVerify)
        XCTAssertFalse(rows.contains { $0.id == "optional-testKitchen" })
        XCTAssertTrue(CameraTestSummary.lines(session).contains { $0.contains("Write CT Colour to a camera slot: Not included") })
    }

    func testLaterWriteFollowUpsAreIncludedOnlyWhenSelectedOrObserved() throws {
        var session = GuidedTestSession.beginContinuous(step: .review)
        session.plan?.optionalChecks = [.colour]
        session.writePass = .init(trials: [
            .init(recipe: "priority", recipeName: "CT Priority", slot: 1),
            .init(recipe: "colour", recipeName: "CT Colour", slot: 1)
        ])
        for suffix in ["restart", "menu", "photo"] {
            let rows = CameraTestSummary.rows(session)
            XCTAssertEqual(rows.first { $0.id == "trial-1-" + suffix }?.status, .notIncluded)
            XCTAssertTrue(rows.first { $0.id == "trial-0-" + suffix }?.isIncluded == true)
        }
        session.writePass?.trials[1].persistence = .init(persisted: true, evidenceState: .passed,
                                                       settingsState: .passed, nameState: .notTested,
                                                       restartConfirmed: true)
        session.writePass?.trials[1].photoMatchesRecipe = .yes
        let observed = CameraTestSummary.rows(session)
        XCTAssertEqual(observed.first { $0.id == "trial-1-restart" }?.status, .passed)
        XCTAssertEqual(observed.first { $0.id == "trial-1-photo" }?.status, .observed)
        XCTAssertFalse(observed.first { $0.id == "trial-1-restart" }?.detail.contains("name matched") == true,
                       "passing settings cannot imply an untested name matched")
        session.plan?.optionalChecks.insert(.extraRestarts)
        XCTAssertEqual(CameraTestSummary.rows(session).first { $0.id == "trial-1-menu" }?.status, .notChecked)
    }

    func testGuidedPriorityComparisonKeepsRawEvidenceButDoesNotAskToMatchInactiveNumbers() throws {
        let model = try XCTUnwrap(registry.model(withID: "X-T50"))
        let slot = CameraSlot(index: 1, label: "C1", name: "CT Priority", isOccupied: true,
                              settings: RecipeSettings(filmSimulation: .realaAce, dynamicRange: .dr400,
                                  dRangePriority: .auto, highlightTone: -1.5, shadowTone: -1),
                              rawProperties: [:], unsupportedFields: [:])
        var comparison = GuidedTestFlow.comparison(for: slot, model: model)
        for field in [RecipeField.dynamicRange, .highlightTone, .shadowTone] {
            let row = try XCTUnwrap(comparison.rows.first { $0.field == field.rawValue })
            let presentation = GuidedComparisonRowPresentation(row: row)
            XCTAssertTrue(presentation.priorityControlled)
            XCTAssertEqual(presentation.value, "Controlled by D-Range Priority")
            XCTAssertTrue(row.appShowed.contains(RecipeSettingsFormatter.priorityNote))
        }
        let priority = try XCTUnwrap(comparison.rows.first { $0.field == RecipeField.dRangePriority.rawValue })
        XCTAssertEqual(GuidedComparisonRowPresentation(row: priority).value, "Auto")
        XCTAssertFalse(GuidedComparisonRowPresentation(row: priority).priorityControlled)

        comparison.checkedAt = Date()
        var session = GuidedTestSession.beginContinuous(step: .review)
        session.slotComparisons = [comparison]
        let report = CameraCompatibilityReport.GuidedTestRecord(session: session)
        let reportedHighlight = try XCTUnwrap(report.slotComparisons?.first?.rows?.first { $0.field == "Highlight Tone" })
        XCTAssertEqual(reportedHighlight.appShowed, "−1.5 · overridden by D-Range Priority")
        XCTAssertEqual(reportedHighlight.displayedValue, "Controlled by D-Range Priority")

        let legacy = GuidedTestSession.SlotComparison.Row(field: "highlightTone", label: "Highlight Tone",
            appShowed: "−1.5 · overridden by D-Range Priority")
        XCTAssertEqual(GuidedComparisonRowPresentation(row: legacy).value, "Controlled by D-Range Priority")
        let active = GuidedTestSession.SlotComparison.Row(field: "highlightTone", label: "Highlight Tone", appShowed: "−1.5",
                                                         priorityControlled: false)
        XCTAssertEqual(GuidedComparisonRowPresentation(row: active).value, "−1.5")
    }

    func testRestoreFinalMatchAndCommandWarningRemainSeparateEvidence() throws {
        let verification = RestoreVerification(at: Date(), readAt: Date(), outcome: .applied,
            commandOutcome: .partiallyApplied, freshReadSucceeded: true,
            originalName: "Original", expectedName: "Original", currentName: "Original",
            nameMatches: true, originalNameRestorable: true,
            fields: [.init(code: "0xD190", original: "9001", current: "9001", matches: true)],
            reasons: ["Dynamic Range write was refused, but its original value was already present."])
        let rows = CameraTestSummary.restoreRows(slot: 1, disposition: .restored, verification: verification)
        XCTAssertEqual(rows.first { $0.id == "restore-1" }?.status, .passed)
        let warning = try XCTUnwrap(rows.first { $0.id == "restore-1-command" })
        XCTAssertEqual(warning.status, .commandWarning)
        XCTAssertTrue(warning.detail.contains("refused"))

        let legacy = CameraTestSummary.restoreRows(slot: 1, disposition: .partiallyApplied, verification: nil)
        XCTAssertEqual(legacy.first?.status, .needsAttention,
                       "an old partial command result cannot be promoted to restored without final-state evidence")
    }
}
