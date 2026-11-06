import XCTest
@testable import FujiCookbook

/// The first push to a body no push has been read back on writes one setting and reads it back
/// before the rest; a clean push marks the body verified for the session. Asserted on the traffic
/// the mock recorded and on what its slots hold, not on log text.
///
/// The staging is app policy (`StagedWrite`). Camera facts in these tests are from
/// zgrimz/fujifilm-ptp-reference: `docs/01-transport.md#response-codes`,
/// `docs/04-custom-slots.md#why-a-write-is-refused`, `docs/04-custom-slots.md#verifying-a-write`.
@MainActor
final class StagedFirstWriteTests: XCTestCase {

    private let filmSimulation = FujiPTP.PresetProp.filmSimulation.rawValue

    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    private func connect(_ faults: MockCameraFaults) async -> (CameraServices, MockCameraTransport) {
        var faults = faults
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        return (manager, transport)
    }

    /// Film simulation and sharpness both differ from the mock's seeded C1.
    private var recipe: RecipeSettings {
        RecipeSettings(filmSimulation: .classicNeg,
                       grain: GrainEffect(strength: .weak, size: .large),
                       whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 2, shiftBlue: -3, kelvin: nil),
                       dynamicRange: .dr400, highlightTone: -0.5, shadowTone: 1.0, color: 2, sharpness: -1)
    }

    /// Every property write in the trace, in order, as the property codes written. Slot selects are
    /// left out: they say where, not what.
    private func propertyWrites(_ m: CameraServices) -> [String] {
        (m.reports.report?.transactions ?? [])
            .filter { $0.operation == "0x1016" && $0.parameters.first != "0xD18C" }
            .compactMap { $0.parameters.first }
    }

    /// The transaction right after the first write of `code`.
    private func transactionAfterFirstWrite(of code: String, _ m: CameraServices) -> PTPTransaction? {
        let transactions = m.reports.report?.transactions ?? []
        guard let index = transactions.firstIndex(where: { $0.operation == "0x1016" && $0.parameters.first == code }),
              index + 1 < transactions.count else { return nil }
        return transactions[index + 1]
    }

    private func stage(_ m: CameraServices) -> WritePermission.Stage? {
        guard case .granted(let permission) = m.session.connected?.writeAccess else { return nil }
        return permission.stage
    }

    private func heldFilmSimulation(_ t: MockCameraTransport, slot: Int) async -> FilmSimulation? {
        await t.storedProperty(filmSimulation, slot: slot)
            .flatMap(FujiEncoding.decodeInt16).flatMap { FujiEncoding.byteToFilmSim[$0] }
    }

    // MARK: Which pushes stage

    func testTheFirstPushToAnUnlistedBodyWritesOneSettingReadsItBackThenTheRest() async throws {
        let (m, t) = await connect(.unlistedBody)
        XCTAssertEqual(stage(m), .unverified, "precondition")
        XCTAssertEqual(m.session.connected?.capabilityBadge.text, "Read & Write · not yet tested", "precondition")

        let result = await m.slotWriter.push(settings: recipe, name: "Staged", toSlot: 1)

        XCTAssertEqual(result.outcome, .applied, result.errorMessage ?? "")
        XCTAssertEqual(result.firstWrite, .written(property: filmSimulation))
        let writes = propertyWrites(m)
        XCTAssertEqual(writes.first, "0xD192", "film simulation first, before the name")
        XCTAssertEqual(writes.dropFirst().first, "0xD18D", "then the name, then the rest as any push")
        XCTAssertEqual(writes.filter { $0 == "0xD192" }.count, 1, "the staged property is not written twice")
        let readBack = transactionAfterFirstWrite(of: "0xD192", m)
        XCTAssertEqual(readBack?.operation, "0x1015")
        XCTAssertEqual(readBack?.parameters.first, "0xD192", "read back on its own before anything else")
        let held = await heldFilmSimulation(t, slot: 1)
        XCTAssertEqual(held, .classicNeg)
        XCTAssertEqual(stage(m), .verified, "a clean push marks the body verified for the session")
        XCTAssertEqual(m.session.connected?.capabilityBadge.text, "Read & Write", "and the caveat clears with the stage")
        XCTAssertEqual(m.session.connected?.observed.firstWrite, .written(property: filmSimulation))
    }

    func testTheNextPushInTheSessionIsNotStaged() async {
        let (m, _) = await connect(.unlistedBody)
        _ = await m.slotWriter.push(settings: recipe, name: "First", toSlot: 1)
        XCTAssertEqual(stage(m), .verified, "precondition")
        let before = propertyWrites(m).count

        let second = await m.slotWriter.push(settings: RecipeSettings(filmSimulation: .velvia), name: "Second", toSlot: 1)

        XCTAssertEqual(second.outcome, .applied)
        XCTAssertNil(second.firstWrite)
        XCTAssertEqual(propertyWrites(m).dropFirst(before).first, "0xD18D", "the name leads, as on any unstaged push")
    }

    func testAHardwareVerifiedBodyIsNeverStaged() async {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-T50", firmwareVersion: "1.32"))
        XCTAssertEqual(stage(m), .verified, "precondition")
        let result = await m.slotWriter.push(settings: recipe, name: "X-T50", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertNil(result.firstWrite)
        XCTAssertEqual(propertyWrites(m).first, "0xD18D")
    }

    func testACommunityEntryIsStagedOnItsFirstPush() async {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-T5", firmwareVersion: "4.20"))
        XCTAssertEqual(stage(m), .unverified, "precondition: a published record, no push read back here")
        let result = await m.slotWriter.push(settings: recipe, name: "X-T5", toSlot: 1)
        XCTAssertEqual(result.firstWrite, .written(property: filmSimulation))
        XCTAssertEqual(stage(m), .verified)
    }

    func testARestoreIsNeverStagedAndNeverPromotes() async throws {
        let (m, _) = await connect(.unlistedBody)
        let backup = try XCTUnwrap(m.slotReader.slotBackup)
        let saved = try XCTUnwrap(backup.slots.first { $0.index == 1 })
        var bytes: [UInt16: Data] = [:]
        for (code, hex) in saved.properties {
            if let value = UInt16(code.dropFirst(2), radix: 16) { bytes[value] = Data(hexString: hex) }
        }
        let result = await m.slotWriter.restore(bytes, name: saved.name ?? "", toSlot: 1)
        XCTAssertNil(result.firstWrite)
        XCTAssertEqual(stage(m), .unverified, "a restore replays the body's own bytes; it proves nothing")
    }

    func testARecipeThatChangesNeitherCandidateRunsUnstagedAndStillVerifies() async throws {
        let (m, t) = await connect(.unlistedBody)
        let heldNow = await heldFilmSimulation(t, slot: 1)
        let held = try XCTUnwrap(heldNow, "precondition: C1 holds a film simulation")
        // Sharpness is encoded in tenths (`FujiPresetCodec`), and a recipe that leaves it unset still
        // writes a default, so the recipe carries the value C1 holds.
        let heldSharpness = await t.storedProperty(FujiPTP.PresetProp.sharpness.rawValue, slot: 1)
            .flatMap(FujiEncoding.decodeInt16).map { Int($0) / 10 }
        let sharpness = try XCTUnwrap(heldSharpness, "precondition: C1 holds a sharpness")
        let unchanged = RecipeSettings(filmSimulation: held, grain: GrainEffect(strength: .weak, size: .large),
                                       sharpness: sharpness)

        let result = await m.slotWriter.push(settings: unchanged, name: "Same", toSlot: 1)

        XCTAssertEqual(result.outcome, .applied, result.errorMessage ?? "")
        XCTAssertNil(result.firstWrite, "nothing to stage")
        XCTAssertEqual(propertyWrites(m).first, "0xD18D")
        XCTAssertEqual(stage(m), .verified, "every write was read back, which is what verifies")
    }

    // MARK: Stage one's stops

    func testStageOneRefusedAsUnsupportedStopsThePushWithNothingElseWritten() async {
        var faults = MockCameraFaults.unlistedBody
        faults.unsupportedWriteCodes = [filmSimulation]
        let (m, t) = await connect(faults)
        let before = await heldFilmSimulation(t, slot: 1)

        let result = await m.slotWriter.push(settings: recipe, name: "Refused", toSlot: 1)

        XCTAssertEqual(result.outcome, .notWritten)
        XCTAssertEqual(result.firstWrite, .refused(property: filmSimulation, code: 0x200A, restore: .unchanged))
        XCTAssertFalse(result.nameWritten)
        XCTAssertEqual(propertyWrites(m), ["0xD192"], "the one refused write, and nothing after it")
        let after = await heldFilmSimulation(t, slot: 1)
        XCTAssertEqual(after, before, "the bank is as it was")
        XCTAssertEqual(stage(m), .unverified)
        XCTAssertTrue(result.errorMessage?.contains("refused the first setting") ?? false, result.errorMessage ?? "nil")
        XCTAssertEqual(m.session.connected?.observed.firstWrite, result.firstWrite)
    }

    func testStageOneRefusedAsInvalidValueCarriesOnLikeAnyRefusal() async {
        var faults = MockCameraFaults.unlistedBody
        faults.invalidValueWriteCodes = [filmSimulation]
        let (m, _) = await connect(faults)

        let result = await m.slotWriter.push(settings: recipe, name: "Invalid", toSlot: 1)

        XCTAssertEqual(result.firstWrite, .invalidValue(property: filmSimulation, code: 0x201C))
        XCTAssertTrue(result.nameWritten, "the push went on")
        XCTAssertEqual(result.outcome, .partiallyApplied, "the film simulation was refused, the rest landed")
        XCTAssertGreaterThan(propertyWrites(m).count, 2)
        XCTAssertEqual(stage(m), .verified, "a refusal says nothing against the bank path; every accepted write was held")
    }

    func testStageOneAcceptedButNotHeldStopsAndLeavesTheBankAsItWas() async {
        var faults = MockCameraFaults.unlistedBody
        faults.silentlyIgnoredWriteCodes = [filmSimulation]
        let (m, t) = await connect(faults)
        let before = await heldFilmSimulation(t, slot: 1)

        let result = await m.slotWriter.push(settings: recipe, name: "Ignored", toSlot: 1)

        guard case .mismatched(let property, _, let restore) = result.firstWrite else {
            return XCTFail("expected a mismatch, got \(String(describing: result.firstWrite))")
        }
        XCTAssertEqual(property, filmSimulation)
        XCTAssertEqual(restore, .unchanged, "the read after the stop matched the recovery copy, so nothing was written back")
        XCTAssertEqual(result.outcome, .notWritten)
        XCTAssertFalse(result.nameWritten)
        XCTAssertEqual(propertyWrites(m), ["0xD192"])
        let after = await heldFilmSimulation(t, slot: 1)
        XCTAssertEqual(after, before)
        XCTAssertEqual(stage(m), .unverified)
    }

    func testStageOneAcceptedAndChangedIsPutBackFromTheRecoveryCopy() async throws {
        let (m, t) = await connect(.unlistedBody)
        let heldBefore = await heldFilmSimulation(t, slot: 1)
        let before = try XCTUnwrap(heldBefore)
        // The push reads the film simulation twice before deciding: the recovery copy, then the
        // staged read-back. The second answers a value the write didn't send.
        await t.queueRead(.normal, for: filmSimulation)
        await t.queueRead(.value(FujiEncoding.packU16(5)), for: filmSimulation)

        let result = await m.slotWriter.push(settings: recipe, name: "Changed", toSlot: 1)

        XCTAssertEqual(result.firstWrite,
                       .mismatched(property: filmSimulation, read: FujiEncoding.packU16(5), restore: .restored))
        XCTAssertEqual(result.outcome, .notWritten, "put back and confirmed, so the bank is as it was")
        let after = await heldFilmSimulation(t, slot: 1)
        XCTAssertEqual(after, before, "the recovery copy's value is back on the camera")
        XCTAssertEqual(propertyWrites(m), ["0xD192", "0xD192"], "the staged write and the write back, nothing else")
        XCTAssertEqual(stage(m), .unverified)
    }

    func testStageOneWithNoResponseStopsAsUnknown() async {
        var faults = MockCameraFaults.unlistedBody
        faults.lostWriteResponseCodes = [filmSimulation]
        let (m, _) = await connect(faults)

        let result = await m.slotWriter.push(settings: recipe, name: "Lost", toSlot: 1)

        XCTAssertEqual(result.outcome, .unknown, "a lost response is not a refusal")
        guard case .unknown(let property, let restore) = result.firstWrite else {
            return XCTFail("expected an unknown outcome, got \(String(describing: result.firstWrite))")
        }
        XCTAssertEqual(property, filmSimulation)
        XCTAssertEqual(restore, .restoreUnknown, "the write back drew no response either; recorded apart from the stop")
        XCTAssertFalse(result.nameWritten)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(stage(m), .unverified)
    }

    // MARK: The pure rules

    func testPickPrefersFilmSimulationThenSharpnessAndSkipsUnchangedValues() {
        let sim = FujiPTP.PresetProp.filmSimulation.rawValue
        let sharp = FujiPTP.PresetProp.sharpness.rawValue
        let encoded: [(code: UInt16, bytes: Data)] = [(0xD18E, Data([7, 0])), (sim, Data([0x11, 0])), (sharp, Data([0xF6, 0xFF]))]
        XCTAssertEqual(StagedWrite.pick(encoded: encoded, base: [sim: Data([1, 0]), sharp: Data([0, 0])])?.code, sim)
        XCTAssertEqual(StagedWrite.pick(encoded: encoded, base: [sim: Data([0x11, 0]), sharp: Data([0, 0])])?.code, sharp,
                       "film simulation unchanged, so sharpness")
        XCTAssertNil(StagedWrite.pick(encoded: encoded, base: [sim: Data([0x11, 0]), sharp: Data([0xF6, 0xFF])]),
                     "neither differs: unstaged")
        XCTAssertNil(StagedWrite.pick(encoded: [(0xD18E, Data([7, 0]))], base: [:]), "neither candidate is written")
    }

    func testProvesBankPathNeedsEveryAcceptedWriteHeld() {
        func result(_ outcomes: [FieldOutcome], name: FieldOutcome? = .written) -> SlotWriteResult {
            var result = SlotWriteResult(slot: 1, outcome: .applied, nameWritten: name != nil, nameApplied: nil,
                                         clampedFields: [], fields: [], errorMessage: nil)
            result.fields = outcomes.enumerated().map { index, outcome in
                FieldResult(code: 0xD190 + UInt16(index), field: "p\(index)", isRecipeField: true, outcome: outcome)
            }
            result.nameOutcome = name
            return result
        }
        XCTAssertTrue(StagedWrite.provesBankPath(result([.written, .written])))
        XCTAssertTrue(StagedWrite.provesBankPath(result([.written, .rejected(code: 0x200A)])), "a refusal says nothing against the path")
        XCTAssertTrue(StagedWrite.provesBankPath(result([.written], name: .rejected(code: 0x200A))))
        XCTAssertTrue(StagedWrite.provesBankPath(result([.written], name: nil)), "a body without naming")
        XCTAssertFalse(StagedWrite.provesBankPath(result([.written, .mismatched(wrote: Data([1, 0]), read: Data([2, 0]))])))
        XCTAssertFalse(StagedWrite.provesBankPath(result([.written, .outcomeUnknown])))
        XCTAssertFalse(StagedWrite.provesBankPath(result([.written, .unverified])))
        XCTAssertFalse(StagedWrite.provesBankPath(result([.written], name: .mismatched(wrote: Data(), read: nil))))
        XCTAssertFalse(StagedWrite.provesBankPath(result([.rejected(code: 0x201C)])), "nothing landed")
        var preflightOnly = result([.written])
        preflightOnly.fields.append(FieldResult(code: 0, field: "Clarity", isRecipeField: true, outcome: .rejected(code: nil)))
        XCTAssertTrue(StagedWrite.provesBankPath(preflightOnly), "a pre-flight entry never reached the camera")
    }
}

private extension Data {
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex, let next = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex) {
            if let byte = UInt8(hexString[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        self.init(bytes)
    }
}
