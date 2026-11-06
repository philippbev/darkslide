import XCTest
@testable import FujiCookbook

/// The bodies the user owns, and the two ways one gets in: a tick in Settings, or a trusted
/// camera on the cable.
@MainActor
final class OwnedCamerasTests: XCTestCase {

    private let registry = CameraModelRegistry.shared

    private func suite() -> UserDefaults {
        let name = "OwnedCamerasTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func connected(_ identification: ModelIdentification, isDemo: Bool = false) -> ConnectedCamera {
        ConnectedCamera(productName: identification.model?.displayName ?? "FUJIFILM X-T99",
                        firmwareVersion: "1.00", identification: identification, isDemo: isDemo,
                        writeAccess: WriteDecision.decide(identification: identification, observed: ObservedCapabilities(),
                                                          firmwareVersion: "1.00", serialHash: nil))
    }

    private func model(_ id: String) throws -> CameraModel { try XCTUnwrap(registry.model(withID: id)) }

    // MARK: - The store

    func testAnEmptyStoreHasNoCameras() {
        let owned = OwnedCameras(defaults: suite())
        XCTAssertTrue(owned.modelIDs.isEmpty)
        XCTAssertTrue(owned.models.isEmpty)
    }

    func testAddPersistsAndReloadsInOrder() {
        let defaults = suite()
        let owned = OwnedCameras(defaults: defaults)
        owned.add("X-T50")
        owned.add("X-T3")
        owned.add("GFX50S")
        XCTAssertEqual(owned.modelIDs, ["X-T50", "X-T3", "GFX50S"])
        let reloaded = OwnedCameras(defaults: defaults)
        XCTAssertEqual(reloaded.modelIDs, ["X-T50", "X-T3", "GFX50S"])
        XCTAssertEqual(reloaded.models.map(\.id), ["X-T50", "X-T3", "GFX50S"])
    }

    func testAddIsIdempotent() {
        let owned = OwnedCameras(defaults: suite())
        owned.add("X-T50")
        owned.add("X-T50")
        XCTAssertEqual(owned.modelIDs, ["X-T50"])
    }

    func testRemoveIsSavedAndIgnoresAnAbsentBody() {
        let defaults = suite()
        let owned = OwnedCameras(defaults: defaults)
        owned.add("X-T50")
        owned.add("X-T3")
        owned.remove("X-T50")
        XCTAssertEqual(owned.modelIDs, ["X-T3"])
        XCTAssertFalse(owned.contains("X-T50"))
        XCTAssertEqual(OwnedCameras(defaults: defaults).modelIDs, ["X-T3"], "the removal is saved")
        owned.remove("X-T50")
        XCTAssertEqual(owned.modelIDs, ["X-T3"], "removing a body that isn't there changes nothing")
    }

    func testTheDemoCameraAndUnknownIDsAreRefused() {
        let owned = OwnedCameras(defaults: suite())
        owned.add(CameraModelRegistry.demoModelID)
        owned.add("X-T99")
        XCTAssertTrue(owned.modelIDs.isEmpty)
    }

    /// A stored list from an older build, or one edited by hand, is sanitised on the way in.
    func testLoadDropsDuplicatesUnknownIDsAndTheDemoCameraKeepingOrder() {
        let defaults = suite()
        defaults.set(["X-T3", CameraModelRegistry.demoModelID, "X-T99", "X-T50", "X-T3", "GFX50S"],
                     forKey: OwnedCameras.key)
        XCTAssertEqual(OwnedCameras(defaults: defaults).modelIDs, ["X-T3", "X-T50", "GFX50S"])
    }

    func testSelectableExcludesTheDemoCameraAndKeepsRegistryOrder() {
        let owned = OwnedCameras(defaults: suite())
        XCTAssertEqual(owned.selectable.map(\.id),
                       registry.models.map(\.id).filter { $0 != CameraModelRegistry.demoModelID })
    }

    // MARK: - A camera on the cable

    func testAnExactlyIdentifiedReadOnlyBodyIsAdded() throws {
        let owned = OwnedCameras(defaults: suite())
        owned.noteConnected(connected(.exact(try model("X-T3"))))
        XCTAssertEqual(owned.modelIDs, ["X-T3"], "read-only bodies are owned too")
    }

    func testAnAliasedBodyIsAdded() throws {
        let owned = OwnedCameras(defaults: suite())
        owned.noteConnected(connected(.alias(try model("X-T30 II"), alias: "X-T30II")))
        XCTAssertEqual(owned.modelIDs, ["X-T30 II"])
    }

    func testAHeuristicMatchIsNotAdded() throws {
        let owned = OwnedCameras(defaults: suite())
        owned.noteConnected(connected(.heuristic(try model("X-T5"), matched: "X-T5")))
        XCTAssertTrue(owned.modelIDs.isEmpty, "a name-pattern guess is not a camera the user owns")
    }

    func testAnUnknownBodyIsNotAdded() {
        let owned = OwnedCameras(defaults: suite())
        owned.noteConnected(connected(.unknown))
        XCTAssertTrue(owned.modelIDs.isEmpty)
    }

    /// The Camera tab's second demo resolves to a real registry body; only the transport says it
    /// is the demo — the same trap `RememberedCamera` guards against.
    func testTheDemoCameraIsNotAddedEvenOnARealEntry() throws {
        let owned = OwnedCameras(defaults: suite())
        owned.noteConnected(connected(.exact(registry.demoModel), isDemo: true))
        owned.noteConnected(connected(.exact(try model("GFX100")), isDemo: true))
        XCTAssertTrue(owned.modelIDs.isEmpty)
    }

    func testASecondConnectDoesNotDuplicate() throws {
        let owned = OwnedCameras(defaults: suite())
        let xT50 = connected(.exact(try model("X-T50")))
        owned.noteConnected(xT50)
        owned.noteConnected(xT50)
        XCTAssertEqual(owned.modelIDs, ["X-T50"])
    }

    /// Removing a body the user is plugged into holds: nothing re-adds it until that body connects
    /// again, which is the documented rule.
    func testRemovalHoldsUntilTheNextConnect() throws {
        let owned = OwnedCameras(defaults: suite())
        let xT50 = connected(.exact(try model("X-T50")))
        owned.noteConnected(xT50)
        owned.remove("X-T50")
        XCTAssertTrue(owned.modelIDs.isEmpty)
        owned.noteConnected(xT50)
        XCTAssertEqual(owned.modelIDs, ["X-T50"], "the next connect adds it again")
    }
}
