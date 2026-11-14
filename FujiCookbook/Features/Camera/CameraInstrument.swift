import Foundation

/// What the Camera tab's instrument says, worked out apart from the view so it can be tested: the
/// device panel's line and LEDs, which slot is chosen, the three knobs and the data sheet of a
/// slot's card, the import key's count, and the action bar's status. Only reads.
enum CameraInstrument {

    // MARK: Device panel

    /// "FW 1.31   USB   C1–C7": firmware, transport, slot range. Reconnecting replaces the
    /// transport, so the panel never calls a dropped session connected.
    static func panelMeta(firmware: String?, isDemo: Bool, isReconnecting: Bool, slotCount: Int) -> String {
        var parts: [String] = []
        if let firmware { parts.append("FW \(firmware)") }
        parts.append(isReconnecting ? "Reconnecting" : (isDemo ? "Demo" : "USB"))
        // No range when the count is unknown: "C1–C0" would be worse than none.
        if slotCount > 0 { parts.append("C1–C\(slotCount)") }
        return parts.joined(separator: "   ")
    }

    /// LINK is lit while the session is up; R/W while the app may write to this body.
    static func panelLEDs(isLive: Bool, canWrite: Bool) -> [(label: String, isOn: Bool)] {
        [("Link", isLive), ("R/W", isLive && canWrite)]
    }

    // MARK: Slots

    /// The slot to show when none is chosen, or the chosen one is gone: the first that holds a
    /// setting, else the first.
    static func selection(_ chosen: Int?, in slots: [CameraSlot]) -> Int? {
        if let chosen, slots.contains(where: { $0.index == chosen }) { return chosen }
        return (slots.first(where: \.isOccupied) ?? slots.first)?.index
    }

    /// Which library recipe each slot holds, by slot index. The same rule as the Library's slot
    /// badges (`CameraSlotSnapshot.slotLabels`): an exact match only, never a guess.
    static func libraryRecipes(for slots: [CameraSlot], in recipes: [Recipe]) -> [Int: Recipe] {
        let snapshot = CameraSlotSnapshot(cameraName: "", slotCount: slots.count, reading: slots)
        let labels = snapshot.slotLabels(for: recipes)
        var byIndex: [Int: Recipe] = [:]
        for recipe in recipes {
            guard let label = labels[recipe.uuid], let slot = slots.first(where: { $0.label == label }) else { continue }
            byIndex[slot.index] = recipe
        }
        return byIndex
    }

    /// Occupied slots whose recipe isn't in the library yet: the import key's "N new".
    static func newSlotCount(_ slots: [CameraSlot], inLibrary: [Int: Recipe]) -> Int {
        slots.filter { $0.isOccupied && $0.settings != nil && inLibrary[$0.index] == nil }.count
    }

    // MARK: A slot's card

    struct Knob: Equatable {
        let label: String
        let value: String
        /// 0 is the left stop, 1 the right (`DSKnobScale`).
        let position: Double
    }

    /// COLOR, GRAIN, DYNAMIC: color linear from −4 to +4, grain and dynamic range as steps spread
    /// evenly over the scale. A setting the slot doesn't hold reads "—" with the pointer upright.
    static func knobs(for settings: RecipeSettings?) -> [Knob] {
        let color: Knob = settings?.color.map {
            Knob(label: "Color", value: DSValueFormat.signed($0),
                 position: DSKnobScale.position(of: Double($0), in: -4...4))
        } ?? Knob(label: "Color", value: "—", position: 0.5)

        let grainSteps = GrainStrength.allCases
        let grain: Knob = settings?.grain.flatMap { effect in
            grainSteps.firstIndex(of: effect.strength).map {
                Knob(label: "Grain", value: effect.strength.displayName,
                     position: DSKnobScale.position(ofStep: $0, count: grainSteps.count))
            }
        } ?? Knob(label: "Grain", value: "—", position: 0.5)

        let rangeSteps = DynamicRange.allCases
        let dynamic: Knob = settings?.dynamicRange.flatMap { range in
            rangeSteps.firstIndex(of: range).map {
                Knob(label: "Dynamic", value: range == .auto ? "Auto" : range.displayName,
                     position: DSKnobScale.position(ofStep: $0, count: rangeSteps.count))
            }
        } ?? Knob(label: "Dynamic", value: "—", position: 0.5)

        return [color, grain, dynamic]
    }

    /// The settings under the knobs: the recipe detail's sheet without the film simulation (the
    /// band shows it) and without color and dynamic range (their knobs show them). Grain stays,
    /// because its knob shows only the strength.
    static func dataSheetFields(for settings: RecipeSettings) -> [DSDataField] {
        let shownByKnob: Set<String> = [RecipeField.color.displayName, RecipeField.dynamicRange.displayName]
        return RecipeDetailArchive.dataSheetFields(for: settings).filter { !shownByKnob.contains($0.label) }
    }

    /// The card head's side fields: whether the slot holds a setting, and the library recipe it
    /// matches by number.
    static func sideFields(isOccupied: Bool, libraryRecipe: Recipe?) -> [DSDataField] {
        [DSDataField(label: "State", value: isOccupied ? "Set" : "Empty", led: isOccupied),
         DSDataField(label: "Archive", value: libraryRecipe.map { RecipeRow.objectNumber($0.archiveNumber) } ?? "—")]
    }

    /// The card's foot: "In library   Kodachrome", or "Not in library" for a setting the
    /// library doesn't hold. Empty for an empty slot.
    static func footer(isOccupied: Bool, libraryRecipe: Recipe?) -> String {
        guard isOccupied else { return "" }
        guard let libraryRecipe else { return "Not in library" }
        return "In library   \(libraryRecipe.name)"
    }

    // MARK: Action bar

    /// "Target C3   Write  Read back  Verify" — what loading a recipe does — or why it can't.
    static func actionStatus(slotLabel: String?, canWrite: Bool, isBusy: Bool) -> String {
        guard canWrite else { return "Read only" }
        guard let slotLabel else { return "No slot chosen" }
        if isBusy { return "Target \(slotLabel)   Busy" }
        return "Target \(slotLabel)   Write  Read back  Verify"
    }
}
