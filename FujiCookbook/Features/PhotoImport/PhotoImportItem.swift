import Foundation

/// One file on the camera's card, as a photo source lists it. Nothing here is read from the file
/// itself; it is what the card's catalog says.
struct ImportFile: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case raw, jpeg, heif, movie

        /// What a contact sheet's format badge calls it.
        var label: String {
            switch self {
            case .raw: return "RAF"
            case .jpeg: return "JPG"
            case .heif: return "HIF"
            case .movie: return "MOV"
            }
        }

        /// The file extensions a Fujifilm body writes, upper-cased. Anything else on the card is
        /// not offered for import.
        static func of(fileName: String) -> Kind? {
            switch (fileName as NSString).pathExtension.uppercased() {
            case "RAF": return .raw
            case "JPG", "JPEG": return .jpeg
            case "HIF", "HEIF", "HEIC": return .heif
            case "MOV", "MP4": return .movie
            default: return nil
            }
        }
    }

    /// The source's own handle for the file, stable while the source is open.
    let id: String
    /// "DSCF1284.JPG".
    let name: String
    /// The folder on the card, "DCIM/100_FUJI". Frame numbers repeat across folders once the
    /// counter wraps, so a frame is a name within a folder.
    let folder: String
    let byteSize: Int64
    let captureDate: Date?
    let kind: Kind

    /// Nil for a file that isn't a photo or movie the app imports.
    init?(id: String, name: String, folder: String, byteSize: Int64, captureDate: Date?) {
        guard let kind = Kind.of(fileName: name) else { return nil }
        self.id = id
        self.name = name
        self.folder = folder
        self.byteSize = byteSize
        self.captureDate = captureDate
        self.kind = kind
    }

    /// "DSCF1284" — the part a RAF and its JPEG share.
    var stem: String { (name as NSString).deletingPathExtension }

    /// What identifies this file across connections, for "only new": the card's handles don't
    /// survive a reconnect, and a name alone repeats once the frame counter wraps.
    var ledgerKey: String {
        "\(name.uppercased())|\(byteSize)|\(Int(captureDate?.timeIntervalSince1970 ?? 0))"
    }
}

/// One exposure: the files the camera wrote for it. Shooting RAW+JPEG gives two files and one
/// frame, which is one tile on the contact sheet and one asset in the photo library.
struct ImportFrame: Identifiable, Hashable, Sendable {
    /// Ordered for display: the file to show first, then the rest.
    let files: [ImportFile]

    var id: String { "\(files[0].folder)/\(files[0].stem.uppercased())" }

    /// The file whose picture stands for the frame: a JPEG or HEIF before a RAF, because a card
    /// catalog has a thumbnail for those on every body.
    var preview: ImportFile { files[0] }

    var captureDate: Date? { files.compactMap(\.captureDate).min() }

    /// "1284" from "DSCF1284": the trailing digits, or the whole name when there are none.
    var frameNumber: String {
        let stem = files[0].stem
        let digits = String(stem.reversed().prefix { $0.isNumber }.reversed())
        return digits.isEmpty ? stem : digits
    }

    /// "RAF+JPG": the RAF first, as the camera's own quality menu names the pair.
    var formatLabel: String {
        let order: [ImportFile.Kind] = [.raw, .jpeg, .heif, .movie]
        return order.filter { kind in files.contains { $0.kind == kind } }.map(\.label).joined(separator: "+")
    }

    var byteSize: Int64 { files.reduce(0) { $0 + $1.byteSize } }

    /// Group a card's files into frames, in the order they were taken. Files with no date keep the
    /// order of their names.
    static func frames(from files: [ImportFile]) -> [ImportFrame] {
        let displayOrder: [ImportFile.Kind] = [.jpeg, .heif, .movie, .raw]
        let grouped = Dictionary(grouping: files) { "\($0.folder)/\($0.stem.uppercased())" }
        return grouped.values.map { group in
            ImportFrame(files: group.sorted {
                let left = displayOrder.firstIndex(of: $0.kind) ?? 0, right = displayOrder.firstIndex(of: $1.kind) ?? 0
                return left == right ? $0.name < $1.name : left < right
            })
        }
        .sorted { left, right in
            switch (left.captureDate, right.captureDate) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.id < right.id
            }
        }
    }
}

/// The frames of one calendar day: one section of the contact sheet.
struct ImportDay: Identifiable, Equatable {
    /// Midnight of the day, or nil for frames the card gave no date for.
    let day: Date?
    let frames: [ImportFrame]

    var id: Date { day ?? .distantPast }

    /// Newest day first, the way a card is read after a trip; within a day, in the order taken.
    /// Undated frames come last.
    static func days(from frames: [ImportFrame], calendar: Calendar = .current) -> [ImportDay] {
        let grouped = Dictionary(grouping: frames) { $0.captureDate.map(calendar.startOfDay(for:)) }
        return grouped.map { ImportDay(day: $0.key, frames: $0.value) }
            .sorted { left, right in
                switch (left.day, right.day) {
                case let (a?, b?): return a > b
                case (_?, nil): return true
                default: return false
                }
            }
    }
}

/// Which files have been imported before, so a card that still holds last week's photos offers
/// only what is new. A file on disk rather than a preference: it grows with every import.
struct PhotoImportLedger {
    private(set) var keys: Set<String>
    private let url: URL

    static var defaultURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("PhotoImportLedger.json")
    }

    /// A ledger that can't be read starts empty: the cost is offering photos again, never losing one.
    init(url: URL = PhotoImportLedger.defaultURL) {
        self.url = url
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        keys = Set(stored ?? [])
    }

    /// Whether every file of the frame has been imported.
    func contains(_ frame: ImportFrame) -> Bool {
        frame.files.allSatisfy { keys.contains($0.ledgerKey) }
    }

    mutating func record(_ files: [ImportFile]) throws {
        keys.formUnion(files.map(\.ledgerKey))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(keys.sorted()).write(to: url, options: .atomic)
    }
}
