import UniformTypeIdentifiers
import XCTest
@testable import FujiCookbook

/// What the Kitchen's Browse Files picker offers: a Fujifilm RAW, and no JPEG, HEIC or other
/// maker's RAW to stand in for one.
final class RAFPickerSectionTests: XCTestCase {

    private func offered(_ type: UTType) -> Bool {
        RAFPickerSection.fileContentTypes.contains { type.conforms(to: $0) }
    }

    func testBrowseFilesOffersAFujifilmRAF() throws {
        let fujiRAW = try XCTUnwrap(UTType("com.fuji.raw-image"), "the system declares Fujifilm's RAW type")
        XCTAssertTrue(offered(fujiRAW))
        let byExtension = try XCTUnwrap(UTType(filenameExtension: "RAF"))
        XCTAssertTrue(offered(byExtension), "a .RAF in Files is typed by its extension")
    }

    func testBrowseFilesDoesNotOfferAJPEGOrHEIC() {
        XCTAssertFalse(offered(.jpeg))
        XCTAssertFalse(offered(.heic))
        XCTAssertFalse(offered(.png))
    }

    func testBrowseFilesDoesNotOfferAnotherMakersRAW() throws {
        for fileExtension in ["DNG", "CR3", "NEF", "ARW"] {
            let type = try XCTUnwrap(UTType(filenameExtension: fileExtension), fileExtension)
            XCTAssertTrue(type.conforms(to: .rawImage), "\(fileExtension) is a RAW, so the test means something")
            XCTAssertFalse(offered(type), fileExtension)
        }
    }
}
