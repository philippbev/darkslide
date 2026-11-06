import XCTest
@testable import FujiCookbook

/// Write access decided from what the body answers at connect, end to end on the mock: an unlisted
/// body is named by `GetDeviceInfo`, walked on a provisional model and granted; a body nothing names
/// is refused; a body the registry blocks stays refused in the registry's words; a trusted entry is
/// granted on the registry's word.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/01-transport.md#response-codes`, `docs/07-cameras.md#x-t20`, `docs/08-methods.md#minimum-evidence-for-a-new-body`.
@MainActor
final class WriteEnablementTests: XCTestCase {

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

    private var recipe: RecipeSettings {
        RecipeSettings(filmSimulation: .classicNeg,
                       grain: GrainEffect(strength: .weak, size: .large),
                       whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 2, shiftBlue: -3, kelvin: nil),
                       dynamicRange: .dr400, highlightTone: -0.5, shadowTone: 1.0, color: 2, sharpness: -1)
    }

    /// The film simulation C`slot` physically holds, read straight off the transport.
    private func filmSimulation(_ transport: MockCameraTransport, slot: Int) async throws -> FilmSimulation? {
        try await transport.writeProperty(FujiPTP.Prop.slotSelector, FujiEncoding.packU16(slot))
        return try await transport.readProperty(FujiPTP.PresetProp.filmSimulation.rawValue)
            .flatMap(FujiEncoding.decodeInt16).flatMap { FujiEncoding.byteToFilmSim[$0] }
    }

    private func granted(_ m: CameraServices, file: StaticString = #filePath, line: UInt = #line) -> WritePermission? {
        guard case .granted(let permission) = m.session.connected?.writeAccess else {
            XCTFail("expected a granted permission, got \(String(describing: m.session.connected?.writeAccess))",
                    file: file, line: line)
            return nil
        }
        return permission
    }

    // MARK: Unlisted bodies

    func testAnUnlistedBodyIsNamedWalkedAndGranted() async throws {
        let (m, _) = await connect(.unlistedBody)
        let connected = try XCTUnwrap(m.session.connected)
        XCTAssertEqual(connected.identification.confidence, "unlisted")
        XCTAssertEqual(connected.model?.id, CameraModelRegistry.unlistedModelID)
        XCTAssertEqual(connected.model?.displayName, "FUJIFILM X-T99")
        XCTAssertNil(connected.registryModel, "a provisional model is nothing to persist by")
        let permission = try XCTUnwrap(granted(m))
        XCTAssertEqual(permission.grounds, .walk)
        XCTAssertEqual(permission.stage, .unverified)
        XCTAssertEqual(permission.firmwareVersion, "1.00")
        XCTAssertEqual(permission.serialHash, m.reports.report?.camera.serialHash, "the body the permission names")
        XCTAssertEqual(m.slotReader.slots.count, 7)
        XCTAssertTrue(m.session.canPush)
        XCTAssertEqual(connected.capabilityBadge.text, "Read & Write · not yet tested")
        XCTAssertEqual(connected.pushCaveat, WritePermission.Grounds.walk.pushCaveat,
                       "a body granted on its own answers says so before a push")
        XCTAssertEqual(connected.testerNote, WritePermission.Grounds.walk.testerNote)
        XCTAssertFalse(connected.isUnsupported)
        let report = try XCTUnwrap(m.reports.report)
        XCTAssertEqual(report.camera.identification, "unlisted")
        XCTAssertNil(report.camera.identifiedModelID)
        XCTAssertEqual(report.slots.assumedSlotCount, 7, "the provisional model's assumption, for the walk to correct")
        XCTAssertEqual(report.slots.probedSlotCount, 7)
        XCTAssertTrue(report.notes.contains { $0.hasPrefix("unlisted body:") }, report.notes.joined(separator: "\n"))
    }

    func testAnUnlistedBodyTakesARecipe() async throws {
        let (m, t) = await connect(.unlistedBody)
        let result = await m.slotWriter.push(settings: recipe, name: "Unlisted", toSlot: 1)
        XCTAssertEqual(result.outcome, .applied, result.errorMessage ?? "")
        let held = try await filmSimulation(t, slot: 1)
        XCTAssertEqual(held, .classicNeg)
        XCTAssertNil(m.reports.report?.pushes?.first?.modelID, "no registry id to record")
    }

    func testTwoUnlistedBodiesShareNoPersistedId() async throws {
        let (a, _) = await connect(.unlistedBody)
        let backupA = try XCTUnwrap(a.slotReader.slotBackup)
        XCTAssertNil(backupA.camera.modelID)
        XCTAssertEqual(backupA.camera.productName, "FUJIFILM X-T99")
        let slot = try XCTUnwrap(a.slotReader.slots.first { $0.isOccupied })
        XCTAssertNil(a.slotReader.portableRecipe(for: slot)?.authoredForModel)

        let (b, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-E7", firmwareVersion: "1.00"))
        let backupB = try XCTUnwrap(b.slotReader.slotBackup)
        XCTAssertNil(backupB.camera.modelID)
        XCTAssertNotEqual(backupA.camera.productName, backupB.camera.productName,
                          "the product name, not a shared placeholder id, is what tells them apart")
    }

    func testABodyNothingNamesIsRefusedAndSwept() async throws {
        let (m, t) = await connect(.unknownBody)
        let connected = try XCTUnwrap(m.session.connected)
        XCTAssertEqual(connected.identification.confidence, "unknown")
        XCTAssertEqual(connected.writeAccess, .refused(.noIdentity))
        XCTAssertTrue(connected.isUnsupported)
        XCTAssertFalse(m.session.canPush)
        XCTAssertTrue(m.session.pushBlockReason?.contains("didn't identify itself") ?? false, m.session.pushBlockReason ?? "nil")
        XCTAssertEqual(connected.capabilityBadge.text, "Unrecognized model — writes blocked")
        let writes = await t.totalWriteCount
        XCTAssertEqual(writes, 0)
    }

    // MARK: Listed bodies

    func testABlockedBodyIsRefusedInTheRegistrysWords() async throws {
        let (m, _) = await connect(.noSlotProtocolBody)
        let connected = try XCTUnwrap(m.session.connected)
        let reason = try XCTUnwrap(connected.model?.writeSupport.blockReason)
        XCTAssertEqual(connected.writeAccess, .refused(.blockedByRecord(reason: reason)))
        XCTAssertEqual(connected.capabilityBadge.text, "Read-only · no USB slots")
        XCTAssertNil(connected.pushCaveat, "nothing to say about writing to a body that isn't written to")
        XCTAssertNil(connected.testerNote)
        XCTAssertTrue(connected.slotsUnreachable)
        XCTAssertFalse(connected.isUnsupported, "a listed body is explained, not called unsupported")
    }

    func testAnUntestedBodyWhoseSlotsAnswerIsGranted() async throws {
        let (m, _) = await connect(.readOnlyWithSlots)
        let permission = try XCTUnwrap(granted(m))
        XCTAssertEqual(permission.grounds, .walk)
        XCTAssertEqual(permission.stage, .unverified)
        XCTAssertTrue(m.session.canPush)
        XCTAssertEqual(m.session.connected?.capabilityBadge.text, "Read & Write · not yet tested")
        // An `.untested` entry is `.inferred` by default, and its level's sentence about a shared
        // processor is untrue of most of them (an X-Trans II body, a GFX 50S).
        XCTAssertEqual(m.session.connected?.pushCaveat, WritePermission.Grounds.walk.pushCaveat)
        XCTAssertNotEqual(m.session.connected?.pushCaveat, VerificationLevel.inferred.pushCaveat)
        XCTAssertEqual(m.session.connected?.testerNote, WritePermission.Grounds.walk.testerNote)
        XCTAssertNotEqual(m.session.connected?.testerNote, VerificationLevel.inferred.testerNote)
        XCTAssertFalse(m.session.connected?.pushCaveat?.contains("processor") ?? true)
        XCTAssertFalse(m.session.connected?.testerNote?.contains("processor") ?? true)
    }

    func testABodyStillBeingReadIsToldNothingAboutWriting() {
        let identification = CameraModelRegistry.shared.identify(productName: "FUJIFILM GFX100 II")
        let reading = ConnectedCamera(productName: "FUJIFILM GFX100 II", firmwareVersion: nil,
                                      identification: identification, isDemo: false,
                                      writeAccess: WriteDecision.decide(identification: identification,
                                                                        observed: ObservedCapabilities(),
                                                                        firmwareVersion: nil, serialHash: nil))
        XCTAssertEqual(reading.writeAccess, .undecided)
        XCTAssertNil(reading.pushCaveat)
        XCTAssertNil(reading.testerNote,
                     "its entry's `.inferred` note would say writing is on because of a shared processor")
    }

    func testATrustedInferredEntryKeepsTheSharedArchitectureCaveat() async throws {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-T4", firmwareVersion: "1.00"))
        let permission = try XCTUnwrap(granted(m))
        XCTAssertEqual(permission.grounds, .trustedEntry(.inferred))
        XCTAssertEqual(m.session.connected?.pushCaveat, VerificationLevel.inferred.pushCaveat)
        XCTAssertEqual(m.session.connected?.testerNote, VerificationLevel.inferred.testerNote)
    }

    func testAnUntestedBodyWithoutABankBlockIsRefused() async throws {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-H1", firmwareVersion: "2.01",
                                                    unsupportedReadCodes: [FujiPTP.Prop.slotSelector, FujiPTP.Prop.presetName]))
        let connected = try XCTUnwrap(m.session.connected)
        XCTAssertEqual(connected.writeAccess, .refused(.noBankBlock))
        XCTAssertEqual(connected.capabilityBadge.text, "Read-only · no USB slots")
        XCTAssertTrue(connected.slotsUnreachable)
        XCTAssertFalse(m.session.canPush)
    }

    func testAnIgnoredSelectRefusesTheBody() async throws {
        var faults = MockCameraFaults.readOnlyWithSlots
        faults.silentlyIgnoredWriteCodes = [FujiPTP.Prop.slotSelector]
        let (m, _) = await connect(faults)
        XCTAssertEqual(m.session.connected?.writeAccess, .refused(.selectIgnored(bank: 2)))
        XCTAssertFalse(m.session.canPush)
        XCTAssertTrue(m.session.pushBlockReason?.contains("C2") ?? false, m.session.pushBlockReason ?? "nil")
        XCTAssertEqual(m.session.connected?.capabilityBadge.text, "Read-only")
    }

    func testACommunityEntryIsGrantedUnverifiedOnTheRegistrysWord() async throws {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-T5", firmwareVersion: "4.20"))
        let permission = try XCTUnwrap(granted(m))
        XCTAssertEqual(permission.grounds, .trustedEntry(.community))
        XCTAssertEqual(permission.stage, .unverified)
        XCTAssertEqual(m.session.connected?.capabilityBadge.text, "Read & Write · not yet tested",
                       "a community report has no write through this app behind it; the caveat stays until the first push here is read back")
    }

    func testAListedBodyWithoutDeviceInfoIsStillGranted() async throws {
        let (m, _) = await connect(MockCameraFaults(productName: "FUJIFILM X-T50", firmwareVersion: "1.32",
                                                    refusesDeviceInfo: true))
        let permission = try XCTUnwrap(granted(m))
        XCTAssertEqual(permission.grounds, .trustedEntry(.hardware))
        XCTAssertEqual(permission.stage, .verified)
        XCTAssertTrue(m.session.canPush)
    }

    func testTheGuidedGateWaitsOutAnUndecidedBody() {
        XCTAssertEqual(GuidedTestRunner.gate(status: .connected, isConnected: true, isDeciding: true),
                       .busy("Reading the camera's slots…"))
        XCTAssertEqual(GuidedTestRunner.gate(status: .connected, isConnected: true, isDeciding: false), .ready)
    }
}
