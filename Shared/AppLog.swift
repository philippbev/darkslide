import Foundation
import os

/// App-wide logging (compiled into both targets).
///
/// Each event becomes an `os.Logger` line plus an entry in an in-memory ring the app can show and
/// copy without a Mac attached. `CameraLog` is a façade over it for the camera layer.
///
/// Three outputs, in increasing order of how much they cost:
/// - `os.Logger`, one per `Category` — visible in Console.app/Xcode, free when nobody is reading.
/// - `buffer` — an in-memory ring, which the Connection Log and the diagnostics report's session
///   activity read.
/// - `current.log` in the App Group container, rolled to `previous.log` at launch.
///
/// **The file is the point.** `OSLogStore` on iOS can only be opened with
/// `.currentProcessIdentifier` scope, so the unified log from the launch that just crashed is
/// unreachable — the one log anybody actually wants. Keeping our own copy on disk is the only way a
/// bug report can carry what happened *before* the crash rather than after it.
public enum AppLog {
    /// Log subsystem, following the bundle identifier.
    public static let subsystem = AppIdentifiers.base

    /// The areas of the app that log. One `os.Logger` per case, so Console.app can filter by
    /// category.
    public enum Category: String, Sendable, CaseIterable {
        /// Launch, store creation, lifecycle.
        case app
        /// The USB/PTP connection layer. Everything `CameraLog` writes.
        case camera
        /// RAW conversion, Test Kitchen, Frame & Fit.
        case kitchen
        /// Recipe scanning and the provider clients.
        case ai
        /// SwiftData, decoding, the recipe store.
        case data
        /// `.fujirecipe` import/export and the file pickers.
        case importExport = "import"
        /// The Share Extension and the shared-screenshot inbox.
        case share

        /// The logger built for this category in `loggers`, so a log call doesn't build one.
        fileprivate var logger: Logger { AppLog.loggers[self] ?? Logger(subsystem: AppLog.subsystem, category: rawValue) }
    }

