import Foundation

/// What the recipe's archive card says, worked out apart from the view so it can be tested: the
/// side fields of its head, the data sheet, and the line on its foot.
///
/// Values here follow the design system: parts are separated by space alone, never by a "·", and
/// signed values use a real minus sign (the formatter's already do).
enum RecipeDetailArchive {
    /// The settings in the data sheet: every row the recipe sets, except the film simulation, which
    /// has the band above the sheet.
    static func dataSheetFields(for settings: RecipeSettings) -> [DSDataField] {
        RecipeSettingsFormatter.rows(for: settings)
            .filter { $0.field != .filmSimulation }
            .map { DSDataField(label: $0.field.displayName, value: spaced($0.value)) }
    }

    /// The slot name, last in the data sheet: the camera's own label for this recipe. A name that
    /// only follows the recipe's name says so.
    static func slotNameField(name: String, isCustom: Bool) -> DSDataField {
        DSDataField(label: "Slot Name", value: name, note: isCustom ? nil : "From name")
    }

    /// The head's side fields: the camera slot the recipe was last read in, its chapter, the day it
    /// was made.
    static func sideFields(slot: String?, chapterNames: [String], createdAt: Date,
                           calendar: Calendar = .current) -> [DSDataField] {
        [DSDataField(label: "Slot", value: slot ?? "—"),
         DSDataField(label: "Roll", value: chapterValue(chapterNames)),
         DSDataField(label: "Created", value: created(createdAt, calendar: calendar))]
    }

    /// "Street"; "Street +2" when the recipe is in three chapters; "—" in none. The tags under
    /// the card name them all.
    static func chapterValue(_ names: [String]) -> String {
        guard let first = names.first else { return "—" }
        return names.count == 1 ? first : "\(first) +\(names.count - 1)"
    }

    /// "2026-11-14": the archive's date, the same in every language.
    static func created(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "X100VI   Works as written": the camera the verdict is for, and the verdict. Empty with no
    /// camera to judge against.
    static func footer(cameraID: String?, verdict: RecipeCameraFit.Verdict?) -> String {
        guard let cameraID, let verdict else { return "" }
        return "\(cameraID)   \(verdict.title)"
    }

    /// The formatter's value as the archive writes it: parts apart by space alone, never by "·" or
    /// ",", and zero without a sign ("0", not "+0"). The shared formatter keeps its own form for
    /// export and share cards.
    static func spaced(_ value: String) -> String {
        let parts = value.replacingOccurrences(of: " · ", with: "   ")
            .replacingOccurrences(of: ", ", with: "  ")
        // The number leads, a unit may follow: "+0.0 EV" reads "0 EV".
        let number = parts.prefix { $0 != " " }
        return isSignedZero(String(number)) ? "0" + parts.dropFirst(number.count) : parts
    }

    /// "+0", "−0", "+0.0": a zero the formatter signed.
    private static func isSignedZero(_ value: String) -> Bool {
        guard let sign = value.first, "+-\u{2212}".contains(sign) else { return false }
        return Double(value.dropFirst()) == 0
    }
}
