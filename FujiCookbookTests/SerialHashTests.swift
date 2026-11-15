import XCTest
import CryptoKit
@testable import FujiCookbook

/// A Camera Compatibility Report has to be safe to post in a public issue, so the serial hash in it
/// must be one nobody else can reverse — and the reports, Camera Tests and recovery copies already
/// stored under the old unkeyed hash must still be recognized when their camera comes back.
@MainActor
final class SerialHashTests: XCTestCase {
    private let serial = "12A34567"
    /// What `MockCameraTransport` answers in `GetDeviceInfo`.
    private let demoSerial = "DEMO0000001"

    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
        GuidedRecoveryStore.deleteAll()
    }

    override func tearDown() {
        CameraReportStore.deleteLatest()
        GuidedRecoveryStore.deleteAll()
        super.tearDown()
    }

    private func deviceKey() throws -> SymmetricKey {
        try XCTUnwrap(SerialHash.deviceKey, "the test host's Keychain produces the device key")
    }

    private func connect(_ faults: MockCameraFaults = MockCameraFaults()) async -> CameraServices {
        var faults = faults
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    private var recipe: RecipeSettings {
        RecipeSettings(filmSimulation: .classicNeg, grain: GrainEffect(strength: .weak, size: .large),
                       colorChromeEffect: .strong, colorChromeFXBlue: .weak,
                       whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 2, shiftBlue: -3, kelvin: nil),
                       dynamicRange: .dr400,
                       highlightTone: -0.5, shadowTone: 1.0, color: 2, sharpness: -1, highISONR: -3, clarity: 1)
    }

    /// Rewrite the stored report as the build before keyed hashes would have left it.
    private func storeAsLegacy(serial: String) throws {
        var stored = try XCTUnwrap(CameraReportStore.loadLatest())
        stored.camera.serialHash = SerialHash.legacy(serial)
        stored.camera.serialHashScheme = nil
        XCTAssertNotNil(CameraReportStore.save(stored))
    }

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    // MARK: The hash

    func testTheKeyedHashIsStableOnThisPhoneAndIsNeverTheSerial() throws {
        let key = try deviceKey()
        let first = SerialHash.recordConnected(serial: serial, key: key)
        XCTAssertEqual(first, SerialHash.recordConnected(serial: serial, key: try deviceKey()),
                       "one serial, one phone, one hash")
        XCTAssertEqual(first.count, 16, "8 bytes, as before")
        XCTAssertTrue(first.allSatisfy(\.isHexDigit))
        XCTAssertFalse(first.localizedCaseInsensitiveContains(serial))
        XCTAssertNotEqual(first, SerialHash.legacy(serial), "not the hash anyone can recompute")
        XCTAssertNotEqual(first, SerialHash.keyed("12A34568", key: key), "a neighbouring serial hashes elsewhere")
    }

    func testTheKeyIsWhatTheHashDependsOn() {
        let a = SymmetricKey(size: .bits256), b = SymmetricKey(size: .bits256)
        XCTAssertEqual(SerialHash.keyed(serial, key: a), SerialHash.keyed(serial, key: a))
        XCTAssertNotEqual(SerialHash.keyed(serial, key: a), SerialHash.keyed(serial, key: b),
                          "without this phone's key a guessed serial checks against nothing")
    }

    /// Pinned to the value earlier builds stored, or no stored record would ever match again.
    func testTheLegacyHashIsTheOneEarlierBuildsStored() {
        XCTAssertEqual(SerialHash.legacy(serial), "1a17a3d2c567808e")
    }

    func testTheKeyIsStoredOnceAndOutlivesTheRetiredAICleanup() throws {
        let stored = try XCTUnwrap(KeychainStore.secret(for: SerialHash.keychainAccount, byteCount: 32))
        XCTAssertEqual(KeychainStore.secret(for: SerialHash.keychainAccount, byteCount: 32), stored,
                       "read back, not regenerated")
        XCTAssertEqual(SerialHash.keyed(serial, key: SymmetricKey(data: stored)),
                       SerialHash.keyed(serial, key: try deviceKey()))

        RetiredAIData.purge()
        XCTAssertEqual(KeychainStore.secret(for: SerialHash.keychainAccount, byteCount: 32), stored,
                       "the cleanup is about AI credentials; this key would make every camera a stranger")
    }

    /// Never the unkeyed hash as a fallback: it would put the serial within reach of anyone holding
    /// the report.
    func testNoKeyMeansNoHashRatherThanAWeakOne() {
        var info = FujiPTP.DeviceInfo()
        info.serialNumber = serial
        var report = CameraCompatibilityReport.beginUnreached()
        report.record(deviceInfo: info, rawLength: 0, serialKey: nil)
        XCTAssertNil(report.camera.serialHash)
        XCTAssertNil(report.camera.serialHashScheme)
        XCTAssertTrue(report.notes.contains { $0.hasPrefix("serial hash omitted") }, "\(report.notes)")
        let json = String(decoding: report.json, as: UTF8.self)
        XCTAssertFalse(json.contains(SerialHash.legacy(serial)))
        XCTAssertFalse(json.contains(serial))
    }

    // MARK: What a report carries

    func testAReportCarriesTheKeyedHashAndNoSecret() async throws {
        let key = try deviceKey()
        let m = await connect()
        let report = try XCTUnwrap(m.reports.report)
        XCTAssertEqual(report.camera.serialHash, SerialHash.keyed(demoSerial, key: key))
        XCTAssertEqual(report.camera.serialHashScheme, SerialHash.keyedScheme)

        let secret = key.withUnsafeBytes { Data($0) }
        let snapshot = DiagnosticsReportSnapshot(capturedAt: Date(), reportText: report.textRendering,
                                                 cameraReport: report, summary: [])
        let export = snapshot.export(for: .standalone, note: nil)
        let outputs = [String(decoding: report.json, as: UTF8.self), report.textRendering,
                       export.text, try XCTUnwrap(export.cameraJSON)]
        for output in outputs {
            for needle in [demoSerial, SerialHash.legacy(demoSerial), hex(secret), secret.base64EncodedString()] {
                XCTAssertFalse(output.localizedCaseInsensitiveContains(needle), "\(needle) in \(output.prefix(200))")
            }
        }
        XCTAssertTrue(export.text.contains("hash \(report.camera.serialHash!) (keyed to this phone)"),
                      "the keyed hash is shared, and says what it is")
        XCTAssertEqual(try XCTUnwrap(export.cameraJSON), String(decoding: report.json, as: UTF8.self))
    }

    /// A report stored by an earlier build carries the unkeyed hash until its camera reconnects. Until
    /// then it can still be shared, and the hash must not go with it — from the JSON or from a text
    /// rendering frozen into a saved Camera Test before the upgrade.
    func testAnUnkeyedHashNeverLeavesTheDevice() throws {
        var report = CameraCompatibilityReport.beginUnreached()
        report.camera.serialHash = SerialHash.legacy(serial)
        let frozen = "Fuji Cookbook — camera compatibility report v6\nSerial      hash \(SerialHash.legacy(serial))\nUSB         0x04CB:0x02E3"
        let snapshot = DiagnosticsReportSnapshot(capturedAt: Date(), reportText: frozen + "\n" + report.textRendering,
                                                 cameraReport: report, summary: [])

        for presentation in [DiagnosticsReportView.Presentation.standalone, .cameraTest] {
            let export = snapshot.export(for: presentation, note: nil)
            let shared = export.shareable(for: presentation)
            for output in [export.text, export.technicalText, try XCTUnwrap(export.cameraJSON),
                           String(decoding: shared.data, as: UTF8.self)]
                + shared.extraFiles.map({ String(decoding: $0.data, as: UTF8.self) }) {
                XCTAssertFalse(output.contains(SerialHash.legacy(serial)), "\(presentation): \(output.prefix(300))")
            }
            XCTAssertTrue(export.text.contains("USB         0x04CB:0x02E3"), "only the serial line goes")
        }
        XCTAssertEqual(snapshot.cameraReport?.camera.serialHash, SerialHash.legacy(serial),
                       "the stored copy keeps it, to recognize its camera by")
    }

    // MARK: Recognizing what earlier builds stored

    func testAStoredReportWithTheLegacyHashStillMatchesItsCameraAndIsRewrittenKeyed() async throws {
        let m = await connect(MockCameraFaults(productName: "FUJIFILM X-T5"))
        _ = await m.slotWriter.push(settings: recipe, name: "Before", toSlot: 3)
        let keyed = try XCTUnwrap(m.reports.report?.camera.serialHash)
        await m.connector.disconnect()
        try storeAsLegacy(serial: demoSerial)

        let m2 = await connect(MockCameraFaults(productName: "FUJIFILM X-T5"))
        XCTAssertEqual(m2.reports.report?.pushes?.count, 1, "the push history came forward")
        XCTAssertEqual(m2.reports.report?.camera.serialHash, keyed)
        XCTAssertEqual(m2.reports.report?.camera.serialHashScheme, SerialHash.keyedScheme)
        await m2.connector.disconnect()
        XCTAssertEqual(CameraReportStore.loadLatest()?.camera.serialHash, keyed, "and the keyed hash replaced it on disk")
        XCTAssertEqual(CameraReportStore.loadLatest()?.camera.serialHashScheme, SerialHash.keyedScheme)
    }

    func testALegacyHashOfAnotherSerialIsStillAnotherCamera() async throws {
        let m = await connect(MockCameraFaults(productName: "FUJIFILM X-T5"))
        _ = await m.slotWriter.push(settings: recipe, name: "Before", toSlot: 3)
        await m.connector.disconnect()
        try storeAsLegacy(serial: "OTHER000001")

        let m2 = await connect(MockCameraFaults(productName: "FUJIFILM X-T5"))
        XCTAssertNil(m2.reports.report?.pushes, "a different body starts with no history")
    }

    /// The baseline Clear Diagnostics keeps is the one thing the drift check reads. Kept by an
    /// earlier build, it carries the legacy hash, and the check must not go blind on upgrade.
    func testAClearDiagnosticsBaselineFromAnEarlierBuildStillCatchesDrift() async throws {
        let m = await connect()
        // C1 has a complete readable snapshot; Classic Neg differs from its seeded Classic Chrome.
        let written = await m.slotWriter.push(settings: recipe, name: "Kept", toSlot: 1)
        XCTAssertEqual(written.outcome, .applied)
        await m.connector.disconnect()
        CameraReportStore.stripLatestToDriftBaseline()
        try storeAsLegacy(serial: demoSerial)

        var faults = MockCameraFaults()
        faults.rawReadValues = [FujiPTP.PresetProp.filmSimulation.rawValue: FujiEncoding.packU16(0x01)]
        let m2 = await connect(faults)
        XCTAssertEqual(m2.slotReader.filmSimulationDrift.map(\.slot), [1])
        XCTAssertEqual(m2.reports.report?.camera.serialHashScheme, SerialHash.keyedScheme)
    }

    func testACameraTestAndRecoveryCopyFromAnEarlierBuildStillMatchTheirCamera() throws {
        let keyed = SerialHash.recordConnected(serial: serial, key: try deviceKey())
        let facts = CameraFacts(isConnected: true, transport: "usb", productName: "FUJIFILM X-M5", serialHash: keyed)

        var session = GuidedTestSession.beginContinuous(step: .readSlots)
        session.cameraProductName = "FUJIFILM X-M5"
        session.transport = "usb"
        session.serialHash = SerialHash.legacy(serial)
        XCTAssertEqual(GuidedTestFlow.resumeDecision(stored: session, facts: facts), .offerResume(.readSlots))
        session.adopt(camera: facts)
        XCTAssertEqual(session.serialHash, keyed, "and the keyed hash is written over it")

        var other = session
        other.serialHash = SerialHash.legacy("12A34568")
        XCTAssertFalse(GuidedTestFlow.describesSameBody(stored: other, facts: facts))

        var report = CameraCompatibilityReport.begin(productName: "FUJIFILM X-M5", transport: "usb", usb: nil,
                                                     modelID: "X-M5", identification: "exact", firmwareVersion: nil,
                                                     verification: nil, assumedSlotCount: 7)
        report.camera.serialHash = keyed
        report.camera.serialHashScheme = SerialHash.keyedScheme
        session.serialHash = SerialHash.legacy(serial)
        XCTAssertTrue(DiagnosticsReportSnapshot.belongsToSessionBody(report, session: session),
                      "a session saved before the upgrade still owns this body's new report")

        let backup = CameraBackup(capturedAt: CameraCompatibilityReport.timestamp(),
                                  camera: .init(productName: "FUJIFILM X-M5", modelID: "X-M5",
                                                serialHash: SerialHash.legacy(serial)),
                                  slots: [.init(index: 1, name: "Original", occupied: true, properties: ["0xD192": "0B00"])])
        let recovery = GuidedRecoveryRecord(sessionID: UUID().uuidString, backup: backup, transport: "usb")
        XCTAssertTrue(recovery.matches(facts), "a recovery copy is never rewritten, and still finds its camera")
        var otherFacts = facts
        otherFacts.serialHash = SerialHash.keyed("12A34568", key: try deviceKey())
        XCTAssertFalse(recovery.matches(otherFacts))
    }

    // MARK: Camera backups

    /// The file `ShareBundle.items(forBackup:)` hands the share sheet.
    private func staged(_ backup: CameraBackup) throws -> Data {
        defer { ShareBundle.clearStaging() }
        let url = try XCTUnwrap(try ShareBundle.items(forBackup: backup).first as? URL)
        return try Data(contentsOf: url)
    }

    /// A recovery copy taken by an earlier build is never rewritten, so it keeps the unkeyed hash for
    /// good. Settings' export before Clear Diagnostics and the restore step's share sheet both send it
    /// off the phone, and the hash must stay behind while the record keeps it to find its camera.
    func testARecoveryCopyFromAnEarlierBuildExportsWithoutItsHash() throws {
        guard let directory = GuidedRecoveryStore.directoryURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        let legacy = SerialHash.legacy(serial)
        let sessionID = UUID().uuidString
        // As an earlier build's `GuidedRecoveryStore` wrote it: a hash, and no `serialHashScheme`.
        let file = """
            {"backup":{"camera":{"modelID":"X-M5","productName":"FUJIFILM X-M5","serialHash":"\(legacy)"},\
            "capturedAt":"2026-09-08T10:00:00Z","schema":"fuji-camera-backup",\
            "slots":[{"index":1,"name":"Original","occupied":true,"properties":{"0xD192":"0B00"},"summary":"Original"}],\
            "version":1},"dispositions":{"1":"pending"},"sessionID":"\(sessionID)","touchedSlots":[1],"transport":"usb"}
            """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(file.utf8).write(to: directory.appendingPathComponent("\(sessionID).json"))

        let stored = try XCTUnwrap(GuidedRecoveryStore.allRecords().first { $0.id == sessionID })
        XCTAssertEqual(stored.backup.camera.serialHash, legacy)
        XCTAssertNil(stored.backup.camera.serialHashScheme)

        var expected = stored.backup
        expected.camera.serialHash = nil
        for exported in [stored.exportFile.data, try staged(stored.backup)] {
            XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains(legacy))
            XCTAssertEqual(try CameraBackup.decode(exported), expected,
                           "only the hash goes; Restore a Slot matches the file by model and reads its bytes")
        }

        let kept = try XCTUnwrap(GuidedRecoveryStore.load(sessionID: sessionID))
        XCTAssertEqual(kept.backup.camera.serialHash, legacy, "the record on the phone keeps it")
        let facts = CameraFacts(isConnected: true, transport: "usb", productName: "FUJIFILM X-M5",
                                serialHash: SerialHash.recordConnected(serial: serial, key: try deviceKey()))
        XCTAssertTrue(kept.matches(facts), "and still finds its camera by it")
    }

    func testAKeyedBackupKeepsItsHashInEveryExport() async throws {
        try XCTSkipIf(GuidedRecoveryStore.directoryURL == nil, "no App Group container in this test host")
        let m = await connect()
        let backup = try XCTUnwrap(m.slotReader.slotBackup)
        XCTAssertEqual(backup.camera.serialHash, SerialHash.keyed(demoSerial, key: try deviceKey()))
        XCTAssertEqual(backup.camera.serialHashScheme, SerialHash.keyedScheme)

        let record = GuidedRecoveryRecord(sessionID: UUID().uuidString, backup: backup, transport: "usb")
        XCTAssertTrue(GuidedRecoveryStore.create(record))
        let stored = try XCTUnwrap(GuidedRecoveryStore.load(sessionID: record.id))
        XCTAssertEqual(stored.backup, backup, "the scheme survives the recovery store")

        for exported in [stored.exportFile.data, try staged(backup)] {
            XCTAssertEqual(try CameraBackup.decode(exported), backup, "a keyed hash is safe to share, and goes with the file")
        }
    }

    /// A backup file exported before the scheme existed, which Restore a Slot may be handed at any time.
    func testABackupFileFromAnEarlierBuildStillDecodes() throws {
        let legacy = SerialHash.legacy(serial)
        let file = Data("""
            {"camera":{"firmwareVersion":"1.10","modelID":"X-M5","productName":"FUJIFILM X-M5","serialHash":"\(legacy)"},\
            "capturedAt":"2026-09-08T10:00:00Z","schema":"fuji-camera-backup",\
            "slots":[{"index":1,"name":"Original","occupied":true,"properties":{"0xD192":"0B00"},"summary":"Original"}],\
            "version":1}
            """.utf8)
        let backup = try CameraBackup.decode(file)
        XCTAssertEqual(backup.camera.serialHash, legacy)
        XCTAssertNil(backup.camera.serialHashScheme, "no scheme reads as unkeyed")
        XCTAssertEqual(backup.properties(forSlot: 1), [FujiPTP.PresetProp.filmSimulation.rawValue: Data([0x0B, 0x00])])
        XCTAssertNil(backup.forSharing.camera.serialHash)
    }
}
