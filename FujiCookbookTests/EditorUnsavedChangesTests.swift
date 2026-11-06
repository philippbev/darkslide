import XCTest
@testable import FujiCookbook

/// The recipe and chapter editors refuse a swipe that would throw away an edit, and ask before
/// Cancel does; both read whether the draft holds a change. A draft that misses a change loses it
/// without a word, and one that reports a change where there is none asks on every Cancel.
@MainActor
final class EditorUnsavedChangesTests: XCTestCase {

    // MARK: Recipe

    private func savedRecipe() -> Recipe {
        Recipe(name: "Kodachrome",
               cameraName: "KODA",
               notes: "Bright sun.",
               tags: ["daylight", "street"],
               isFavorite: true,
               credit: "A Blog",
               authoredForModelID: "X-T50",
               settings: RecipeSettings(filmSimulation: .classicChrome,
                                        grain: GrainEffect(strength: .weak, size: .small),
                                        whiteBalance: WhiteBalance(mode: .daylight, shiftRed: 2,
                                                                   shiftBlue: -4, kelvin: nil),
                                        highlightTone: -1, sharpness: 1))
    }

    func testAnExistingRecipeOpensWithNoChanges() {
        XCTAssertFalse(RecipeDraft(from: savedRecipe()).hasChanges)
    }

    /// Opening fills the six fields a recipe must carry with their defaults. That is where the form
    /// starts, not an edit, or every scanned recipe would ask before Cancel.
    func testTheOpeningDefaultsAreNotAChange() {
        let draft = RecipeDraft(from: Recipe(name: "Scanned", settings: RecipeSettings()))
        XCTAssertEqual(draft.filmSim, .provia, "precondition: the draft defaulted an absent field")
        XCTAssertFalse(draft.hasChanges)
    }

    /// The editor's own starting point for a new recipe (`LibraryView.createRecipe`).
    func testANewUntouchedRecipeHasNoChanges() {
        XCTAssertFalse(RecipeDraft(from: Recipe(name: "New Recipe")).hasChanges)
    }

    func testEditingTheNameIsAChangeUntilItIsUndone() {
        var draft = RecipeDraft(from: savedRecipe())

        draft.name = "Kodachrome 64"
        XCTAssertTrue(draft.hasChanges)

        draft.name = "Kodachrome"
        XCTAssertFalse(draft.hasChanges, "typing the old name back leaves nothing to lose")
    }

    func testChangingASettingIsAChange() {
        var draft = RecipeDraft(from: savedRecipe())
        draft.filmSim = .acros
        XCTAssertTrue(draft.hasChanges, "film simulation")

        draft = RecipeDraft(from: savedRecipe())
        draft.wbShiftB = -3
        XCTAssertTrue(draft.hasChanges, "white balance shift")
    }

    /// Setting a field the recipe left unset is an edit even when the value is 0: the draft keeps
    /// "not set" and 0 apart, and so does Save.
    func testSettingAnUnsetFieldToZeroIsAChange() {
        var draft = RecipeDraft(from: savedRecipe())
        XCTAssertNil(draft.clarity, "precondition")

        draft.clarity = 0
        XCTAssertTrue(draft.hasChanges)
    }

    func testChangingTheCameraProfileOrMetadataIsAChange() {
        var draft = RecipeDraft(from: savedRecipe())
        draft.modelID = nil
        XCTAssertTrue(draft.hasChanges, "camera profile")

        draft = RecipeDraft(from: savedRecipe())
        draft.isFavorite = false
        XCTAssertTrue(draft.hasChanges, "favorite")

        draft = RecipeDraft(from: savedRecipe())
        draft.cameraName = ""
        XCTAssertTrue(draft.hasChanges, "camera slot name")
    }

    // MARK: Photos

    private func stagedPhoto() -> PhotoDraft {
        PhotoDraft(id: UUID(), full: Data(), thumbnail: Data(), existing: nil)
    }

    func testStagedPhotosOpenWithNoChanges() {
        XCTAssertFalse(StagedPhotos([stagedPhoto(), stagedPhoto()]).hasChanges)
        XCTAssertFalse(StagedPhotos([]).hasChanges)
    }

    func testAddingAPhotoIsAChangeUntilItIsRemoved() {
        var photos = StagedPhotos([stagedPhoto()])

        photos.drafts.append(stagedPhoto())
        XCTAssertTrue(photos.hasChanges)

        photos.drafts.removeLast()
        XCTAssertFalse(photos.hasChanges)
    }

    func testRemovingOrMovingAPhotoIsAChange() {
        var photos = StagedPhotos([stagedPhoto(), stagedPhoto()])
        photos.drafts.removeFirst()
        XCTAssertTrue(photos.hasChanges, "removed")

        photos = StagedPhotos([stagedPhoto(), stagedPhoto()])
        photos.drafts.reverse()
        XCTAssertTrue(photos.hasChanges, "moved: the order is the order Save writes")
    }

    // MARK: Chapter

    private let first = UUID()
    private let second = UUID()

    private func savedChapter() -> Chapter {
        Chapter(name: "Summer", recipeUUIDs: [first, second])
    }

    func testAnExistingChapterOpensWithNoChanges() {
        XCTAssertFalse(ChapterDraft(from: savedChapter()).hasChanges)
    }

    /// The editor's own starting point for a new chapter (`ChaptersListView.createChapter`).
    func testANewUntouchedChapterHasNoChanges() {
        XCTAssertFalse(ChapterDraft(from: Chapter(name: "New Chapter")).hasChanges)
    }

    func testRenamingAChapterIsAChangeUntilItIsUndone() {
        var draft = ChapterDraft(from: savedChapter())

        draft.name = "Winter"
        XCTAssertTrue(draft.hasChanges)

        draft.name = "Summer"
        XCTAssertFalse(draft.hasChanges)
    }

    func testAddingRemovingOrMovingASlotIsAChange() {
        var draft = ChapterDraft(from: savedChapter())
        draft.recipeUUIDs.append(UUID())
        XCTAssertTrue(draft.hasChanges, "added")

        draft = ChapterDraft(from: savedChapter())
        draft.recipeUUIDs.removeLast()
        XCTAssertTrue(draft.hasChanges, "removed")

        draft = ChapterDraft(from: savedChapter())
        draft.recipeUUIDs.reverse()
        XCTAssertTrue(draft.hasChanges, "moved: position is the camera slot")
    }
}
