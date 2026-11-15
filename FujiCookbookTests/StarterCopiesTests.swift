import XCTest
@testable import FujiCookbook

final class StarterCopiesTests: XCTestCase {
    private typealias Copy = StarterCopies.Copy<String>
    private typealias Resolution = StarterCopies.Resolution<String>

    private func day(_ number: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(number) * 86_400)
    }

    func testNoCopiesOrOneCopyNeedNothing() {
        XCTAssertEqual(StarterCopies.resolve([Copy]()), Resolution())
        XCTAssertEqual(StarterCopies.resolve([Copy(id: "a", createdAt: day(1), isEdited: false)]),
                       Resolution())
    }

    func testUntouchedCopiesKeepTheOldest() {
        let copies = [Copy(id: "newer", createdAt: day(2), isEdited: false),
                      Copy(id: "oldest", createdAt: day(1), isEdited: false),
                      Copy(id: "newest", createdAt: day(3), isEdited: false)]
        XCTAssertEqual(StarterCopies.resolve(copies), Resolution(delete: ["newer", "newest"]))
    }

    /// The edited copy is kept even though it is the newer one: deleting it would lose the edit.
    func testAnEditedCopyReplacesEveryUntouchedOne() {
        let copies = [Copy(id: "untouched", createdAt: day(1), isEdited: false),
                      Copy(id: "edited", createdAt: day(2), isEdited: true)]
        XCTAssertEqual(StarterCopies.resolve(copies), Resolution(delete: ["untouched"]))
    }

    func testEditedCopiesPastTheOldestAreRekeyed() {
        let copies = [Copy(id: "edited-later", createdAt: day(3), isEdited: true),
                      Copy(id: "untouched", createdAt: day(1), isEdited: false),
                      Copy(id: "edited-first", createdAt: day(2), isEdited: true)]
        XCTAssertEqual(StarterCopies.resolve(copies),
                       Resolution(delete: ["untouched"], rekey: ["edited-later"]))
    }

    /// Two devices see the same copies in different fetch orders, and must reach the same answer.
    func testTheAnswerDoesNotDependOnOrder() {
        let copies = [Copy(id: "a", createdAt: day(1), isEdited: false),
                      Copy(id: "b", createdAt: day(2), isEdited: true),
                      Copy(id: "c", createdAt: day(3), isEdited: false),
                      Copy(id: "d", createdAt: day(4), isEdited: true)]
        XCTAssertEqual(StarterCopies.resolve(copies), StarterCopies.resolve(copies.reversed()))
    }
}
