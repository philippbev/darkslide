import XCTest
@testable import FujiCookbook

@MainActor
final class CameraBackupValidationTests: XCTestCase {
    private func backup(properties: [String: String] = ["0xD192": "0400"], slot: Int = 1,
                        occupied: Bool = true) -> CameraBackup {
        CameraBackup(capturedAt: Date(timeIntervalSince1970: 0),
                     camera: .init(productName: "Demo Camera", modelID: nil, firmwareVersion: nil,
                                   serialHash: nil, serialHashScheme: nil),
                     slots: [.init(index: slot, occupied: occupied, properties: properties)])
    }

    func testMalformedMapsAreRefusedAsAWhole() {
        let maps = [
            ["0xD192": "0400", "0xD19D": "NOTHEX"],
            ["0xD192": "0400", "0xD19E": "FF"],
            ["0xD192": ""], ["0xD192": "000000"], ["0xD192": "00 0"],
            ["xxD192": "0400"], ["D192": "0400"], ["0xD192": "0400", "0XD192": "0400"],
            ["0xD185": "0400"], ["0xD1A5": "0700"], ["0xFFFF": "0400"], [:]
        ]
        for properties in maps {
            let invalid = backup(properties: properties)
            XCTAssertThrowsError(try CameraBackup.decode(invalid.json), "\(properties)")
            XCTAssertNil(invalid.properties(forSlot: 1), "a recovery record must not silently narrow invalid data")
        }
    }

    func testInvalidSlotAndVersionMetadataIsRefused() {
        for index in [-1, 0, 8, 65537] {
            XCTAssertThrowsError(try CameraBackup.decode(backup(slot: index).json))
        }
        var duplicate = backup()
        duplicate.slots.append(duplicate.slots[0])
        XCTAssertThrowsError(try CameraBackup.decode(duplicate.json))
        for version in [-1, 0, 2] {
            var invalid = backup(); invalid.version = version
            XCTAssertThrowsError(try CameraBackup.decode(invalid.json))
        }
    }

    func testAMalformedUnselectedSlotAlsoRejectsTheFile() {
        var invalid = backup()
        invalid.slots.append(.init(index: 2, occupied: true, properties: ["0xD19E": "FF"]))
        XCTAssertThrowsError(try CameraBackup.decode(invalid.json))
    }

    func testValidPartialAndUnfamiliarRawValuesRemainRestorable() throws {
        let source = backup(properties: ["0xd192": "0b00", "0xD199": "9980"])
        let decoded = try CameraBackup.decode(source.json)
        XCTAssertEqual(decoded, source)
        XCTAssertEqual(decoded.properties(forSlot: 1), [0xD192: Data([0x0B, 0]), 0xD199: Data([0x99, 0x80])])
        XCTAssertNoThrow(try CameraBackup.decode(backup(properties: [:], occupied: false).json))
    }

    func testInvalidDirectRestoresWriteNothingIncludingTheSelectorAndName() async throws {
        CameraReportStore.deleteLatest()
        var faults = MockCameraFaults(); faults.isInstant = true; faults.maxSelectableSlot = 4
        let transport = MockCameraTransport(faults: faults)
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        let beforeWrites = await transport.totalWriteCount
        let before = manager.slotReader.slots
        let cases: [([UInt16: Data], Int)] = [
            ([0xD192: Data([4, 0]), 0xD19E: Data([0xFF])], 1),
            ([0xD185: Data([4, 0])], 1), ([0xD1A5: Data([7, 0])], 1), ([:], 1),
            ([0xD192: Data([4, 0])], 0), ([0xD192: Data([4, 0])], 5),
            ([0xD192: Data([4, 0])], 65537)
        ]
        for (saved, slot) in cases {
            let result = await manager.slotWriter.restore(saved, name: "Must not rename", toSlot: slot)
            XCTAssertEqual(result.outcome, .notWritten)
            XCTAssertFalse(result.nameWritten)
            XCTAssertNotNil(result.errorMessage)
        }
        let afterWrites = await transport.totalWriteCount
        XCTAssertEqual(afterWrites, beforeWrites)
        XCTAssertEqual(manager.slotReader.slots, before)
    }

    /// A recovery copy is matched to the connected body by registry id when both sides have one,
    /// else by product name: a copy taken while a body was unlisted carries no id, and the same
    /// body gains one when a later build lists it.
    func testARecoveryCopyIsMatchedToItsBodyByIdOrElseByProductName() {
        let listed = CameraBackup.Camera(productName: "X-T50", modelID: "X-T50", firmwareVersion: nil,
                                         serialHash: nil, serialHashScheme: nil)
        let unlisted = CameraBackup.Camera(productName: "X-T50", modelID: nil, firmwareVersion: nil,
                                           serialHash: nil, serialHashScheme: nil)
        XCTAssertTrue(listed.isFromBody(productName: "X-T50", registryModelID: "X-T50"))
        XCTAssertFalse(listed.isFromBody(productName: "X-T5", registryModelID: "X-T5"))
        XCTAssertFalse(listed.isFromBody(productName: "X-T50", registryModelID: "X-T5"), "ids decide when both sides have one")
        XCTAssertTrue(listed.isFromBody(productName: "X-T50", registryModelID: nil), "the body is no longer listed")
        XCTAssertTrue(unlisted.isFromBody(productName: "X-T50", registryModelID: "X-T50"), "the body was listed after the copy was taken")
        XCTAssertTrue(unlisted.isFromBody(productName: "X-T50", registryModelID: nil))
        XCTAssertFalse(unlisted.isFromBody(productName: "X-T99", registryModelID: nil), "two unlisted bodies never match each other")
    }
}