    /// Immutable after initialisation, so no lock — `Category` is `CaseIterable` and this covers
    /// every case, which is what lets the lookup above fall back only in theory.
    private static let loggers: [Category: Logger] = Dictionary(
        uniqueKeysWithValues: Category.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) })

    /// One recorded event, newest last.
    public struct Entry: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let category: Category
        public let isError: Bool
        public let message: String

        /// One line of the report: `HH:mm:ss.SSS  [category]  ! message`, the `! ` only on an error.
        public var reportLine: String {
            AppLog.formatLine(timestamp: timestamp, category: category, isError: isError, message: message)
        }
    }

    // MARK: Entry points

    /// Record a normal event.
    ///
    /// Messages must stay **non-identifying enough to paste into a bug report**: outcomes, counts,
    /// property codes, camera models. Never recipe field values, file paths or names, EXIF payloads
    /// or serial numbers — a user hands this whole log to us in the diagnostics report, and the
    /// point of that screen is that they can read it before they send it.
    public static func info(_ category: Category, _ message: String) {
        record(category: category, isError: false, message: message)
    }

    /// Record a failure. Same content rule as `info`.
    ///
    /// This is for a failure *worth reading later*, not for every thrown error — a `catch` that
    /// recovers cleanly and tells the user is usually still worth one line, a retry loop's third
    /// attempt usually isn't.
    public static func error(_ category: Category, _ message: String) {
        record(category: category, isError: true, message: message)
    }

    /// Record a failure and the error behind it — **only for errors whose description we own**.
    ///
    /// Uses `String(describing:)` rather than `localizedDescription`: the localized string is
    /// written for the user and routinely discards the underlying domain and code, which are the two
    /// things worth having afterwards.
    ///
    /// The rule this overload lives under: pass a *typed* error whose description is a case name we
    /// wrote — `CameraError`, `RecipeScanError`, a `DecodingError` about a provider's response
    /// shape. Never pass whatever Foundation throws at a file. A `CocoaError` or `NSURLError`
    /// embeds the path, URL, or account it failed on, and this log is not a private channel: the
    /// user hands the whole file to us in a diagnostics report, and a picked file's *name* is
    /// routinely the user's own content. For those, interpolate ``bounded(_:)`` instead.
    public static func error(_ category: Category, _ message: String, _ error: Error) {
        record(category: category, isError: true,
               message: "\(message): \(String(describing: error))")
    }

    /// The bounded form of an error — its domain and code, never its description. Foundation
    /// error descriptions routinely name the very file paths, URLs, and accounts a user-shared
    /// report should never carry.
    public static func bounded(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }

    // MARK: Reading

    /// Everything logged this launch, oldest first.
    public static var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    /// Entries for one area, oldest first — the Connection Log's view of `.camera`.
    public static func entries(in category: Category) -> [Entry] {
        entries.filter { $0.category == category }
    }

    /// Plain-text form of this launch's entries, oldest first.
    public static func reportText(in category: Category? = nil) -> String {
        let wanted = category.map { entries(in: $0) } ?? entries
        return wanted.map(\.reportLine).joined(separator: "\n")
    }

    /// This launch's entries as written to `current.log` — flushed first, so the file is complete —
    /// rather than the in-memory ring. The ring is shared by every category and drops its oldest
    /// entries once it fills, so a busy category can push others out of it; the file keeps
    /// everything up to its size cap. Falls back to the ring when the file can't be read (no App
    /// Group container, as in some test hosts).
    public static func currentLaunchText() -> String {
        flushNow()
        guard let url = currentLogURL, let data = try? Data(contentsOf: url) else { return reportText() }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    /// What the *previous* launch left behind, read back off disk. Empty on a first run, or when the
    /// previous run wrote nothing to disk.
    ///
    /// This is the half of the diagnostics report that survives a crash, so it is read from the file
    /// rather than from memory — by definition the buffer that produced it is gone.
    public static func previousLaunchText() -> String {
        guard let url = previousLogURL, let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Copy whatever `previous.log` holds into the file that never rolls.
    ///
    /// Called once at launch, by `SessionTermination`, and only when the previous run died in the
    /// foreground. It takes the roll's result because what it copies is what the roll moved into
    /// `previous.log`.
    ///
    /// Best-effort by design: failing to preserve a log must never be the reason a launch fails.
    ///
    /// A dead run that left no log replaces the preserved file with a line saying so, rather than
    /// leaving an *earlier* death's log in place to be read as this one's, for the same reason
    /// `rollLogFiles()` removes a stale `previous.log`.
    public static func preserveLogFromUnexpectedExit(after _: RolledLogs) {
        guard let previous = previousLogURL, let destination = unexpectedExitLogURL else { return }
        let fileManager = FileManager.default
        let hasLog = fileManager.fileExists(atPath: previous.path)
        ioQueue.sync {
            try? fileManager.removeItem(at: destination)
            if hasLog {
                try? fileManager.copyItem(at: previous, to: destination)
            } else {
                try? fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
                try? Data((Self.noLogFromDeadRun + "\n").utf8).write(to: destination, options: .atomic)
            }
        }
    }

    /// What the preserved log says when the run that died wrote nothing to disk first.
    static let noLogFromDeadRun =
        "(The session that ended unexpectedly wrote nothing to disk before it ended, so there is no log to preserve.)"

    /// The log of the most recent run that ended unexpectedly, or empty when no run has since Clear
    /// Diagnostics last erased it.
    public static func unexpectedExitText() -> String {
        guard let url = unexpectedExitLogURL, let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Drop this launch's entries. Does not touch either file — the Connection Log's Clear button is
    /// about what's on screen, not about destroying the record a bug report would carry.
    public static func clear(_ category: Category? = nil) {
        lock.lock()
        if let category {
            buffer.removeAll { $0.category == category }
        } else {
            buffer.removeAll()
        }
        lock.unlock()
    }

    /// Erase both log files and everything buffered behind them.
    ///
    /// Distinct from ``clear(_:)``, which only empties the on-screen buffer. This is the one the
    /// user's Clear Diagnostics control calls, so it has to leave nothing for the next flush to
    /// write back: `unflushed` is dropped as well, under the same lock, or entries recorded before
    /// the tap would reappear in `current.log` seconds later and the file would look un-erased.
    public static func eraseFiles() {
        lock.lock()
        buffer.removeAll()
        unflushed.removeAll()
        lock.unlock()

        // The preserved log included: Clear Diagnostics promises to erase what a report draws on,
        // and this file is drawn on by exactly that report.
        let urls = [currentLogURL, previousLogURL, unexpectedExitLogURL].compactMap { $0 }
        ioQueue.sync {
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    // MARK: Lifecycle

    /// Evidence that `rollLogFiles()` has run, so `previous.log` holds the run that just ended. Only
    /// `rollLogFiles()` makes one.
    public struct RolledLogs: Sendable {
        fileprivate init() {}
    }

    /// Roll `current.log` to `previous.log`. Call once at launch, before anything logs.
    ///
    /// Whatever is in `current.log` at this moment belongs to the run that just ended, including
    /// whatever a run that crashed flushed before it died.
    ///
    /// **No `current.log` means the run that just ended wrote nothing, and `previous.log` then
    /// belongs to the run before *that*** — so it is removed, not kept. Keeping it would present an
    /// older run as the one that just ended: a run that aborts seconds after launch, before anything
    /// reaches disk, would leave the next launch offering a log days old as "the session that ended
    /// unexpectedly". Nothing is better than the wrong thing.
    @discardableResult
    public static func rollLogFiles() -> RolledLogs {
        guard let current = currentLogURL, let previous = previousLogURL else { return RolledLogs() }
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: previous)
        guard fileManager.fileExists(atPath: current.path) else { return RolledLogs() }
        try? fileManager.moveItem(at: current, to: previous)
        return RolledLogs()
    }

    /// Write anything still buffered to disk. Called on background/terminate, and periodically as the
    /// buffer fills — see `record`.
    ///
    /// Safe to call from anywhere and never throws: a diagnostics facility that can take the app down
    /// is worse than no diagnostics facility.
    public static func flush() {
        lock.lock()
        let pending = unflushed
        unflushed = []
        lock.unlock()

        guard !pending.isEmpty, let url = currentLogURL else { return }
        let text = pending.map(\.reportLine).joined(separator: "\n") + "\n"
        ioQueue.async { append(text, to: url) }
    }

    /// `flush()`, and wait until the write has landed. For the few moments where a crash could
    /// follow within milliseconds and the lines before it are the whole evidence.
    ///
    /// `flush()` only enqueues, and the buffer self-flushes every 20 entries, so a crash loses up to
    /// 19 lines plus whatever is still queued — and on a reconnect those are exactly the lines that
    /// say where it died. Blocks the caller on a read-modify-write of a file capped at 256 KB, so it
    /// belongs at rare checkpoints — connect, plug and unplug — never per line.
    public static func flushNow() {
        flush()
        ioQueue.sync {}
    }

    // MARK: Internals

    /// Newest-last ring of this launch's entries.
    private static var buffer: [Entry] = []
    /// Entries recorded but not yet written to `current.log`.
    private static var unflushed: [Entry] = []

    /// One lock over both arrays. `AppLog` is called from `@MainActor` views and from detached
    /// scanning tasks, so it can't be actor-isolated without forcing `await` onto every `catch`
    /// block in the app.
    private static let lock = NSLock()

    /// File writes happen here, never on the caller's thread. Utility QoS: a log line is never worth
    /// competing with a RAW conversion for the CPU.
    private static let ioQueue = DispatchQueue(label: "\(subsystem).applog", qos: .utility)

    /// How many entries this launch keeps in memory. The ring is shared by every category, and a
    /// Test Kitchen matrix can produce a lot of lines.
    private static let capacity = 600

    /// Flush once this many entries have accumulated, so a crash loses fewer than this many, plus
    /// any write still queued; see `flushNow()`.
    private static let flushThreshold = 20

    /// Cap on each file. Three of these is the worst case on disk, and the report only shows the tail.
    private static let maxFileBytes = 256 * 1024

    private static func record(category: Category, isError: Bool, message: String) {
        // The unified-log line first: it's the one output that still happens if everything below
        // this point is somehow broken.
        //
        // Marked `.private`, which is the one privacy decision in this file that isn't about our
        // own log at all. Unified-log lines outlive the app: they are captured by a sysdiagnose and
        // can travel to Apple under the user's diagnostics setting, and nothing on this side sees
        // what is in them or gets to show the user first. `.private` still resolves in full for a
        // developer with the device attached, which is the only audience this copy is for.
        let logger = category.logger
        if isError {
            logger.error("\(message, privacy: .private)")
        } else {
            logger.info("\(message, privacy: .private)")
        }

        let entry = Entry(timestamp: Date(), category: category, isError: isError, message: message)

        lock.lock()
        buffer.append(entry)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
        unflushed.append(entry)
        let shouldFlush = unflushed.count >= flushThreshold
        lock.unlock()

        if shouldFlush { flush() }
    }

    /// Append, trimming from the front when the file outgrows its cap.
    ///
    /// Read-modify-write rather than a `FileHandle` seek-to-end, because trimming needs the whole
    /// file anyway and these files are bounded at a quarter of a megabyte. Runs only on `ioQueue`.
    private static func append(_ text: String, to url: URL) {
        let existing = (try? Data(contentsOf: url)) ?? Data()
        var combined = existing + Data(text.utf8)

        if combined.count > maxFileBytes {
            let overflow = combined.count - maxFileBytes
            // Drop the overflow, then the partial line it left behind, so the file always starts on
            // a line boundary and never mid-UTF-8-sequence.
            combined = combined.dropFirst(overflow)
            if let newline = combined.firstIndex(of: UInt8(ascii: "\n")) {
                combined = Data(combined[combined.index(after: newline)...])
            }
        }

        guard let directory = containerURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? combined.write(to: url, options: .atomic)
    }

    /// Shared with the Share Extension, so both processes' lines land in one report. They interleave
    /// by append order rather than by timestamp, which is fine: the extension runs when the app is
    /// backgrounded, so in practice they don't overlap.
    private static var containerURL: URL? {
        SharedContainer.url?
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private static var currentLogURL: URL? { containerURL?.appendingPathComponent("current.log") }
    private static var previousLogURL: URL? { containerURL?.appendingPathComponent("previous.log") }
    /// The log from a launch that ended in the foreground without saying goodbye.
    ///
    /// A third file, because `rollLogFiles()` overwrites `previous.log` on *every* launch (see
    /// `SessionTermination`). Nothing rolls this one: it is written when the loss is detected, and
    /// lives until the next unexpected exit replaces it or Clear Diagnostics removes it.
    private static var unexpectedExitLogURL: URL? {
        containerURL?.appendingPathComponent("unexpected-exit.log")
    }

    /// `Entry.reportLine`'s format.
    fileprivate static func formatLine(timestamp: Date, category: Category, isError: Bool, message: String) -> String {
        "\(timeFormatter.string(from: timestamp))  [\(category.rawValue)]  \(isError ? "! " : "")\(message)"
    }

    fileprivate static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
