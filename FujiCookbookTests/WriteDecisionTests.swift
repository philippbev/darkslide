import XCTest
@testable import FujiCookbook

/// `WriteDecision` is the one producer of a write permission. These pin what it grants and refuses
/// for each way a product name can resolve and each way a slot read can end, without a camera.
///
/// The walk's order is the record's for a new body (zgrimz/fujifilm-ptp-reference
/// `docs/08-methods.md#minimum-evidence-for-a-new-body`, `docs/04-custom-slots.md#verifying-a-write`).
@MainActor
final class WriteDecisionTests: XCTestCase {
    private let registry = CameraModelRegistry.shared

    private func decide(_ identification: ModelIdentification,
                        observed: ObservedCapabilities = ObservedCapabilities(),
                        firmware: String? = "1.00", serialHash: String? = "0123456789abcdef") -> WriteAccess {
        WriteDecision.decide(identification: identification, observed: observed,
                             firmwareVersion: firmware, serialHash: serialHash)
    }

    private func identify(_ productName: String) -> ModelIdentification {
        registry.identify(productName: productName)
    }

    /// A slot read as a clean walk leaves it, with the knob each refusal turns.
    private func walked(selector: SelectorRead = .value(1), banks: Int = 7, allRead: Bool = true,
                        restored: Bool? = true) -> ObservedCapabilities {
        ObservedCapabilities(slotRead: WalkResult(selector: selector, walk: .finished(banks: banks, allRead: allRead),
                                                  selectorRestored: restored))
    }

    private func read(_ walk: WalkEvidence, selector: SelectorRead = .value(1),
                      restored: Bool? = nil) -> ObservedCapabilities {
        ObservedCapabilities(slotRead: WalkResult(selector: selector, walk: walk, selectorRestored: restored))
    }

    private func permission(_ access: WriteAccess, file: StaticString = #filePath,
                            line: UInt = #line) -> WritePermission? {
        guard case .granted(let permission) = access else {
            XCTFail("expected a granted permission, got \(access)", file: file, line: line)
            return nil
        }
        return permission
    }

    private func refusal(_ access: WriteAccess, file: StaticString = #filePath,
                         line: UInt = #line) -> WriteRefusal? {
        guard case .refused(let refusal) = access else {
            XCTFail("expected a refusal, got \(access)", file: file, line: line)
            return nil
        }
        return refusal
    }

    // MARK: Trusted entries: the registry's word, before any slot read

    func testAHardwareVerifiedEntryIsGrantedVerifiedAndNamesTheBody() throws {
        let granted = try XCTUnwrap(permission(decide(identify("FUJIFILM X-T50"), firmware: "1.32",
                                                      serialHash: "feedface01234567")))
        XCTAssertEqual(granted.stage, .verified)
        XCTAssertEqual(granted.grounds, .trustedEntry(.hardware))
        XCTAssertEqual(granted.firmwareVersion, "1.32")
        XCTAssertEqual(granted.serialHash, "feedface01234567")
    }

    func testAnOwnerReportEntryIsGrantedVerified() throws {
        let granted = try XCTUnwrap(permission(decide(identify("FUJIFILM GFX100S"))))
        XCTAssertEqual(granted.stage, .verified)
        XCTAssertEqual(granted.grounds, .trustedEntry(.ownerReport))
    }

    func testACommunityEntryIsGrantedUnverified() throws {
        let granted = try XCTUnwrap(permission(decide(identify("FUJIFILM X-T5"))))
        XCTAssertEqual(granted.stage, .unverified)
        XCTAssertEqual(granted.grounds, .trustedEntry(.community))
    }

    func testAnInferredEntryIsGrantedUnverified() throws {
        let granted = try XCTUnwrap(permission(decide(identify("FUJIFILM X-T4"))))
        XCTAssertEqual(granted.stage, .unverified)
        XCTAssertEqual(granted.grounds, .trustedEntry(.inferred))
    }

