import Foundation

/// What the photo import's head says, worked out apart from the view so it can be tested: the
/// SOURCE | MODE | SELECTION fields, the top key that selects all or none, and a day's frame range.
enum PhotoImportHeader {

    /// SOURCE: the card's camera, without the maker every Fujifilm body puts first, with an LED lit
    /// once the whole card is read and "Newest 500" while older photos wait. MODE: which files an
    /// import copies. SELECTION: chosen of shown, "12/40".
    static func fields(sourceName: String, isListing: Bool, loadedCount: Int, hasOlder: Bool,
                       fileChoice: ImportFileChoice, selected: Int, shown: Int) -> [DSDataField] {
        [DSDataField(label: "Source", value: shortName(sourceName), led: !isListing,
                     note: hasOlder ? "Newest \(loadedCount)" : nil),
         DSDataField(label: "Mode", value: modeValue(fileChoice)),
         DSDataField(label: "Selection", value: "\(selected)/\(shown)")]
    }

    /// "X100VI" from "FUJIFILM X100VI".
    static func shortName(_ name: String) -> String {
        let prefix = "FUJIFILM "
        guard name.uppercased().hasPrefix(prefix), name.count > prefix.count else { return name }
        return String(name.dropFirst(prefix.count))
    }

    /// The file choice as it fits a third of the row: "RAW+JPG", "RAW", "JPG".
    static func modeValue(_ choice: ImportFileChoice) -> String {
        switch choice {
        case .all: return "RAW+JPG"
        case .raw: return "RAW"
        case .rendered: return "JPG"
        }
    }

    /// The key at the top: "All" while something shown is left out, "None" once all of it is chosen.
    static func selectsAll(selected: Int, shown: Int) -> Bool {
        selected < shown
    }

    /// "0142–0150": the day's first and last frame number; one number for one frame. Numbers that
    /// aren't numbers sort as text.
    static func frameRange(_ frameNumbers: [String]) -> String? {
        let sorted = frameNumbers.sorted { lhs, rhs in
            if let l = Int(lhs), let r = Int(rhs) { return l < r }
            return lhs < rhs
        }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        return first == last ? first : "\(first)–\(last)"
    }
}
