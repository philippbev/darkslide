import XCTest
@testable import FujiCookbook

final class KeychainStoreSecretTests: XCTestCase {
    private let account = "test.keychainStore.emptySecret"

    override func tearDown() {
        KeychainStore.set("", for: account)
        super.tearDown()
    }

    func testEmptySecretIsRefusedAndNothingIsStored() {
        XCTAssertNil(KeychainStore.secret(for: account, byteCount: 0))
        XCTAssertNil(KeychainStore.get(account), "a refused secret leaves no item behind")
    }
}
