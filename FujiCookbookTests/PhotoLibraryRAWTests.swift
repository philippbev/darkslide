import UniformTypeIdentifiers
import XCTest
@testable import FujiCookbook

/// Picking RAW files from Photos: which photos count as carrying a RAW, and what the picker says
/// about the ones that didn't arrive.
final class PhotoLibraryRAWTests: XCTestCase {

    private let raf = URL(fileURLWithPath: "/tmp/DSCF0001.RAF")

    func testAFujifilmRAFCountsAsARAW() throws {
        let fujiRAW = try XCTUnwrap(UTType("com.fuji.raw-image"), "the system declares Fujifilm's RAW type")
        XCTAssertTrue(PhotoLibraryRAW.carriesRAW([fujiRAW]))
    }

    func testAJPEGOrHEICAloneIsNotARAW() {
        XCTAssertFalse(PhotoLibraryRAW.carriesRAW([.jpeg]))
        XCTAssertFalse(PhotoLibraryRAW.carriesRAW([.heic]))
        XCTAssertFalse(PhotoLibraryRAW.carriesRAW([]))
    }

    func testARAWAmongOtherTypesCountsAsARAW() throws {
        let fujiRAW = try XCTUnwrap(UTType("com.fuji.raw-image"))
        XCTAssertTrue(PhotoLibraryRAW.carriesRAW([.jpeg, fujiRAW]))
    }

    func testACleanImportHasNoProblem() {
        XCTAssertNil(PhotoLibraryRAW.Import(urls: [raf]).problem)
        XCTAssertNil(PhotoLibraryRAW.Import().problem, "cancelling the picker picks nothing and says nothing")
    }

    /// The fact first, then where the .RAF comes from, then the pair case — hedged, and last. A
    /// tester who picked a plain JPEG read the old wording as Photos hiding a RAW from the app.
    func testOnePhotoWithoutARAWSaysSoAndPointsAtTheRAF() throws {
        let problem = try XCTUnwrap(PhotoLibraryRAW.Import(withoutRAW: 1).problem)
        XCTAssertEqual(problem.title, "Couldn't Use That Photo")
        XCTAssertEqual(problem.message, "That photo has no RAW file attached. Pick the .RAF itself — from Photos if the Fujifilm app downloaded it to your phone, or with Browse Files. A photo Photos holds as a RAW+JPEG pair may offer only its JPEG; bring its .RAF in on its own.")
    }

    func testEveryPhotoWithoutARAWSaysNone() throws {
        let problem = try XCTUnwrap(PhotoLibraryRAW.Import(withoutRAW: 3).problem)
        XCTAssertEqual(problem.title, "Couldn't Use Those Photos")
        XCTAssertEqual(problem.message, "None of those photos has a RAW file attached. Pick the .RAF itself — from Photos if the Fujifilm app downloaded it to your phone, or with Browse Files. A photo Photos holds as a RAW+JPEG pair may offer only its JPEG; bring its .RAF in on its own.")
    }

    func testSomePhotosWithoutARAWAreCountedAgainstThePick() throws {
        let one = try XCTUnwrap(PhotoLibraryRAW.Import(urls: [raf, raf], withoutRAW: 1).problem)
        XCTAssertEqual(one.title, "Some Photos Weren't Added")
        XCTAssertEqual(one.message, "1 of the 3 photos has no RAW file attached. Pick the .RAF itself — from Photos if the Fujifilm app downloaded it to your phone, or with Browse Files. A photo Photos holds as a RAW+JPEG pair may offer only its JPEG; bring its .RAF in on its own.")

        let two = try XCTUnwrap(PhotoLibraryRAW.Import(urls: [raf], withoutRAW: 2).problem)
        XCTAssertEqual(two.message, "2 of the 3 photos have no RAW file attached. Pick the .RAF itself — from Photos if the Fujifilm app downloaded it to your phone, or with Browse Files. A photo Photos holds as a RAW+JPEG pair may offer only its JPEG; bring its .RAF in on its own.")
    }

    func testAFailedCopyAsksToTryAgain() throws {
        let single = try XCTUnwrap(PhotoLibraryRAW.Import(failed: 1).problem)
        XCTAssertEqual(single.title, "Couldn't Use That Photo")
        XCTAssertEqual(single.message, "Couldn't copy that photo from your library. Try again.")

        let all = try XCTUnwrap(PhotoLibraryRAW.Import(failed: 2).problem)
        XCTAssertEqual(all.title, "Couldn't Use Those Photos")
        XCTAssertEqual(all.message, "Couldn't copy those photos from your library. Try again.")

        let some = try XCTUnwrap(PhotoLibraryRAW.Import(urls: [raf], failed: 1).problem)
        XCTAssertEqual(some.message, "1 of the 2 photos couldn't be copied from your library. Try picking it again.")
    }

    func testAMixedPickNamesBothProblems() throws {
        let problem = try XCTUnwrap(PhotoLibraryRAW.Import(urls: [raf], withoutRAW: 1, failed: 2).problem)
        XCTAssertEqual(problem.title, "Some Photos Weren't Added")
        XCTAssertEqual(problem.message, "1 of the 4 photos has no RAW file attached. Pick the .RAF itself — from Photos if the Fujifilm app downloaded it to your phone, or with Browse Files. A photo Photos holds as a RAW+JPEG pair may offer only its JPEG; bring its .RAF in on its own. 2 of the 4 photos couldn't be copied from your library. Try picking them again.")
    }
}
