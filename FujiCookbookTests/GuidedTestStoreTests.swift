import XCTest
@testable import FujiCookbook

/// The in-progress guided test on disk.
///
/// It has to survive a relaunch, because the write pass asks the tester to switch their camera off
/// and on and an iOS kill during that is ordinary — losing everything they had already typed at that
/// moment is the one failure that would stop them finishing.
final class GuidedTestStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        GuidedTestStore.deleteAll()
        GuidedRecoveryStore.deleteAll()
    }

    override func tearDown() {
        GuidedTestStore.deleteAll()
        GuidedRecoveryStore.deleteAll()
        super.tearDown()
    }

    private func sampleSession() -> GuidedTestSession {
        var session = GuidedTestSession.begin(wave: 1, step: .compareSlots)
        session.cameraProductName = "FUJIFILM X-T5"
        session.identifiedModelID = "X-T5"
        session.serialHash = "abc123"
        session.transport = "usb"
        session.badgeShown = "Read & Write · unverified"
        session.completedSteps = [.intro, .connect, .confirmIdentity, .readSlots]
        session.identity = .init(confirmed: true)
        session.slotComparisons = [
            .init(slot: 2, name: "ACROS Street",
                  rows: [.init(field: "grain", label: "Grain Effect", appShowed: "Weak, Large",
                               differs: true, cameraShows: "Weak, Small")],
                  checkedAt: CameraCompatibilityReport.timestamp())
        ]
        session.freeText = "Dial was on C."
        session.profileHarvest = .init(state: .ran, detail: "601-byte profile, layout resolved at base 0x1FD")
        return session
    }

    func testASessionSurvivesASaveAndLoad() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        let session = sampleSession()
        GuidedTestStore.save(session)

        let loaded = try XCTUnwrap(GuidedTestStore.load())
        // Equal, dates included: timestamps are truncated to the whole second at the source, so
        // ISO 8601 — which has no sub-second component — decodes back to what was written.
        XCTAssertEqual(loaded, session)
        XCTAssertEqual(loaded.slotComparisons.first?.rows.first?.cameraShows, "Weak, Small")
        XCTAssertEqual(loaded.step, .compareSlots)
    }

    @MainActor
    func testStillBankConfirmationsSurviveResumeAndReportAsTesterEvidence() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        var session = GuidedTestSession.beginContinuous(step: .grainProbe)
        session.identifiedModelID = "X-M5"
        session.setStillBankConfirmation(1, confirmed: true)
        session.setStillBankConfirmation(3, confirmed: true)
        XCTAssertNotNil(GuidedTestStore.save(session))
        let loaded = try XCTUnwrap(GuidedTestStore.load())
        XCTAssertEqual(loaded.stillBankConfirmations, session.stillBankConfirmations)
        XCTAssertTrue(loaded.hasConfirmedStillBank(1))
        XCTAssertFalse(loaded.hasConfirmedStillBank(2))

        let record = CameraCompatibilityReport.GuidedTestRecord(session: loaded)
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CameraCompatibilityReport.GuidedTestRecord.self, from: encoded)
        XCTAssertEqual(decoded.stillBankConfirmations, loaded.stillBankConfirmations)
        let text = CameraCompatibilityReport.render(guidedTest: decoded, formatter: ISO8601DateFormatter()).joined(separator: "\n")
        XCTAssertTrue(text.contains("tester confirmed C1 assigned to STILL"))
        XCTAssertTrue(text.contains("tester confirmed C3 assigned to STILL"))
        XCTAssertTrue(text.contains("not detected by the app"))
    }

    @MainActor
    func testStartingOverArchivesProgressAndCreatesAFreshIntroduction() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        let previous = sampleSession()
        XCTAssertNotNil(GuidedTestStore.save(previous))
        let fresh = try GuidedTestStore.startOver(replacing: previous, facts: CameraFacts())
        XCTAssertNotEqual(fresh.id, previous.id)
        XCTAssertEqual(fresh.step, .intro)
        XCTAssertTrue(fresh.isContinuous)
        XCTAssertTrue(fresh.isLive)
        XCTAssertTrue(fresh.completedSteps.isEmpty)
        XCTAssertNil(fresh.identity)
        XCTAssertNil(fresh.freeText)
        XCTAssertNil(fresh.reportSnapshot)
        XCTAssertEqual(GuidedTestStore.load(), fresh)
        let archived = try XCTUnwrap(GuidedTestStore.loadHistory().first { $0.id == previous.id })
        XCTAssertEqual(archived.outcome, .abandoned)
        XCTAssertEqual(archived.slotComparisons, previous.slotComparisons)
        XCTAssertEqual(archived.freeText, previous.freeText)
    }

    @MainActor
    func testStartingOverWithPendingRecoveryOpensIntroForSavedAndCompletedTests() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        for outcome: GuidedTestSession.Outcome in [.inProgress, .completed] {
            var previous = GuidedTestSession.beginContinuous(step: outcome == .completed ? .send : .powerCycle)
            previous.outcome = outcome
            previous.recoveryBaselineID = previous.id
            let original = recovery(previous.id)
            XCTAssertTrue(GuidedRecoveryStore.create(original))
            XCTAssertTrue(GuidedRecoveryStore.markTouched(sessionID: previous.id, slot: 1))
            let pending = try XCTUnwrap(GuidedRecoveryStore.load(sessionID: previous.id))
            if previous.isLive { XCTAssertNotNil(GuidedTestStore.save(previous)) }
            else { XCTAssertTrue(GuidedTestStore.archive(previous)) }

            let fresh = try GuidedTestStore.startOver(replacing: previous, facts: CameraFacts())
            XCTAssertNotEqual(fresh.id, previous.id)
            XCTAssertEqual(fresh.step, .intro, "unresolved settings must not turn Start Over into Finish")
            XCTAssertNil(fresh.recoveryBaselineID)
            XCTAssertEqual(GuidedTestStore.load(), fresh)
            XCTAssertEqual(GuidedRecoveryStore.load(sessionID: previous.id), pending)
            XCTAssertTrue(GuidedRecoveryStore.unresolvedRecords().contains { $0.id == previous.id })
            let archived = try XCTUnwrap(GuidedTestStore.loadHistory().first { $0.id == previous.id })
            XCTAssertEqual(archived.outcome, outcome == .completed ? .completed : .abandoned)
        }
    }

    @MainActor
    func testStartingOverFromHistoryPreservesADifferentActiveTest() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        var finished = GuidedTestSession.beginContinuous(step: .send)
        finished.outcome = .completed
        XCTAssertTrue(GuidedTestStore.archive(finished))
        let active = sampleSession()
        XCTAssertNotNil(GuidedTestStore.save(active))

        let fresh = try GuidedTestStore.startOver(replacing: finished, facts: CameraFacts())
        XCTAssertEqual(GuidedTestStore.load()?.id, fresh.id)
        let archivedActive = try XCTUnwrap(GuidedTestStore.loadHistory().first { $0.id == active.id })
        XCTAssertEqual(archivedActive.slotComparisons, active.slotComparisons)
        XCTAssertEqual(archivedActive.outcome, .abandoned)
        XCTAssertEqual(GuidedTestStore.loadHistory().first { $0.id == finished.id }?.outcome, .completed)
    }

    @MainActor
    func testFailedStartOverKeepsTheOriginalLiveTest() throws {
        guard let historyURL = GuidedTestStore.historyURL else { throw XCTSkip("no App Group container in this test host") }
        let previous = sampleSession()
        XCTAssertNotNil(GuidedTestStore.save(previous))
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: historyURL) }
        XCTAssertThrowsError(try GuidedTestStore.startOver(replacing: previous, facts: CameraFacts()))
        XCTAssertEqual(GuidedTestStore.load(), previous)
    }

    /// A finished test is filed rather than dropped: the write pass's unlock is decided from it.
    func testArchivingClearsTheLiveSessionAndKeepsTheHistory() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        var session = sampleSession()
        session.outcome = .completed
        GuidedTestStore.save(session)

        GuidedTestStore.archive(session)
        XCTAssertNil(GuidedTestStore.load(), "it is no longer in progress")
        XCTAssertEqual(GuidedTestStore.loadHistory().count, 1)
        XCTAssertEqual(GuidedTestStore.loadHistory().first?.id, session.id)

        // Archiving the same session twice is one entry, not two — a tester tapping Send twice must
        // not look like two read passes.
        GuidedTestStore.archive(session)
        XCTAssertEqual(GuidedTestStore.loadHistory().count, 1)
    }

    func testTheHistoryIsBounded() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        for _ in 0..<(GuidedTestStore.maxHistory + 4) {
            var session = GuidedTestSession.begin(wave: 1, step: .send)
            session.outcome = .completed
            GuidedTestStore.archive(session)
        }
        XCTAssertEqual(GuidedTestStore.loadHistory().count, GuidedTestStore.maxHistory)
    }

    /// Clear Diagnostics promises to erase what a problem report draws on, and a guided test's
    /// answers are projected straight into that report.
    func testClearingErasesTheAnswersTooAndNotJustTheLiveSession() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        var finished = sampleSession()
        finished.outcome = .completed
        GuidedTestStore.archive(finished)
        GuidedTestStore.save(sampleSession())

        GuidedTestStore.deleteAll()
        XCTAssertNil(GuidedTestStore.load())
        XCTAssertTrue(GuidedTestStore.loadHistory().isEmpty)
    }

    /// The same trap the compatibility report has: a stored file written by the previous build must
    /// still decode, or a tester loses a half-finished test the moment they update the app.
    func testASessionMissingALaterFieldStillDecodes() throws {
        let minimal = """
        {
          "version": 1,
          "id": "6F1C",
          "wave": 1,
          "startedAt": "2026-09-14T10:02:11Z",
          "updatedAt": "2026-09-14T10:05:00Z",
          "step": "compareSlots",
          "completedSteps": ["intro", "connect"],
          "outcome": "inProgress",
          "slotComparisons": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(GuidedTestSession.self, from: Data(minimal.utf8))

        XCTAssertEqual(session.step, .compareSlots)
        XCTAssertNil(session.writePass)
        XCTAssertNil(session.identity)
        XCTAssertNil(session.stillBankConfirmations)
        XCTAssertFalse(session.hasConfirmedStillBank(1))
        XCTAssertTrue(session.isLive)
    }

    /// A session saved before the bank-condition questions existed carries no answers, and must
    /// decode to "not asked" rather than to JPEG, base ISO or a prepared slot.
    func testASessionFromBeforeTheConditionQuestionsDecodesToNotAsked() throws {
        let stored = """
        {
          "version": 2,
          "id": "6F1D",
          "wave": 1,
          "startedAt": "2026-10-01T10:02:11Z",
          "updatedAt": "2026-10-01T10:05:00Z",
          "step": "recheckSlot",
          "completedSteps": ["intro"],
          "outcome": "inProgress",
          "plan": { "version": 1, "optionalChecks": [] },
          "slotComparisons": [
            { "slot": 2, "rows": [], "fieldsAppCouldNotRead": [], "confirmedMatching": true }
          ],
          "writePass": {
            "trials": [ { "recipe": "priority", "recipeName": "CT Priority", "slot": 7, "wrote": {} } ],
            "currentTrial": 0,
            "restores": []
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(GuidedTestSession.self, from: Data(stored.utf8))

        XCTAssertNil(session.slotComparisons.first?.isoShown)
        XCTAssertNil(session.slotComparisons.first?.imageFormatShown)
        XCTAssertNil(session.writePass?.autoUpdateCustomSetting)
        XCTAssertNil(session.writePass?.trial?.preparation)
        XCTAssertNil(session.writePass?.trial?.preparationConfirmedAt)
    }

    func testAdvancingMarksTheStepBehindItAsDone() {
        var session = GuidedTestSession.begin(wave: 1, step: .intro)
        session.advance(to: .connect)
        session.advance(to: .confirmIdentity)
        XCTAssertEqual(session.completedSteps, [.intro, .connect])
        XCTAssertEqual(session.step, .confirmIdentity)

        // Going back and forward again doesn't double-count.
        session.advance(to: .connect)
        session.advance(to: .confirmIdentity)
        XCTAssertEqual(session.completedSteps, [.intro, .connect, .confirmIdentity])
    }

    func testFailedArchiveKeepsTheLiveSession() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        let session = sampleSession()
        XCTAssertNotNil(GuidedTestStore.save(session))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(GuidedTestStore.archive(session, at: directory), "a directory cannot be replaced with the archive file")
        XCTAssertEqual(GuidedTestStore.load()?.id, session.id)
    }

    func testArchivingAnOlderSessionCannotDeleteAnotherLiveTest() throws {
        try XCTSkipIf(GuidedTestStore.latestURL == nil, "no App Group container in this test host")
        let live = sampleSession()
        XCTAssertNotNil(GuidedTestStore.save(live))
        XCTAssertTrue(GuidedTestStore.archive(GuidedTestSession.beginContinuous()))
        XCTAssertEqual(GuidedTestStore.load()?.id, live.id)
    }

    private func recovery(_ sessionID: String = UUID().uuidString) -> GuidedRecoveryRecord {
        let backup = CameraBackup(capturedAt: CameraCompatibilityReport.timestamp(),
                                  camera: .init(productName: "FUJIFILM X-M5", modelID: "X-M5", serialHash: "original-body"),
                                  slots: [.init(index: 1, name: "Original", occupied: true, properties: ["0xD192": "0B00"]),
                                          .init(index: 2, occupied: false, properties: [:])])
        return .init(sessionID: sessionID, backup: backup, transport: "usb")
    }

    func testRecoveryIsImmutableAndSurvivesHistoryEvictionAndDiagnosticClearing() throws {
        try XCTSkipIf(GuidedRecoveryStore.directoryURL == nil, "no App Group container in this test host")
        let original = recovery()
        XCTAssertTrue(GuidedRecoveryStore.create(original))
        XCTAssertTrue(GuidedRecoveryStore.markTouched(sessionID: original.id, slot: 1))
        var changedBackup = original.backup
        changedBackup.slots[0].name = "CT Colour"
        XCTAssertFalse(GuidedRecoveryStore.create(.init(sessionID: original.id, backup: changedBackup, transport: "usb")))
        for _ in 0..<(GuidedTestStore.maxHistory + 2) {
            GuidedTestStore.archive(GuidedTestSession.beginContinuous())
        }
        GuidedTestStore.deleteAll()
        let loaded = try XCTUnwrap(GuidedRecoveryStore.load(sessionID: original.id))
        XCTAssertEqual(loaded.backup, original.backup)
        XCTAssertEqual(loaded.unresolvedSlots, [1])
        XCTAssertTrue(GuidedRecoveryStore.deleteAll(), "explicit recovery deletion remains possible")
        XCTAssertNil(GuidedRecoveryStore.load(sessionID: original.id))
    }

    func testOfferedCanceledAndPartialRestoreKeepRecoveryOutstanding() throws {
        try XCTSkipIf(GuidedRecoveryStore.directoryURL == nil, "no App Group container in this test host")
        let original = recovery()
        XCTAssertTrue(GuidedRecoveryStore.create(original))
        XCTAssertTrue(GuidedRecoveryStore.markTouched(sessionID: original.id, slot: 1))
        for disposition in ["offered", "canceled", "running", "partiallyApplied", "failed", "couldNotVerify"] {
            XCTAssertTrue(GuidedRecoveryStore.recordDisposition(sessionID: original.id, slot: 1,
                                                                outcome: RestoreDisposition(rawValue: disposition)))
            XCTAssertEqual(GuidedRecoveryStore.load(sessionID: original.id)?.unresolvedSlots, [1])
        }
        XCTAssertTrue(GuidedRecoveryStore.recordDisposition(sessionID: original.id, slot: 1, outcome: .restored))
        XCTAssertEqual(GuidedRecoveryStore.load(sessionID: original.id)?.unresolvedSlots, [])
        XCTAssertTrue(GuidedRecoveryStore.markTouched(sessionID: original.id, slot: 1))
        XCTAssertEqual(GuidedRecoveryStore.load(sessionID: original.id)?.unresolvedSlots, [1], "a later trial reopens cleanup")
    }

    func testEmptyOriginalAndPhysicalIdentityUncertaintySurviveStorage() throws {
        try XCTSkipIf(GuidedRecoveryStore.directoryURL == nil, "no App Group container in this test host")
        let original = recovery()
        XCTAssertTrue(GuidedRecoveryStore.create(original))
        let loaded = try XCTUnwrap(GuidedRecoveryStore.load(sessionID: original.id))
        XCTAssertFalse(try XCTUnwrap(loaded.backup.slots.first { $0.index == 2 }).occupied)
        XCTAssertNil(loaded.backup.properties(forSlot: 2))
        var facts = CameraFacts(isConnected: true, transport: "usb", productName: "FUJIFILM X-M5", serialHash: "original-body")
        XCTAssertTrue(loaded.matches(facts))
        facts.serialHash = "other-body"
        XCTAssertFalse(loaded.matches(facts))
        facts.serialHash = nil
        XCTAssertFalse(loaded.matches(facts), "a known serial cannot become a name-only match")
    }
}
