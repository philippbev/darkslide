import XCTest
@testable import FujiCookbook

final class TransportValidationTests: XCTestCase {
    private func response(code: UInt16 = 0x2001) -> Data {
        var data = Data()
        data.appendLE(UInt32(12))
        data.appendLE(UInt16(3))
        data.appendLE(code)
        data.appendLE(UInt32(987)) // ImageCaptureCore's transaction ID need not equal ours.
        return data
    }

    func testAllTransportOperationsRequireACompleteResponse() throws {
        XCTAssertNoThrow(try ImageCaptureTransport.checkResponse(response()))
        var wrongType = response()
        wrongType.writeLE(UInt16(2), at: 4)
        var wrongLength = response()
        wrongLength.writeLE(UInt32(16), at: 0)
        for malformed in [nil, Data(), Data(response().prefix(8)), wrongType, wrongLength] as [Data?] {
            XCTAssertThrowsError(try ImageCaptureTransport.checkResponse(malformed)) { error in
                XCTAssertEqual(error as? FujiPTP.InvalidDataset, .response)
            }
        }
        XCTAssertThrowsError(try ImageCaptureTransport.checkResponse(response(code: 0x201C))) { error in
            guard case CameraError.ptpError(let code) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(code, 0x201C)
        }
    }

    private func objectInfo() -> Data {
        var data = Data(repeating: 0, count: 52)
        data.writeLE(UInt16(0x3801), at: 4)
        data.writeLE(UInt32(1000), at: 8)
        data.append(FujiEncoding.packPTPString("DSCF0001.JPG"))
        data.append(contentsOf: [0, 0, 0])
        return data
    }

    func testObjectInfoChecksEntireDatasetBeforeReturningMetadata() throws {
        let data = objectInfo()
        let parsed = try FujiPTP.parseObjectInfo(data)
        XCTAssertEqual(parsed.objectFormat, 0x3801)
        XCTAssertEqual(parsed.compressedSize, 1000)
        XCTAssertEqual(parsed.filename, "DSCF0001.JPG")
        XCTAssertThrowsError(try FujiPTP.parseObjectInfo(nil))
        for length in 0..<data.count {
            XCTAssertThrowsError(try FujiPTP.parseObjectInfo(Data(data.prefix(length))), "length \(length)")
        }
        XCTAssertThrowsError(try FujiPTP.parseObjectInfo(data + Data([0])))
        var badTerminator = data
        badTerminator[badTerminator.count - 5] = 65
        XCTAssertThrowsError(try FujiPTP.parseObjectInfo(badTerminator))
        var excessiveName = data
        excessiveName[52] = 255
        XCTAssertThrowsError(try FujiPTP.parseObjectInfo(excessiveName))
    }

    func testLiveImageSizeCannotEnterBankNamespace() {
        XCTAssertEqual(FujiPTP.PresetProp.allCases.count, 23)
        XCTAssertNil(FujiPTP.PresetProp(rawValue: FujiPTP.Prop.liveImageSize))
        XCTAssertThrowsError(try CameraBackupValidation.properties([FujiPTP.Prop.liveImageSize: Data([7, 0])]))
    }
}
