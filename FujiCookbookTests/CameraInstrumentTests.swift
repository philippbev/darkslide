import XCTest
@testable import FujiCookbook

/// What the Camera tab's instrument says: the device panel, the chosen slot, the knobs and data
/// sheet of its card, the import key's count and the action bar's status.
final class CameraInstrumentTests: XCTestCase {

    private typealias Instrument = CameraInstrument

    private func slot(_ index: Int, _ settings: RecipeSettings?, name: String? = nil) -> CameraSlot {
        CameraSlot(index: index, label: "C\(index)", name: name, isOccupied: settings != nil,
                   settings: settings, rawProperties: [:], unsupportedFields: [:])
    }

    /// Full settings, as a slot read gives them: the matcher only calls a match exact once enough
    /// fields were compared.
    private func full(_ simulation: FilmSimulation, color: Int = 0) -> RecipeSettings {
        var settings = RecipeSettings.neutral
        settings.filmSimulation = simulation
        settings.color = color
        return settings
    }

    // MARK: Panel

    func testThePanelLineNamesFirmwareTransportAndRange() {
        XCTAssertEqual(Instrument.panelMeta(firmware: "1.31", isDemo: false, isReconnecting: false, slotCount: 7),
                       "FW 1.31   USB   C1–C7")
        XCTAssertEqual(Instrument.panelMeta(firmware: nil, isDemo: true, isReconnecting: false, slotCount: 4),
                       "Demo   C1–C4")
        XCTAssertFalse(Instrument.panelMeta(firmware: "1.31", isDemo: false, isReconnecting: false, slotCount: 0).contains("C1"),
                       "no range when the count is unknown")
    }

    func testAReconnectingCameraIsNeverCalledConnected() {
        XCTAssertEqual(Instrument.panelMeta(firmware: "1.31", isDemo: false, isReconnecting: true, slotCount: 7),
                       "FW 1.31   Reconnecting   C1–C7")
        XCTAssertEqual(Instrument.panelLEDs(isLive: false, canWrite: true).map(\.isOn), [false, false])
        XCTAssertEqual(Instrument.panelLEDs(isLive: true, canWrite: false).map(\.isOn), [true, false])
        XCTAssertEqual(Instrument.panelLEDs(isLive: true, canWrite: true).map(\.label), ["Link", "R/W"])
    }

    func testACardReaderIsLinkedButNotWritable() {
        XCTAssertEqual(Instrument.cardReaderLEDs().map(\.isOn), [true, false],
                       "plugged in and open, but the slots aren't reachable in that mode")
        XCTAssertTrue(Instrument.cardReaderMeta.contains("Card Reader"))
    }

    // MARK: Selection

    func testWithNoChoiceTheFirstSetSlotIsShown() {
        let slots = [slot(1, nil), slot(2, full(.acros)), slot(3, full(.velvia))]
        XCTAssertEqual(Instrument.selection(nil, in: slots), 2)
        XCTAssertEqual(Instrument.selection(3, in: slots), 3)
        XCTAssertEqual(Instrument.selection(9, in: slots), 2, "a slot that is gone falls back")
        XCTAssertEqual(Instrument.selection(nil, in: [slot(1, nil), slot(2, nil)]), 1)
        XCTAssertNil(Instrument.selection(nil, in: []))
    }

    // MARK: Library

    func testTheImportKeyCountsSetSlotsTheLibraryLacks() {
        let chrome = Recipe(name: "Kodachrome", settings: full(.classicChrome, color: 2))
        let slots = [slot(1, chrome.settings), slot(2, nil), slot(3, full(.eterna, color: -3)), slot(4, full(.acros))]
        let inLibrary = Instrument.libraryRecipes(for: slots, in: [chrome])
        XCTAssertEqual(inLibrary.mapValues(\.uuid), [1: chrome.uuid])
        XCTAssertEqual(Instrument.newSlotCount(slots, inLibrary: inLibrary), 2)
    }

