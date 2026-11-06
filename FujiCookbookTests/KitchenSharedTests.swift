import XCTest
@testable import FujiCookbook

/// What Develop and Test Kitchen share instead of each keeping a copy: the slot tag on a chosen
/// recipe, the picker's list, and the cell a guided run records for a file it couldn't read.
@MainActor
final class KitchenSharedTests: XCTestCase {

    private func connected() async -> CameraServices {
        var faults = MockCameraFaults()
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    func testAnUnreadableFileIsAFailedCellTheReportCanName() {
        let result = ConversionResult.unreadableFile(named: "DSCF0001.RAF")
        XCTAssertEqual(result.sourceFilename, "DSCF0001.RAF")
        XCTAssertFalse(result.success)
        XCTAssertNil(result.recoveryFileURL)
        XCTAssertEqual(result.errorMessage, "Couldn't read the selected RAW file. Choose the file again.")
        XCTAssertEqual(result.evidence.failureReason, "file_unreadable",
                       "the report's display mapping keys on this reason")
    }

    func testSlotLabelNamesOnlyASlotThatHoldsARecipe() async throws {
        let manager = await connected()
        let occupied = try XCTUnwrap(manager.occupiedSlots.first)
        XCTAssertEqual(manager.slotLabel(for: .slot(occupied.index)), occupied.label)

        let empty = try XCTUnwrap(manager.slotReader.slots.first { !$0.isOccupied },
                                  "the demo camera starts with empty slots as well as programmed ones")
        XCTAssertNil(manager.slotLabel(for: .slot(empty.index)))
        XCTAssertNil(manager.slotLabel(for: .library(UUID())))
        XCTAssertNil(manager.slotLabel(for: nil))
    }

    func testChoicesListProgrammedSlotsBeforeLibraryRecipes() async throws {
        let manager = await connected()
        let recipe = Recipe(name: "Library Recipe")
        let choices = RecipeChoice.choices(camera: manager, recipes: [recipe])

        XCTAssertEqual(choices.count, manager.occupiedSlots.count + 1)
        XCTAssertEqual(choices.prefix(manager.occupiedSlots.count).map(\.ref),
                       manager.occupiedSlots.map { .slot($0.index) })
        XCTAssertEqual(choices.last?.ref, .library(recipe.uuid))
    }
}