    func testTheDemoModelIsGrantedVerified() throws {
        let granted = try XCTUnwrap(permission(decide(.exact(registry.demoModel), firmware: nil, serialHash: nil)))
        XCTAssertEqual(granted.stage, .verified)
        XCTAssertNil(granted.firmwareVersion)
        XCTAssertNil(granted.serialHash)
    }

    func testABlockedEntryIsRefusedInItsOwnWords() throws {
        let xPro3 = try XCTUnwrap(registry.model(withID: "X-Pro3"))
        let reason = try XCTUnwrap(xPro3.writeSupport.blockReason)
        XCTAssertEqual(decide(identify("FUJIFILM X-Pro3")), .refused(.blockedByRecord(reason: reason)))
        XCTAssertEqual(WriteRefusal.blockedByRecord(reason: reason).reason(productName: "FUJIFILM X-Pro3"), reason)
    }

    // MARK: Untested entries: decided by the walk, in the record's order

    func testAnUntestedEntryIsUndecidedUntilItsSlotReadEnds() throws {
        let gfx100II = try XCTUnwrap(registry.model(withID: "GFX100 II"))
        XCTAssertEqual(gfx100II.writeSupport, .untested, "precondition")
        XCTAssertEqual(decide(identify("FUJIFILM GFX100 II")), .undecided)
    }

    func testAnUntestedEntryIsGrantedByACleanWalk() throws {
        let granted = try XCTUnwrap(permission(decide(identify("FUJIFILM GFX100 II"), observed: walked(),
                                                      firmware: "2.00", serialHash: "cafe")))
        XCTAssertEqual(granted.stage, .unverified)
        XCTAssertEqual(granted.grounds, .walk)
        XCTAssertEqual(granted.firmwareVersion, "2.00")
        XCTAssertEqual(granted.serialHash, "cafe")
    }

    func testASelectorAnsweringUnsupportedRefusesForWantOfABankBlock() throws {
        let access = decide(identify("FUJIFILM X-H1"), observed: read(.sweptReadOnly, selector: .unsupported))
        XCTAssertEqual(access, .refused(.noBankBlock))
        XCTAssertTrue(try XCTUnwrap(refusal(access)).reason(productName: "FUJIFILM X-H1").contains("0x200A"))
    }

    func testASelectorReadThatFailsRefusesAsUnreadable() {
        let access = decide(identify("FUJIFILM GFX100 II"), observed: read(.sweptReadOnly, selector: .failed("timed out")))
        XCTAssertEqual(access, .refused(.selectorUnreadable(detail: "timed out")))
    }

    func testAWalkThatFailsRefuses() {
        let access = decide(identify("FUJIFILM GFX100 II"), observed: read(.failed("C1 select refused")))
        XCTAssertEqual(access, .refused(.walkFailed(detail: "C1 select refused")))
    }

    func testAnIgnoredSelectRefusesNamingTheBank() throws {
        let access = decide(identify("FUJIFILM GFX100 II"), observed: read(.stopped(selectIgnoredAt: 2), restored: true))
        XCTAssertEqual(access, .refused(.selectIgnored(bank: 2)))
        XCTAssertTrue(try XCTUnwrap(refusal(access)).reason(productName: "FUJIFILM GFX100 II").contains("C2"))
    }

    func testAWalkThatSelectedNoBankRefuses() {
        XCTAssertEqual(decide(identify("FUJIFILM GFX100 II"), observed: walked(banks: 0)), .refused(.noBanks))
    }

    func testABankThatDidNotAnswerEveryPropertyRefuses() throws {
        let access = decide(identify("FUJIFILM GFX100 II"), observed: walked(allRead: false))
        guard case .walkFailed = try XCTUnwrap(refusal(access)) else { return XCTFail("got \(access)") }
    }

