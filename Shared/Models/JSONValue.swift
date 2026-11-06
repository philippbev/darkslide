import Foundation

/// A `Codable` representation of an arbitrary JSON value.
///
/// Used for `unsupportedFields` so that a recipe authored on a newer/different camera can be
/// imported, **preserved, and re-exported** even when this app version doesn't understand a field,
/// so a recipe is never silently degraded by passing through it. The value survives, not the
/// bytes: numbers are held as `Double`, so integers beyond 2⁵³ lose precision, and number
/// formatting, key order and whitespace are not kept.
enum JSONValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string): try container.encode(string)
        case .number(let number): try container.encode(number)
        case .bool(let bool): try container.encode(bool)
        case .object(let object): try container.encode(object)
        case .array(let array): try container.encode(array)
        case .null: try container.encodeNil()
        }
    }

    /// A short human-readable rendering for the "preserved unsupported fields" UI flag.
    var displayString: String {
        switch self {
        case .string(let string): return string
        case .number(let number):
            // `Int(exactly:)`, not `Int(_:)`: an unknown field can exceed Int's range, and
            // `Int(_:)` traps on it.
            if let integer = Int(exactly: number) { return String(integer) }
            return String(number)
        case .bool(let bool): return bool ? "true" : "false"
        case .null: return "null"
        case .array(let array): return "[\(array.count) items]"
        case .object(let object): return "{\(object.count) fields}"
        }
    }
}
