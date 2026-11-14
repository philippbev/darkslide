import XCTest
@testable import FujiCookbook

/// The camera's slots as last read, kept for the Library: saved at the end of a slot walk on a
/// body the app writes to, per camera, and matched to library recipes for the slot badges.
@MainActor
final class CameraSlotSnapshotTests: XCTestCase {

    private var suites: [String] = []

    override func tearDown() {
        suites.forEach { UserDefaults().removePersistentDomain(forName: $0) }
        super.tearDown()
    }

    private func suite() -> UserDefaults {
        let name = "CameraSlotSnapshotTests.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func connect(_ faults: MockCameraFaults, defaults: UserDefaults) async -> CameraServices {
        var faults = faults
        faults.isInstant = true
        let manager = CameraServices()
        manager.slotReader.rememberedCameraDefaults = defaults
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    private func slot(_ index: Int, _ settings: RecipeSettings?, name: String? = nil) -> CameraSlotSnapshot.Slot {
        CameraSlotSnapshot.Slot(index: index, label: "C\(index)", isOccupied: settings != nil, name: name, settings: settings)
    }

    // MARK: Saved on a read

    func testAReadOfAWritableBodySavesItsSlots() async throws {
        let defaults = suite()
        var faults = MockCameraFaults(productName: "FUJIFILM X-S20", firmwareVersion: nil)
        faults.maxSelectableSlot = 4
        faults.presentsAsHardware = true

        let manager = await connect(faults, defaults: defaults)

        let snapshot = try XCTUnwrap(CameraSlotSnapshot.load(cameraName: "FUJIFILM X-S20", from: defaults))
        XCTAssertEqual(snapshot.slotCount, 4)
        XCTAssertEqual(snapshot.slots.map(\.label), manager.slotReader.slots.map(\.label))
        XCTAssertEqual(snapshot.occupiedCount, manager.slotReader.slots.filter(\.isOccupied).count)
    }

    func testTheDemoCameraLeavesNoSnapshot() async {
        let defaults = suite()
        _ = await connect(MockCameraFaults(), defaults: defaults)
        XCTAssertNil(defaults.string(forKey: CameraSlotSnapshot.storageKey))
    }

    func testASecondCameraKeepsTheFirstsSnapshot() {
        let defaults = suite()
        CameraSlotSnapshot(cameraName: "X100VI", slotCount: 7, readAt: Date(), slots: [slot(1, .neutral)]).save(to: defaults)
        CameraSlotSnapshot(cameraName: "X-T5", slotCount: 7, readAt: Date(), slots: []).save(to: defaults)
        XCTAssertEqual(CameraSlotSnapshot.load(cameraName: "X100VI", from: defaults)?.occupiedCount, 1)
        XCTAssertNotNil(CameraSlotSnapshot.load(cameraName: "X-T5", from: defaults))
    }

    func testUnreadableStorageReadsAsNothing() {
        XCTAssertTrue(CameraSlotSnapshot.all(from: "").isEmpty)
        XCTAssertTrue(CameraSlotSnapshot.all(from: "not json").isEmpty)
    }

    // MARK: Recipes in the slots

    /// Full settings, as a slot read gives them: the matcher only calls a match exact once enough
    /// fields were compared.
    private func full(_ simulation: FilmSimulation, clarity: Int) -> RecipeSettings {
        var settings = RecipeSettings.neutral
        settings.filmSimulation = simulation
        settings.clarity = clarity
        return settings
    }

    func testASlotBadgeGoesToTheRecipeWithTheSameSettings() {
        let chrome = Recipe(name: "Kodachrome", settings: full(.classicChrome, clarity: 2))
        let acros = Recipe(name: "Tri-X", settings: full(.acros, clarity: -1))
        let other = Recipe(name: "Unrelated", settings: full(.velvia, clarity: 4))
        let snapshot = CameraSlotSnapshot(cameraName: "X100VI", slotCount: 4, readAt: Date(),
                                          slots: [slot(1, chrome.settings), slot(2, nil), slot(3, acros.settings),
                                                  slot(4, full(.eterna, clarity: 5))])
        XCTAssertEqual(snapshot.slotLabels(for: [chrome, acros, other]), [chrome.uuid: "C1", acros.uuid: "C3"])
    }

    func testTwinRecipesShareABadgeOnlyThroughTheSlotName() {
        let settings = full(.classicChrome, clarity: 2)
        let first = Recipe(name: "Kodachrome", settings: settings)
        let twin = Recipe(name: "Kodachrome Copy", settings: settings)
        let named = CameraSlotSnapshot(cameraName: "X100VI", slotCount: 1, readAt: Date(),
                                       slots: [slot(1, settings, name: twin.effectiveCameraName)])
        XCTAssertEqual(named.slotLabels(for: [first, twin]), [twin.uuid: "C1"])

        let unnamed = CameraSlotSnapshot(cameraName: "X100VI", slotCount: 1, readAt: Date(),
                                         slots: [slot(1, settings, name: "SOMETHING ELSE")])
        XCTAssertEqual(unnamed.slotLabels(for: [first, twin]), [:], "no badge on a guess")
    }
}
