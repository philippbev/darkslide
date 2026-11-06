import Foundation

/// How confidently a product name resolved to a registry entry — the axis that, with what the body
/// answers at connect, decides what the app may do with it.
///
/// `exact` and `alias` are trusted: the registry's word stands for them. A `heuristic` match is a
/// guess — the name *contains* a known id at a word boundary, which is how "X-T5 TETHER" stays
/// usable, and a name that contains an id can still be a different camera — so a guess reads behind
/// a banner that names it, and writes only once its own slot read has proved the bank path
/// (`WriteDecision`). `unlisted` is a body with no entry that named itself over `GetDeviceInfo`;
/// it carries a provisional model and is decided the same way. `unknown` has neither and gets the
/// read-only sweep and a report to send.
///
/// Exact-or-unknown would have been simpler and would have turned every body that works today into
/// an unknown the moment its product name carried a suffix; the guess tier keeps them and makes the
/// guess visible.
enum ModelIdentification: Equatable, Hashable {
    case exact(CameraModel)
    /// The name is a known spelling variant of a registry id (`CameraModelRegistry.aliases`).
    case alias(CameraModel, alias: String)
    /// The name contains a registry id at a word boundary; `matched` is that id.
    case heuristic(CameraModel, matched: String)
    /// No registry entry, and a `GetDeviceInfo` answer carrying product name, serial and firmware.
    /// The provisional model (`CameraModelRegistry.provisionalModel`) is field knowledge for the
    /// codec; its placeholder id is nothing's to persist, so ``registryModel`` is nil.
    case unlisted(provisional: CameraModel)
    /// Neither a registry entry nor a `GetDeviceInfo` answer naming the body.
    case unknown

    var model: CameraModel? {
        switch self {
        case .exact(let m), .alias(let m, _), .heuristic(let m, _), .unlisted(let m): return m
        case .unknown: return nil
        }
    }

    /// The registry entry the name resolved to. Anything that persists or compares a model id — a
    /// report, a backup, a recipe's `authoredForModel` — reads this rather than ``model``, which an
    /// unlisted body answers with a provisional model two different cameras could share.
    var registryModel: CameraModel? {
        switch self {
        case .exact(let m), .alias(let m, _), .heuristic(let m, _): return m
        case .unlisted, .unknown: return nil
        }
    }

    /// A registry match taken at its word: `exact` or `alias`. RAW conversion, the EXIF seed and
    /// My Cameras key on it; writing is `WriteDecision`'s question.
    var isTrusted: Bool {
        switch self {
        case .exact, .alias: return true
        case .heuristic, .unlisted, .unknown: return false
        }
    }

    var isGuess: Bool {
        if case .heuristic = self { return true }
        return false
    }

    var isUnlisted: Bool {
        if case .unlisted = self { return true }
        return false
    }

    /// `exact` / `alias` / `heuristic` / `unknown`: the case alone, without the matched name
    /// ``reportLabel`` adds.
    var confidence: String {
        switch self {
        case .exact: return "exact"
        case .alias: return "alias"
        case .heuristic: return "heuristic"
        case .unlisted: return "unlisted"
        case .unknown: return "unknown"
        }
    }

    /// For the compatibility report: `exact`, `alias(X-T30II)`, `heuristic(X-T5)`, `unlisted`,
    /// `unknown`.
    var reportLabel: String {
        switch self {
        case .exact: return "exact"
        case .alias(_, let alias): return "alias(\(alias))"
        case .heuristic(_, let matched): return "heuristic(\(matched))"
        case .unlisted: return "unlisted"
        case .unknown: return "unknown"
        }
    }

    /// The banner shown wherever a guessed body's recipes are read.
    func guessBanner(productName: String) -> String? {
        guard case .heuristic(let m, _) = self else { return nil }
        return "Treating “\(productName)” as a \(m.displayName) — a guess from the name. Check that what you read looks right. Writing is allowed only once this camera's slots have been read and selected successfully."
    }
}
