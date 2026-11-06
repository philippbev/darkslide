import XCTest
@testable import FujiCookbook

/// Two slots wearing one name is the only slot-name ambiguity that actually costs the user
/// anything: the camera shows an index and a name and nothing else. It's a warning rather than a
/// constraint — `uuid` is the identity, and a library may hold as many "Velvia" recipes as it likes.
@MainActor
final class PushCollisionTests: XCTestCase {

    private var namingModel: CameraModel {
        CameraModelRegistry.shared.models.first { $0.supportsSlotNaming }!
    }

    private func collisions(_ assignments: [Int: Recipe]) -> [String: [Int]] {
        PushView.slotNameCollisions(
            assignments: assignments.mapValues(\.uuid),
            recipes: Array(assignments.values),
            model: namingModel)
    }

    /// The case the library can't show you: two names that look nothing alike in a list, and are
    /// the same 25 characters once the camera has them.
    func testTwoNamesThatTruncateAlikeCollide() {
        let a = Recipe(name: "Kodachrome 64 Warm Tones In Shade")
        let b = Recipe(name: "Kodachrome 64 Warm Tones In Sunlight")
        XCTAssertNotEqual(a.name, b.name, "precondition: distinct in the library")
        XCTAssertEqual(a.effectiveCameraName, b.effectiveCameraName, "precondition: same on the camera")

        XCTAssertEqual(collisions([1: a, 3: b]), ["Kodachrome 64 Warm Tones": [1, 3]])
    }

    func testDistinctNamesDoNotCollide() {
        XCTAssertTrue(collisions([1: Recipe(name: "Velvia Daily"),
                                  2: Recipe(name: "Classic Neg Evening")]).isEmpty)
    }

    /// Case differs, so the camera shows two visibly different labels. Not a collision — unlike
    /// `DuplicateResolver`, which is deliberately case-insensitive because it asks a different
    /// question ("is this the same recipe", not "can I read these apart").
    func testCaseDifferencesAreNotACollision() {
        XCTAssertTrue(collisions([1: Recipe(name: "VELVIA"), 2: Recipe(name: "Velvia")]).isEmpty)
    }

    /// Nothing stops the same recipe being assigned to two slots, and pushing it produces two
    /// identical slots with no indication.
    func testTheSameRecipeInTwoSlotsIsReported() {
        let recipe = Recipe(name: "Velvia Daily")
        let found = PushView.slotNameCollisions(assignments: [1: recipe.uuid, 4: recipe.uuid],
                                                recipes: [recipe],
                                                model: namingModel)
        XCTAssertEqual(found, ["Velvia Daily": [1, 4]])
    }

    func testACustomOverrideIsWhatGetsCompared() {
        // Different recipe names, but both authors pinned the same label.
        let a = Recipe(name: "Velvia Daily", cameraName: "SUMMER")
        let b = Recipe(name: "Classic Neg Evening", cameraName: "SUMMER")
        XCTAssertEqual(collisions([2: a, 5: b]), ["SUMMER": [2, 5]])
    }

    /// The slot lists are sorted, so the message reads "C1 and C4" rather than in dictionary order.
    func testReportedSlotsAreSorted() {
        let recipe = Recipe(name: "Velvia Daily")
        let found = PushView.slotNameCollisions(assignments: [6: recipe.uuid, 2: recipe.uuid, 4: recipe.uuid],
                                                recipes: [recipe],
                                                model: namingModel)
        XCTAssertEqual(found["Velvia Daily"], [2, 4, 6])
    }

    func testABodyThatCannotNameSlotsHasNothingToCollide() throws {
        let mute = try XCTUnwrap(CameraModelRegistry.shared.models.first { !$0.supportsSlotNaming },
                                 "the test needs a registry body that cannot name slots")
        let recipe = Recipe(name: "Velvia Daily")
        XCTAssertTrue(PushView.slotNameCollisions(assignments: [1: recipe.uuid, 2: recipe.uuid],
                                                  recipes: [recipe],
                                                  model: mute).isEmpty)
    }

    /// An assignment can outlive the recipe it points at (deleted mid-session); it must be skipped,
    /// not trapped on.
    func testAnAssignmentToADeletedRecipeIsIgnored() {
        let recipe = Recipe(name: "Velvia Daily")
        let found = PushView.slotNameCollisions(assignments: [1: recipe.uuid, 2: UUID()],
                                                recipes: [recipe],
                                                model: namingModel)
        XCTAssertTrue(found.isEmpty)
    }
}
