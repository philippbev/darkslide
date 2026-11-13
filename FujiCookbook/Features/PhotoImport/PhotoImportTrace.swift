import Foundation

/// A timed record of one photo import's listing, for finding where a slow one spends its time.
/// One small file in Caches, started afresh by each visit; it holds file counts and timings, no
/// file names. `xcrun devicectl device copy from --domain-type appDataContainer` reaches it.
enum PhotoImportTrace {
    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photo-import-trace.log")
    }

    private static var started = Date()

    /// Begin a new record below the earlier ones, so a quick second visit doesn't hide the slow first
    /// one. Past 64 KB the oldest half goes.
    static func start(_ what: String) {
        started = Date()
        if let data = try? Data(contentsOf: url), data.count > 64_000 {
            try? data.suffix(32_000).write(to: url)
        }
        let stamp = Date().formatted(.dateTime.day().month().hour().minute().second())
        appendLine("\n=== \(stamp)\n")
        note(what)
    }

    /// One line, with the seconds since `start`.
    static func note(_ line: String) {
        appendLine(String(format: "%7.2fs  %@\n", Date().timeIntervalSince(started), line))
    }

    private static func appendLine(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
