import XCTest
@testable import FujiCookbook

/// The Camera Profile footer's promise: what it says Save will drop or change is exactly what
/// `assembleSettings()` then does, because both come from the same assembly.
@MainActor
final class RecipeDraftProfileChangeTests: XCTestCase {

    /// A Generic recipe using the late gen-IV controls, with a half-step tone and a sized grain.
    private func draft(profile: String?) -> RecipeDraft {
        let settings = RecipeSettings(filmSimulation: .classicChrome,
                                      grain: GrainEffect(strength: .weak, size: .large),
                                      colorChromeEffect: .strong, colorChromeFXBlue: .strong,
                                      highlightTone: 1.5, clarity: 2)
        var draft = RecipeDraft(from: Recipe(name: "Wide", authoredForModelID: nil, settings: settings))
        draft.modelID = profile
        return draft
    }

    func testGenericChangesNothing() {
        XCTAssertEqual(draft(profile: nil).changesOnSave(), [])
    }

    func testAProfileWithEveryControlChangesNothing() {
        XCTAssertEqual(draft(profile: "X-T50").changesOnSave(), [])
        XCTAssertEqual(draft(profile: "X-T4").changesOnSave(), [])
    }

    /// The X-T3 has no FX Blue or Clarity, whole-step tones and grain strength only — listed in
    /// field order, as the recipe's parameter table lists them.
    func testTheXT3ListsDropsAndChanges() {
        XCTAssertEqual(draft(profile: "X-T3").changesOnSave(), [
            .changed(.grain, from: "Weak, Large", to: "Weak"),
            .dropped(.colorChromeFXBlue, value: "Strong"),
            .changed(.highlightTone, from: "+1.5", to: "+2"),
            .dropped(.clarity, value: "+2")
        ])
    }

    /// Dropping a value the camera renders no differently from its absence is not worth a warning:
    /// a Clarity of 0, or toning at 0, on a body without the control.
    func testNeutralValuesAreNotListedAsDropped() {
        let settings = RecipeSettings(filmSimulation: .acros, monochromaticColorWC: 0,
                                      monochromaticColorMG: 0, clarity: 0)
        var draft = RecipeDraft(from: Recipe(name: "Neutral", authoredForModelID: nil, settings: settings))
        draft.modelID = "X-T20"
        XCTAssertEqual(draft.changesOnSave(), [])
    }

    /// The X100V has every control in the fixture; only its whole-step tones change a value.
    func testTheX100VListsOnlyTheToneChange() {
        XCTAssertEqual(draft(profile: "X100V").changesOnSave(),
                       [.changed(.highlightTone, from: "+1.5", to: "+2")])
    }

    /// A legacy profile drops the controls it lacks; its tones have no range, so the half step is
    /// kept rather than rounded (the editor falls back to its Generic ranges there).
    func testALegacyProfileDropsGrainAndKeepsTheHalfStepTone() {
        XCTAssertEqual(draft(profile: "X-Pro1").changesOnSave(), [
            .dropped(.grain, value: "Weak, Large"),
            .dropped(.colorChromeEffect, value: "Strong"),
            .dropped(.colorChromeFXBlue, value: "Strong"),
            .dropped(.clarity, value: "+2")
        ])
    }

    /// An unsupported white balance mode is kept by Save, so the list says nothing about it; the
    /// White Balance footer carries that warning instead.
    func testAnUnsupportedWhiteBalanceModeIsKeptAndNotListed() {
        let settings = RecipeSettings(filmSimulation: .provia,
                                      whiteBalance: WhiteBalance(mode: .autoWhitePriority, shiftRed: 0, shiftBlue: 0, kelvin: nil))
        var draft = RecipeDraft(from: Recipe(name: "WB", authoredForModelID: nil, settings: settings))
        draft.modelID = "X100V"
        XCTAssertEqual(draft.changesOnSave(), [])
        XCTAssertEqual(draft.assembleSettings().whiteBalance?.mode, .autoWhitePriority)
        XCTAssertEqual(draft.unsupportedWhiteBalanceMode, .autoWhitePriority)
        draft.modelID = "X-T5"
        XCTAssertNil(draft.unsupportedWhiteBalanceMode)
        draft.modelID = nil
        XCTAssertNil(draft.unsupportedWhiteBalanceMode, "Generic has every mode")
    }

    /// The list is a prediction of Save, so Save has to agree with it field by field.
    func testEveryListedChangeIsWhatSaveWrites() {
        let draft = draft(profile: "X-T3")
        let saved = draft.assembleSettings()
        let changes = draft.changesOnSave()
        XCTAssertFalse(changes.isEmpty, "the fixture must exercise both kinds")
        for change in changes {
            switch change {
            case .dropped(let field, _):
                XCTAssertNil(RecipeSettingsFormatter.valueString(for: field, in: saved), "\(field) is gone after Save")
            case .changed(let field, _, let to):
                XCTAssertEqual(RecipeSettingsFormatter.valueString(for: field, in: saved), to,
                               "\(field) is saved as the notice says")
            }
        }
    }
}
