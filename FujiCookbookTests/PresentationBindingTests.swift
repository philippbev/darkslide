import SwiftUI
import XCTest
@testable import FujiCookbook

/// `Binding(isPresent:)` drives every optional-backed alert, sheet and dialog, so its two halves are
/// pinned here: it reads the optional, and only a dismissal (a write of false) clears it.
final class PresentationBindingTests: XCTestCase {

    func testIsPresentFollowsTheOptionalAndOnlyDismissalClearsIt() {
        var message: String?
        let isPresented = Binding(isPresent: Binding(get: { message }, set: { message = $0 }))

        XCTAssertFalse(isPresented.wrappedValue)
        message = "Export failed"
        XCTAssertTrue(isPresented.wrappedValue)

        isPresented.wrappedValue = true
        XCTAssertEqual(message, "Export failed", "presenting must leave the payload alone")

        isPresented.wrappedValue = false
        XCTAssertNil(message)
        XCTAssertFalse(isPresented.wrappedValue)
    }
}