    func testASelectorThatDidNotGoBackRefuses() {
        XCTAssertEqual(decide(identify("FUJIFILM GFX100 II"), observed: walked(restored: false)),
                       .refused(.selectorNotRestored))
        XCTAssertEqual(decide(identify("FUJIFILM GFX100 II"), observed: walked(restored: nil)),
                       .refused(.selectorNotRestored), "an outcome that isn't known refuses")
    }

    // MARK: Guesses and unlisted bodies

    func testAGuessAtAWritableEntryIsUndecidedThenGrantedByItsWalk() throws {
        let guess = identify("FUJIFILM X-T50 TETHER")
        XCTAssertEqual(guess.confidence, "heuristic", "precondition")
        XCTAssertEqual(decide(guess), .undecided, "the X-T50's hardware verification doesn't carry to a guess")
        let granted = try XCTUnwrap(permission(decide(guess, observed: walked())))
        XCTAssertEqual(granted.grounds, .walk)
        XCTAssertEqual(granted.stage, .unverified)
    }

    func testAGuessAtABlockedEntryKeepsTheBlock() throws {
        let guess = identify("FUJIFILM X-Pro3 TETHER")
        XCTAssertEqual(guess.model?.id, "X-Pro3", "precondition")
        let reason = try XCTUnwrap(guess.model?.writeSupport.blockReason)
        XCTAssertEqual(decide(guess, observed: walked()), .refused(.blockedByRecord(reason: reason)),
                       "a name that contains the X-Pro3's is most likely an X-Pro3")
    }

    func testAnUnlistedBodyIsDecidedByItsWalk() throws {
        let unlisted = ModelIdentification.unlisted(provisional: registry.provisionalModel(productName: "FUJIFILM X-T99"))
        XCTAssertEqual(decide(unlisted), .undecided)
        let granted = try XCTUnwrap(permission(decide(unlisted, observed: walked())))
        XCTAssertEqual(granted.grounds, .walk)
        XCTAssertEqual(granted.stage, .unverified)
        XCTAssertEqual(decide(unlisted, observed: read(.sweptReadOnly, selector: .unsupported)), .refused(.noBankBlock))
    }

    func testTheProvisionalModelIsAPlaceholderForFieldKnowledgeOnly() throws {
        let provisional = registry.provisionalModel(productName: "FUJIFILM X-T99")
        XCTAssertEqual(provisional.id, CameraModelRegistry.unlistedModelID)
        XCTAssertEqual(provisional.displayName, "FUJIFILM X-T99")
        XCTAssertEqual(provisional.writeSupport, .untested)
        XCTAssertEqual(provisional.verification, .inferred)
        XCTAssertTrue(provisional.supportsSlotNaming)
        XCTAssertFalse(provisional.supportsRawConversion, "RAW conversion keeps its own gate")
        XCTAssertEqual(provisional.slotCount, 7)
        XCTAssertTrue(provisional.supportsSlotProtocol)
        let xt50 = try XCTUnwrap(registry.model(withID: "X-T50"))
        XCTAssertEqual(provisional.supportedFields, xt50.supportedFields, "the newest generation's fields")
        XCTAssertEqual(provisional.supportedFilmSimulations, xt50.supportedFilmSimulations)

        let identification = ModelIdentification.unlisted(provisional: provisional)
        XCTAssertNotNil(identification.model, "field knowledge for the codec")
        XCTAssertNil(identification.registryModel, "and nothing to persist or compare by")
        XCTAssertFalse(identification.isTrusted)
        XCTAssertFalse(identification.isGuess)
        XCTAssertTrue(identification.isUnlisted)
        XCTAssertEqual(identification.reportLabel, "unlisted")
        XCTAssertEqual(identification.confidence, "unlisted")
    }

    func testABodyNothingNamesIsRefusedForWantOfIdentity() throws {
        let access = decide(.unknown, observed: walked())
        XCTAssertEqual(access, .refused(.noIdentity), "not even a clean walk stands in for an identity")
        XCTAssertTrue(try XCTUnwrap(refusal(access)).reason(productName: "FUJIFILM X-T99").contains("didn't identify itself"))
    }
}