    func testTheCardSaysWhetherTheLibraryHoldsTheSlot() {
        let recipe = Recipe(name: "Kodachrome", settings: full(.classicChrome))
        recipe.archiveNumber = 24
        XCTAssertEqual(Instrument.footer(isOccupied: true, libraryRecipe: recipe), "In library   Kodachrome")
        XCTAssertEqual(Instrument.footer(isOccupied: true, libraryRecipe: nil), "Not in library")
        XCTAssertEqual(Instrument.footer(isOccupied: false, libraryRecipe: nil), "")
        XCTAssertEqual(Instrument.sideFields(isOccupied: true, libraryRecipe: recipe),
                       [DSDataField(label: "State", value: "Set", led: true),
                        DSDataField(label: "Archive", value: "024")])
        XCTAssertEqual(Instrument.sideFields(isOccupied: false, libraryRecipe: nil).map(\.value), ["Empty", "—"])
    }

    // MARK: Knobs

    func testColorTurnsLinearlyFromMinusFourToPlusFour() {
        let knobs = { (color: Int) in Instrument.knobs(for: self.full(.provia, color: color)) }
        XCTAssertEqual(knobs(-4)[0].position, 0)
        XCTAssertEqual(knobs(0)[0].position, 0.5)
        XCTAssertEqual(knobs(4)[0].position, 1)
        XCTAssertEqual(knobs(2)[0].value, "+2")
        XCTAssertEqual(knobs(-2)[0].value, "\u{2212}2")
    }

    func testGrainAndDynamicRangeStepEvenly() {
        var settings = full(.classicNeg)
        settings.grain = GrainEffect(strength: .weak, size: .large)
        settings.dynamicRange = .dr400
        let knobs = Instrument.knobs(for: settings)
        XCTAssertEqual(knobs.map(\.label), ["Color", "Grain", "Dynamic"])
        XCTAssertEqual(knobs[1].value, "Weak")
        XCTAssertEqual(knobs[1].position, 0.5)
        XCTAssertEqual(knobs[2].value, "DR400")
        XCTAssertEqual(knobs[2].position, 1)
        settings.dynamicRange = .auto
        XCTAssertEqual(Instrument.knobs(for: settings)[2], .init(label: "Dynamic", value: "Auto", position: 0))
    }

    func testASettingTheSlotDoesntHoldReadsAsADash() {
        var settings = RecipeSettings()
        settings.filmSimulation = .acros
        for knob in Instrument.knobs(for: settings) {
            XCTAssertEqual(knob.value, "—")
            XCTAssertEqual(knob.position, 0.5)
        }
    }

    func testTheSheetLeavesOutWhatTheBandAndKnobsShow() {
        var settings = full(.classicNeg, color: 1)
        settings.dynamicRange = .dr200
        settings.grain = GrainEffect(strength: .strong, size: .small)
        let labels = Instrument.dataSheetFields(for: settings).map(\.label)
        XCTAssertFalse(labels.contains(RecipeField.filmSimulation.displayName))
        XCTAssertFalse(labels.contains(RecipeField.color.displayName))
        XCTAssertFalse(labels.contains(RecipeField.dynamicRange.displayName))
        XCTAssertTrue(labels.contains(RecipeField.grain.displayName), "the knob shows only the strength")
    }

    // MARK: Action bar

    func testTheBarSaysWhatLoadingDoes() {
        XCTAssertEqual(Instrument.actionStatus(slotLabel: "C3", canWrite: true, isBusy: false),
                       "Target C3   Write  Read back  Verify")
        XCTAssertEqual(Instrument.actionStatus(slotLabel: "C3", canWrite: false, isBusy: false), "Read only")
        XCTAssertEqual(Instrument.actionStatus(slotLabel: "C3", canWrite: true, isBusy: true), "Target C3   Busy")
        XCTAssertFalse(Instrument.actionStatus(slotLabel: "C3", canWrite: true, isBusy: false).contains("·"))
    }
}
