import XCTest
import SwiftData
@testable import FujiCookbook

/// How a recipe's camera slot name behaves as the recipe is renamed, duplicated, exported and
/// imported. The rule: the generated default follows the recipe name; a name the user typed does
/// not, ever.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#0xd18d-bank-name`.
@MainActor
final class CameraSlotNamePersistenceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelStore.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        return ModelContext(container)
    }

    // MARK: The default follows the name

    func testANewRecipeGetsASlotNameWithoutAnyoneAskingForOne() {
        let recipe = Recipe(name: "Kodachrome 64 Warm")
        XCTAssertEqual(recipe.slotNameDefault, "Kodachrome 64 Warm")
        XCTAssertEqual(recipe.effectiveCameraName, "Kodachrome 64 Warm")
        XCTAssertFalse(recipe.hasCustomCameraName)
    }

    /// Diacritics fold, the em dash and emoji go, and the gaps they leave don't become double
    /// spaces — all before anything reaches the camera.
    func testTheDefaultIsSanitizedOnTheWayIn() {
        let recipe = Recipe(name: "Provençal — Sunset 🌅 Light")
        XCTAssertEqual(recipe.effectiveCameraName, "Provencal Sunset Light")
    }

    func testRenamingMovesTheGeneratedDefault() {
        let recipe = Recipe(name: "Velvia Daily")
        recipe.setName("Classic Neg Evening")
        XCTAssertEqual(recipe.effectiveCameraName, "Classic Neg Evening")
    }

    /// A name with nothing the camera can show takes its default from the film simulation, so a
    /// settings change has to move the default too.
    func testChangingSettingsMovesADefaultBuiltFromTheFilmSimulation() {
        let recipe = Recipe(name: "日本語", settings: RecipeSettings(filmSimulation: .velvia))
        XCTAssertEqual(recipe.effectiveCameraName, "Velvia / Vivid")

        recipe.setSettings(RecipeSettings(filmSimulation: .classicChrome))

        XCTAssertEqual(recipe.slotNameDefault, "Classic Chrome")
        XCTAssertEqual(recipe.effectiveCameraName, "Classic Chrome")
    }

    // MARK: A name the user typed is frozen

    func testRenamingDoesNotMoveANameTheUserTyped() {
        let recipe = Recipe(name: "Velvia Daily", cameraName: "VELVIA PUNCH")
        XCTAssertTrue(recipe.hasCustomCameraName)

        recipe.setName("Something Else Entirely")

        XCTAssertEqual(recipe.effectiveCameraName, "VELVIA PUNCH", "the user's name must not move")
        XCTAssertEqual(recipe.slotNameDefault, "Something Else Entirely",
                       "but the default underneath still tracks, ready if they clear the override")
    }

    func testClearingAnOverrideFallsBackToTheCurrentName() {
        let recipe = Recipe(name: "Velvia Daily", cameraName: "VELVIA PUNCH")
        recipe.setName("Classic Neg Evening")
        recipe.cameraName = nil
        XCTAssertEqual(recipe.effectiveCameraName, "Classic Neg Evening")
    }

    /// A push names the bank it writes, and an empty `0xD18D` would clear the bank's name instead,
    /// so a name that resolves to nothing falls back to something.
    func testTheResolvedNameIsNeverEmpty() {
        XCTAssertFalse(Recipe(name: "日本語").effectiveCameraName.isEmpty)
        XCTAssertFalse(Recipe(name: "").effectiveCameraName.isEmpty)
        XCTAssertFalse(Recipe(name: "Velvia", cameraName: "   ").effectiveCameraName.isEmpty)
        XCTAssertFalse(Recipe(name: "Velvia", cameraName: "").effectiveCameraName.isEmpty)
    }

    func testAWhitespaceOnlyOverrideCountsAsNoOverride() {
        let recipe = Recipe(name: "Velvia Daily", cameraName: "   ")
        XCTAssertFalse(recipe.hasCustomCameraName)
        XCTAssertEqual(recipe.effectiveCameraName, "Velvia Daily")
    }

    /// A name with nothing ASCII in it falls back to the film simulation, so two such recipes are
    /// still told apart on the camera instead of both reading "Recipe".
    func testANonLatinNameFallsBackToTheFilmSimulation() {
        let recipe = Recipe(name: "日本語", settings: RecipeSettings(filmSimulation: .classicNeg))
        XCTAssertEqual(recipe.effectiveCameraName, FilmSimulation.classicNeg.displayName)
    }

    // MARK: Export / import

    func testExportCarriesTheGeneratedNameAndSaysItIsNotCustom() {
        let portable = RecipePortability.portable(from: Recipe(name: "Velvia Daily"))
        XCTAssertEqual(portable.cameraName, "Velvia Daily")
        XCTAssertEqual(portable.cameraNameIsCustom, false)
    }

    func testAGeneratedNameDoesNotArriveAsAnOverride() {
        let portable = RecipePortability.portable(from: Recipe(name: "Velvia Daily"))
        let imported = RecipePortability.makeRecipe(from: portable)
        XCTAssertFalse(imported.hasCustomCameraName, "an automatic name must stay automatic")
        XCTAssertEqual(imported.effectiveCameraName, "Velvia Daily")
    }

    func testACustomNameSurvivesARoundTrip() {
        let portable = RecipePortability.portable(from: Recipe(name: "Velvia Daily",
                                                               cameraName: "VELVIA PUNCH"))
        XCTAssertEqual(portable.cameraNameIsCustom, true)
        let imported = RecipePortability.makeRecipe(from: portable)
        XCTAssertTrue(imported.hasCustomCameraName)
        XCTAssertEqual(imported.effectiveCameraName, "VELVIA PUNCH")
    }

    /// Files written before the flag existed got their `cameraName` from a user typing it into the
    /// old editor, so a present-but-unflagged name is an override.
    func testALegacyFileWithoutTheFlagIsReadAsCustom() {
        let legacy = PortableRecipe(name: "Velvia Daily",
                                    cameraName: "VELVIA PUNCH",
                                    settings: .neutral)
        XCTAssertNil(legacy.cameraNameIsCustom, "precondition: the key is absent")
        XCTAssertTrue(RecipePortability.makeRecipe(from: legacy).hasCustomCameraName)
    }

    // MARK: Importer

    /// The bug this fixes: `.keepBoth` renamed the recipe *after* its slot name was generated, so
    /// "Velvia Daily (2)" went to the camera labelled "Velvia Daily" — the same as the recipe it
    /// was just disambiguated from.
    func testKeepBothGivesTheDisambiguatedRecipeItsOwnSlotName() throws {
        let context = try makeContext()
        let existing = Recipe(name: "Velvia Daily")
        context.insert(existing)

        let incoming = PortableRecipe(name: "Velvia Daily", settings: .neutral)
        var usedNameKeys: Set<String> = [RecipeImporter.nameKey("Velvia Daily")]
        let result = RecipeImporter.apply(incoming,
                                          resolution: .keepBoth,
                                          match: DuplicateMatch(incoming: incoming,
                                                                existing: existing,
                                                                reason: .sameName),
                                          into: context,
                                          usedNameKeys: &usedNameKeys)

        let added = try XCTUnwrap(result.recipe)
        XCTAssertEqual(added.name, "Velvia Daily (2)")
        XCTAssertEqual(added.effectiveCameraName, "Velvia Daily (2)",
                       "the slot name must follow the disambiguated name")
        XCTAssertNotEqual(added.effectiveCameraName, existing.effectiveCameraName)
    }

    /// The regression the custom-ness flag exists to prevent: once every export carries a generated
    /// name, an importer that can't tell generated from chosen replaces the local user's name.
    func testOverwriteDoesNotReplaceALocalCustomNameWithAnAutomaticOne() throws {
        let context = try makeContext()
        let existing = Recipe(name: "Velvia Daily", cameraName: "MY VELVIA")
        context.insert(existing)

        // Exactly what an export of an un-customized recipe looks like.
        let incoming = PortableRecipe(name: "Velvia Daily",
                                      cameraName: "Velvia Daily",
                                      cameraNameIsCustom: false,
                                      settings: .neutral)
        var usedNameKeys: Set<String> = []
        _ = RecipeImporter.apply(incoming,
                                 resolution: .overwrite,
                                 match: DuplicateMatch(incoming: incoming,
                                                       existing: existing,
                                                       reason: .sameName),
                                 into: context,
                                 usedNameKeys: &usedNameKeys)

        XCTAssertEqual(existing.effectiveCameraName, "MY VELVIA")
    }

    func testOverwriteDoesAcceptAnIncomingCustomName() throws {
        let context = try makeContext()
        let existing = Recipe(name: "Velvia Daily")
        context.insert(existing)

        let incoming = PortableRecipe(name: "Velvia Punchy",
                                      cameraName: "AUTHOR PICK",
                                      cameraNameIsCustom: true,
                                      settings: .neutral)
        var usedNameKeys: Set<String> = []
        _ = RecipeImporter.apply(incoming,
                                 resolution: .overwrite,
                                 match: DuplicateMatch(incoming: incoming,
                                                       existing: existing,
                                                       reason: .sameName),
                                 into: context,
                                 usedNameKeys: &usedNameKeys)

        XCTAssertEqual(existing.effectiveCameraName, "AUTHOR PICK")
    }

    /// Overwriting used to drop the credit on the floor.
    func testOverwriteKeepsAttribution() throws {
        let context = try makeContext()
        let existing = Recipe(name: "Velvia Daily")
        context.insert(existing)

        let incoming = PortableRecipe(name: "Velvia Daily", credit: "Northlight", settings: .neutral)
        var usedNameKeys: Set<String> = []
        _ = RecipeImporter.apply(incoming,
                                 resolution: .overwrite,
                                 match: DuplicateMatch(incoming: incoming,
                                                       existing: existing,
                                                       reason: .sameName),
                                 into: context,
                                 usedNameKeys: &usedNameKeys)

        XCTAssertEqual(existing.displayCredit, "Northlight")
    }

    // MARK: Editor round trip

    func testTheEditorStoresAnOverrideOnlyWhenOneWasTyped() {
        let recipe = Recipe(name: "Velvia Daily")
        var draft = RecipeDraft(from: recipe)
        XCTAssertEqual(draft.cameraName, "", "an automatic name leaves the field empty")
        XCTAssertEqual(draft.generatedSlotName, "Velvia Daily")

        draft.name = "Classic Neg Evening"
        XCTAssertEqual(draft.generatedSlotName, "Classic Neg Evening",
                       "the grey placeholder tracks the Name field as it's typed")

        draft.apply(to: recipe)
        XCTAssertNil(recipe.cameraName)
        XCTAssertEqual(recipe.effectiveCameraName, "Classic Neg Evening")

        draft.cameraName = "MY NAME"
        draft.apply(to: recipe)
        XCTAssertEqual(recipe.cameraName, "MY NAME")
        XCTAssertTrue(recipe.hasCustomCameraName)
    }

    /// A legacy override longer than the current limit is loaded intact rather than truncated on
    /// open — an edit the user never asked for. It's clamped at the wire instead.
    func testOpeningTheEditorDoesNotTruncateALegacyOverride() {
        let long = String(repeating: "A", count: 40)
        let recipe = Recipe(name: "Velvia Daily", cameraName: long)
        XCTAssertEqual(RecipeDraft(from: recipe).cameraName, long)
    }
}

