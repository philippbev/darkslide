import Foundation

/// Renders recipe parameter values as human-readable strings for read-only displays
/// (detail view, slot preview, push overwrite preview).
enum RecipeSettingsFormatter {

    /// The one-line subtitle under a recipe or slot name: film simulation, then dynamic range, as far
    /// as the recipe sets them ("Classic Chrome · DR400"). Empty when it sets neither.
    static func summary(for s: RecipeSettings) -> String {
        [s.filmSimulation?.displayName, s.dynamicRange?.displayName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Display value for one field, or nil if the field carries no value.
    static func valueString(for field: RecipeField, in s: RecipeSettings) -> String? {
        switch field {
        case .filmSimulation:
            return s.filmSimulation?.displayName
        case .monochromaticColor:
            guard s.monochromaticColorWC != nil || s.monochromaticColorMG != nil else { return nil }
            var parts: [String] = []
            if let wc = s.monochromaticColorWC { parts.append("WC \(signed(wc))") }
            if let mg = s.monochromaticColorMG { parts.append("MG \(signed(mg))") }
            return parts.joined(separator: ", ")
        case .grain:
            guard let g = s.grain else { return nil }
            if g.strength == .off { return "Off" }
            if let size = g.size { return "\(g.strength.displayName), \(size.displayName)" }
            return g.strength.displayName
        case .colorChromeEffect:
            return s.colorChromeEffect?.displayName
        case .colorChromeFXBlue:
            return s.colorChromeFXBlue?.displayName
        case .whiteBalance:
            guard let wb = s.whiteBalance else { return nil }
            var text = whiteBalanceModeText(wb)
            if wb.shiftRed != 0 || wb.shiftBlue != 0 {
                text += " · R\(signed(wb.shiftRed)) B\(signed(wb.shiftBlue))"
            }
            return text
        case .dynamicRange:
            return s.dynamicRange?.displayName
        case .dRangePriority:
            return s.dRangePriority?.displayName
        case .highlightTone:
            return s.highlightTone.map(tone)
        case .shadowTone:
            return s.shadowTone.map(tone)
        case .color:
            return s.color.map(signed)
        case .sharpness:
            return s.sharpness.map(signed)
        case .highISONR:
            return s.highISONR.map(signed)
        case .clarity:
            return s.clarity.map(signed)
        case .exposureBias:
            return s.exposureBias.map { String(format: "%+.1f EV", $0) }
        case .noiseReduction:
            return s.noiseReduction.map(signed)
        }
    }

    /// Ordered (field, value) rows for a recipe, optionally limited to a model's supported fields.
    ///
    /// Three of the rows can carry a note. With D-Range Priority on, the camera drives Dynamic
    /// Range, Highlight Tone and Shadow Tone itself and refuses the recipe's values for them
    /// (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md#the-d-range-priority-interlock`).
    /// Shown bare, "Dynamic Range: DR400" under that priority reads as a choice the camera will
    /// honour. It isn't, so the row says so — the read-only counterpart of the editor greying those
    /// three out. The value stays, because it is still the recipe's: turn the priority off and it is
    /// exactly what gets written. Done here so no screen that renders rows can show the bare value.
    static func rows(for s: RecipeSettings, model: CameraModel? = nil) -> [(field: RecipeField, value: String)] {
        // The body gate and the priority note, not the whole of `RecipeApplicability`: these rows
        // show Color on a monochrome recipe, and hiding it here would change every screen that
        // renders them.
        return RecipeField.allCases.compactMap { field in
            guard RecipeApplicability.bodyProvides(field, on: model).applies else { return nil }
            guard let value = valueString(for: field, in: s) else { return nil }
            guard RecipeApplicability.underPriority(field, in: s, on: model).applies else {
                return (field, "\(value) · \(priorityNote)")
            }
            return (field, value)
        }
    }

    /// Display value for one **diff row**, or nil if the row carries no value.
    ///
    /// Not an overload of `valueString(for:in:)`: `DiffRowID` and `RecipeField` share case names, so
    /// an overload makes every leading-dot call site ambiguous, `valueString(for: .filmSimulation,
    /// in: s)` included.
    ///
    /// The split rows need their axes separately — a warm–cool value without its magenta–green
    /// partner, a grain size without its strength — and `valueString(for:in:)` above renders whole
    /// fields. Both live here rather than in the diff so one place turns a recipe value into a
    /// string.
    ///
    /// TODO: `RecipeMatcher` keeps private copies of four of these (`grainText`, `monochromaticText`
    /// and the two closures in `whiteBalanceRows`); replace them with calls into this type.
    static func valueString(forRow row: DiffRowID, in s: RecipeSettings) -> String? {
        switch row {
        case .monochromaticColorWC: return s.monochromaticColorWC.map(signed)
        case .monochromaticColorMG: return s.monochromaticColorMG.map(signed)
        case .grainStrength: return s.grain?.strength.displayName
        case .grainSize: return s.grain?.size?.displayName
        case .whiteBalanceMode:
            guard let wb = s.whiteBalance else { return nil }
            // The mode *is* the temperature when it uses one, which is why there is no Kelvin row
            // of its own: a separate one would read N/A on every recipe not in Color Temperature
            // mode, which is nearly all of them.
            return whiteBalanceModeText(wb)
        case .whiteBalanceShift:
            guard let wb = s.whiteBalance else { return nil }
            return "R\(signed(wb.shiftRed)) B\(signed(wb.shiftBlue))"
        default:
            // Every other row is exactly its field.
            return valueString(for: row.field, in: s)
        }
    }

    static let priorityNote = "overridden by D-Range Priority"

    /// The mode's name, or the temperature in its place when the mode uses one. One rendering for
    /// the whole-field and per-row paths, so the detail table and the compare screen cannot show
    /// the same white balance two ways.
    private static func whiteBalanceModeText(_ wb: WhiteBalance) -> String {
        wb.mode.usesKelvin ? (wb.kelvin.map { "\($0)K" } ?? wb.mode.displayName) : wb.mode.displayName
    }

    /// An integer with its sign, the minus typographic (U+2212): the same width as "+", so signed
    /// values align.
    static func signed(_ value: Int) -> String {
        // Not `String(format: "%+d")`: `%d` takes a 32-bit C integer, and Swift's Int is 64-bit.
        (value >= 0 ? "+\(value)" : String(value)).replacingOccurrences(of: "-", with: "−")
    }

    /// A tone value with its sign: whole steps without a decimal, half steps with one.
    static func tone(_ value: Double) -> String {
        // Stored recipes and camera reads reach here without passing import validation.
        guard value.isFinite else { return "Invalid value" }
        // -0.0 equals 0, and `%+.0f` would render it "−0".
        if value == 0 { return "+0" }
        let text = value == value.rounded() ? String(format: "%+.0f", value) : String(format: "%+.1f", value)
        return text.replacingOccurrences(of: "-", with: "−")
    }
}

// MARK: - Chip summaries

extension RecipeSettingsFormatter {
    /// Compact chip strings for recipe cards — the dense "whole recipe at a glance" row ("DR400",
    /// "HL −1", "WB R−1 B−2", "Grain Wk").
    static func chips(for s: RecipeSettings) -> [String] {
        var chips: [String] = []
        // Under a priority the range and tones are the camera's, not the recipe's, so the headline
        // is the priority — `rows(for:)` notes the same three fields in the table below the chips.
        // No body here, so an on priority is taken at its word.
        if RecipeApplicability.priorityOverrides(s, on: nil), let drp = s.dRangePriority {
            chips.append("DRP \(drp.displayName)")
        } else {
            if let dr = s.dynamicRange { chips.append(dr.displayName) }
            if let hl = s.highlightTone { chips.append("HL \(tone(hl))") }
            if let sh = s.shadowTone { chips.append("SH \(tone(sh))") }
        }
        if let color = s.color { chips.append("Color \(signed(color))") }
        if let wb = s.whiteBalance {
            if wb.mode.usesKelvin, let k = wb.kelvin {
                chips.append("\(k)K")
            } else if wb.shiftRed != 0 || wb.shiftBlue != 0 {
                chips.append("WB R\(signed(wb.shiftRed)) B\(signed(wb.shiftBlue))")
            }
        }
        if let grain = s.grain, grain.strength != .off {
            chips.append("Grain \(grain.strength == .weak ? "Wk" : "Str")")
        }
        if let clarity = s.clarity, clarity != 0 { chips.append("Clarity \(signed(clarity))") }
        if let sharp = s.sharpness, sharp != 0 { chips.append("Sharp \(signed(sharp))") }
        if let ev = s.exposureBias, ev != 0 { chips.append(String(format: "%+.2g EV", ev)) }
        return chips
    }
}
