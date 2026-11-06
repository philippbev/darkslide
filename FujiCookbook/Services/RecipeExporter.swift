import Foundation

/// Writes recipe JSON to temporary `.fujirecipe` files for sharing through the iOS share sheet.
/// Files round-trip exactly with the importer.
enum RecipeExporter {
    enum ExportError: LocalizedError {
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .writeFailed(let d): return "Couldn't write the export file: \(d)"
            }
        }
    }

    /// Encodes `snapshot` and writes it to a temporary file named by `fileName(for:on:in:)`, returning
    /// its URL.
    ///
    /// Touches no SwiftData objects, so `RecipeExportRunner` calls it off the main actor; checking
    /// a backup's photos decodes each one. Throws `CancellationError` when cancelled, the encoder's
    /// errors, or `ExportError.writeFailed`.
    static func export(_ snapshot: RecipeExportSnapshot, named name: String, on date: Date = .now,
                       limits: RecipeImportLimits = .standard,
                       progress: RecipeExportValidation.ProgressHandler = { _ in }) throws -> URL {
        let data = try RecipePortability.encode(snapshot, limits: limits, progress: progress)
        try Task.checkCancellation()
        return try write(data, fileName: fileName(for: name, on: date))
    }

    private static func write(_ data: Data, fileName: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        return url
    }

    /// `name`, made safe for a file name, followed by the date in `timeZone` as `yyyy-MM-dd` — so a
    /// folder of backups sorts by date and today's doesn't take yesterday's name. The recipe names
    /// inside the file are unaffected; import reads those, not the file name.
    static func fileName(for name: String, on date: Date, in timeZone: TimeZone = .current) -> String {
        let safe = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safe.isEmpty ? "Recipe" : safe
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        return "\(base) \(day).fujirecipe"
    }
}