/// Import-time disambiguation: "keep both" has to mean both are distinguishable *on the camera*,
/// not just in the library list.
@MainActor
final class ImportDisambiguationTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelStore.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        return ModelContext(container)
    }

    @discardableResult
    private func keepBoth(_ incoming: PortableRecipe,
                          against existing: Recipe,
                          in context: ModelContext,
                          keys: inout Set<String>) -> Recipe? {
        RecipeImporter.apply(incoming,
                             resolution: .keepBoth,
                             match: DuplicateMatch(incoming: incoming,
                                                   existing: existing,
                                                   reason: .sameName),
                             into: context,
                             usedNameKeys: &keys).recipe
    }

    /// The name is disambiguated in the library, but both recipes' slot names truncate at 25 — so
    /// the camera used to show one identical label for both.
    func testALongNameStillGetsADistinctSlotName() throws {
        let context = try makeContext()
        let existing = Recipe(name: "A Very Long Recipe Name That Overflows")
        context.insert(existing)

        var keys: Set<String> = [RecipeImporter.nameKey(existing.name)]
        let incoming = PortableRecipe(name: "A Very Long Recipe Name That Overflows", settings: .neutral)
        let added = try XCTUnwrap(keepBoth(incoming, against: existing, in: context, keys: &keys))

        XCTAssertEqual(added.name, "A Very Long Recipe Name That Overflows (2)")
        XCTAssertNotEqual(added.effectiveCameraName, existing.effectiveCameraName,
                          "both landed on the camera as “\(existing.effectiveCameraName)”")
        XCTAssertEqual(added.effectiveCameraName, "A Very Long Recipe Na (2)")
    }

    /// `DuplicateResolver` matches case-insensitively; the disambiguator used to compare exactly,
    /// so this pair was detected as a duplicate and then left with two identical slot names.
    func testACaseOnlyDifferenceIsStillDisambiguated() throws {
        let context = try makeContext()
        let existing = Recipe(name: "Velvia Daily")
        context.insert(existing)

        var keys: Set<String> = [RecipeImporter.nameKey(existing.name)]
        let incoming = PortableRecipe(name: "velvia daily", settings: .neutral)
        let added = try XCTUnwrap(keepBoth(incoming, against: existing, in: context, keys: &keys))

        XCTAssertEqual(added.name, "velvia daily (2)")
        XCTAssertNotEqual(added.effectiveCameraName, existing.effectiveCameraName)
    }

    /// A custom override bypasses `setName` entirely — `effectiveCameraName` prefers it — so the
    /// library rename never reached the camera.
    func testACollidingCustomOverrideIsDisambiguatedToo() throws {
        let context = try makeContext()
        let existing = Recipe(name: "Velvia Daily", cameraName: "VELVIA")
        context.insert(existing)

        var keys: Set<String> = [RecipeImporter.nameKey(existing.name)]
        let incoming = PortableRecipe(name: "Velvia Daily",
                                      cameraName: "VELVIA",
                                      cameraNameIsCustom: true,
                                      settings: .neutral)
        let added = try XCTUnwrap(keepBoth(incoming, against: existing, in: context, keys: &keys))

        XCTAssertEqual(added.effectiveCameraName, "VELVIA (2)")
        XCTAssertNotEqual(added.effectiveCameraName, existing.effectiveCameraName)
    }

    /// An override the author already made distinct is theirs; renaming it would be presumptuous.
    func testADistinctCustomOverrideIsLeftAlone() throws {
        let context = try makeContext()
        let existing = Recipe(name: "Velvia Daily", cameraName: "VELVIA")
        context.insert(existing)

        var keys: Set<String> = [RecipeImporter.nameKey(existing.name)]
        let incoming = PortableRecipe(name: "Velvia Daily",
                                      cameraName: "VELVIA PUNCHY",
                                      cameraNameIsCustom: true,
                                      settings: .neutral)
        let added = try XCTUnwrap(keepBoth(incoming, against: existing, in: context, keys: &keys))

        XCTAssertEqual(added.effectiveCameraName, "VELVIA PUNCHY")
    }
}
