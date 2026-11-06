/// Where a slot the Camera Test changed stands: offered a restore, put back, kept by choice, or
/// still waiting.
///
/// Persisted by its spelling in Camera Test sessions, recovery records and reports. The spellings
/// changed between builds, so one this build doesn't know decodes as `.unrecognized` instead of
/// failing the whole file.
enum RestoreDisposition: Hashable {
    /// Touched by the test, with nothing decided yet.
    case pending
    case offered
    /// Put back, and the fresh reading matched the original.
    case restored
    case kept
    /// The original slot was empty, which a restore can't recreate, and the user kept the test recipe.
    case emptyKept
    case canceled
    /// A verified restore as builds 2–9 recorded it, by the push outcome's name. Build 10 on writes
    /// it only until `onFinish` replaces it with `restored`.
    case applied
    case partiallyApplied
    case couldNotVerify
    case notWritten
    /// Builds 2–9: the restore wrote, but its read-back didn't run.
    case unknown
    case unrecognized(String)

    private static let known: [RestoreDisposition] = [
        .pending, .offered, .restored, .kept, .emptyKept, .canceled,
        .applied, .partiallyApplied, .couldNotVerify, .notWritten, .unknown,
    ]

    init(rawValue: String) {
        self = Self.known.first { $0.rawValue == rawValue } ?? .unrecognized(rawValue)
    }

    init(_ outcome: RestoreVerification.Outcome) {
        self.init(rawValue: outcome.rawValue)
    }

    var rawValue: String {
        switch self {
        case .pending: return "pending"
        case .offered: return "offered"
        case .restored: return "restored"
        case .kept: return "kept"
        case .emptyKept: return "emptyKept"
        case .canceled: return "canceled"
        case .applied: return "applied"
        case .partiallyApplied: return "partiallyApplied"
        case .couldNotVerify: return "couldNotVerify"
        case .notWritten: return "notWritten"
        case .unknown: return "unknown"
        case .unrecognized(let spelling): return spelling
        }
    }

    /// The slot needs nothing more: put back, or kept on purpose.
    var isSettled: Bool { [.restored, .kept, .emptyKept].contains(self) }

    /// Kept by the user's choice rather than restored.
    var isKeptByChoice: Bool { self == .kept || self == .emptyKept }
}

extension RestoreDisposition: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
