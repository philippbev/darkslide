import XCTest
@testable import FujiCookbook

/// The photo import's head: SOURCE | MODE | SELECTION, the All / None key, a day's frame range.
final class PhotoImportHeaderTests: XCTestCase {

    private typealias Header = PhotoImportHeader

    func testTheFieldsAreSourceModeAndSelection() {
        let fields = Header.fields(sourceName: "FUJIFILM X100VI", isListing: false, loadedCount: 40, hasOlder: false,
                                   fileChoice: .raw, selected: 12, shown: 40)
        XCTAssertEqual(fields, [DSDataField(label: "Source", value: "X100VI", led: true),
                                DSDataField(label: "Mode", value: "RAW"),
                                DSDataField(label: "Selection", value: "12/40")])
    }

    func testTheSourceSaysWhileTheCardIsStillReadAndWhatWaits() {
        let source = Header.fields(sourceName: "Demo Card", isListing: true, loadedCount: 500, hasOlder: true,
                                   fileChoice: .all, selected: 0, shown: 500)[0]
        XCTAssertEqual(source.value, "Demo Card")
        XCTAssertEqual(source.led, false)
        XCTAssertEqual(source.note, "Newest 500")
    }

    func testTheMakerIsLeftOffTheName() {
        XCTAssertEqual(Header.shortName("FUJIFILM X-T5"), "X-T5")
        XCTAssertEqual(Header.shortName("Fujifilm GFX100 II"), "GFX100 II")
        XCTAssertEqual(Header.shortName("Camera"), "Camera")
        XCTAssertEqual(Header.shortName("FUJIFILM "), "FUJIFILM ")
    }

    func testEveryModeFitsAThirdOfTheRow() {
        XCTAssertEqual(ImportFileChoice.allCases.map(Header.modeValue), ["RAW+JPG", "RAW", "JPG"])
    }

    func testTheTopKeySelectsAllUntilAllIsChosen() {
        XCTAssertTrue(Header.selectsAll(selected: 0, shown: 10))
        XCTAssertTrue(Header.selectsAll(selected: 9, shown: 10))
        XCTAssertFalse(Header.selectsAll(selected: 10, shown: 10))
    }

    func testADaysRangeRunsFromItsFirstToItsLastFrame() {
        XCTAssertEqual(Header.frameRange(["0150", "0142", "0147"]), "0142–0150")
        XCTAssertEqual(Header.frameRange(["9999", "10000"]), "9999–10000", "by number, not by text")
        XCTAssertEqual(Header.frameRange(["0142"]), "0142")
        XCTAssertNil(Header.frameRange([]))
    }
}
