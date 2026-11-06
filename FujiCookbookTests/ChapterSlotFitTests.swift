import XCTest
@testable import FujiCookbook

/// A Chapter holds up to seven recipes; a body may have four or six banks. The push only offers the
/// banks the body has, so what these pin down is that the recipes past the last bank are named —
/// on the push screen, and on the Chapter screen from the last camera that could take a push.
@MainActor
final class ChapterSlotFitTests: XCTestCase {

    private func chapter(_ count: Int) -> Chapter {
        Chapter(name: "Seven", recipeUUIDs: (0..<count).map { _ in UUID() })
    }

    private func suite() -> UserDefaults {
        let name = "ChapterSlotFitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    // MARK: Which slots a body leaves out

    func testAFourBankBodyLeavesOutTheLastThreeOfSeven() {
        XCTAssertEqual(chapter(7).slotsBeyond(4), [5, 6, 7])
        XCTAssertEqual(chapter(7).slotsBeyond(6), [7])
        XCTAssertEqual(chapter(7).slotsBeyond(7), [])
    }

    func testAChapterThatFitsLeavesNothingOut() {
        XCTAssertEqual(chapter(3).slotsBeyond(4), [])
        XCTAssertEqual(chapter(0).slotsBeyond(4), [])
    }

    func testSlotRunLabels() {
        XCTAssertEqual(Chapter.slotRunLabel([7]), "C7")
        XCTAssertEqual(Chapter.slotRunLabel([6, 7]), "C6 and C7")
        XCTAssertEqual(Chapter.slotRunLabel([5, 6, 7]), "C5–C7")
        XCTAssertEqual(Chapter.slotRunLabel([]), "")
    }

    // MARK: The push screen names what it drops

    func testPushNamesTheRecipesPastTheLastBank() {
        let recipes = (1...7).map { Recipe(name: "R\($0)") }
        let preassigned = Dictionary(uniqueKeysWithValues: recipes.enumerated().map { ($0.offset + 1, $0.element.uuid) })

        let leftOut = PushView.slotsLeftOut(preassigned: preassigned, slotCount: 4, recipes: recipes)

        XCTAssertEqual(leftOut.map(\.slot), [5, 6, 7])
        XCTAssertEqual(leftOut.map(\.name), ["R5", "R6", "R7"])
    }

    /// A deleted recipe is already shown as missing on the Chapter screen, and has no name to give.
    func testADeletedRecipeIsNotListedAsLeftOut() {
        let kept = [Recipe(name: "C5 kept"), Recipe(name: "C7 kept")]
        let preassigned: [Int: UUID] = [5: kept[0].uuid, 6: UUID(), 7: kept[1].uuid]

        let leftOut = PushView.slotsLeftOut(preassigned: preassigned, slotCount: 4, recipes: kept)

        XCTAssertEqual(leftOut.map(\.slot), [5, 7])
    }

    func testASingleRecipePushLeavesNothingOut() {
        XCTAssertTrue(PushView.slotsLeftOut(preassigned: [:], slotCount: 4, recipes: [Recipe(name: "Solo")]).isEmpty)
    }

    // MARK: Remembering the last camera

    func testRememberedCameraRoundTrips() {
        let defaults = suite()
        XCTAssertNil(RememberedCamera(defaults: defaults), "nothing before the first connect")

        RememberedCamera(displayName: "FUJIFILM X-M5", slotCount: 4)!.save(to: defaults)

        XCTAssertEqual(RememberedCamera(defaults: defaults), RememberedCamera(displayName: "FUJIFILM X-M5", slotCount: 4))
    }

    func testNothingToSayIsNotRemembered() {
        XCTAssertNil(RememberedCamera(displayName: "", slotCount: 4))
        XCTAssertNil(RememberedCamera(displayName: "FUJIFILM X-M5", slotCount: 0))
    }

    private func connect(_ faults: MockCameraFaults, defaults: UserDefaults) async -> CameraServices {
        var faults = faults
        faults.isInstant = true
        let manager = CameraServices()
        manager.slotReader.rememberedCameraDefaults = defaults
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    /// The count is the walk's, not the registry's: the registry assumes seven for an X-S20.
    func testAConnectRemembersTheWalkedSlotCount() async {
        let defaults = suite()
        var faults = MockCameraFaults(productName: "FUJIFILM X-S20", firmwareVersion: nil)
        faults.maxSelectableSlot = 4
        faults.presentsAsHardware = true

        let m = await connect(faults, defaults: defaults)

        XCTAssertEqual(m.session.connected?.isDemo, false, "precondition: a body on the cable")
        XCTAssertTrue(m.session.canPush, "precondition: a body the app writes to")
        XCTAssertEqual(m.session.model?.slotCount, 7, "precondition: the registry's assumption")
        XCTAssertEqual(RememberedCamera(defaults: defaults), RememberedCamera(displayName: "FUJIFILM X-S20", slotCount: 4))
    }

    func testTheDemoCameraIsNotRemembered() async {
        let defaults = suite()
        _ = await connect(MockCameraFaults(), defaults: defaults)
        XCTAssertNil(RememberedCamera(defaults: defaults))
    }

    /// The Camera tab's second demo resolves to a real registry body the app writes to, so only
    /// the transport says it is the demo. Remembered, it would size every chapter for a GFX100
    /// until the tester's own camera was next plugged in.
    func testTheGFX100DemoIsNotRemembered() async {
        let defaults = suite()
        let m = await connect(.gfx100WithoutKitchen, defaults: defaults)
        XCTAssertEqual(m.session.model?.id, "GFX100", "precondition: a real body's registry entry")
        XCTAssertTrue(m.session.canPush, "precondition: one the app writes to")
        XCTAssertEqual(m.session.connected?.isDemo, true)
        XCTAssertEqual(m.reports.report?.camera.transport, "demo")
        XCTAssertNil(RememberedCamera(defaults: defaults))
    }

    /// A chapter's fit only matters where it can be pushed.
    func testABodyTheAppDoesNotWriteToIsNotRemembered() async {
        let defaults = suite()
        var faults = MockCameraFaults.noSlotProtocolBody
        faults.presentsAsHardware = true
        let m = await connect(faults, defaults: defaults)
        XCTAssertFalse(m.session.canPush, "precondition: blocked in the registry on a recorded failure")
        XCTAssertNil(RememberedCamera(defaults: defaults))
    }
}
