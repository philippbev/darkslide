import Foundation

/// Fallback hand-off from the Share Extension to the main app (compiled into both targets).
///
/// The extension scans a shared screenshot and saves the recipe itself. When it can't finish, it
/// drops the image bytes into an App Group folder instead; the app drains the folder on
/// launch/foreground and runs each image through the AI recipe scan. A file-based inbox (rather
/// than launching the app directly) because iOS gives share extensions no supported way to open
/// their containing app — the hand-off must survive until the user opens it themselves.
enum ScreenshotInbox {
    /// `APP_GROUP_IDENTIFIER`, the same setting both targets' entitlements use.
    static let appGroupID = AppIdentifiers.appGroup

    private static var inboxURL: URL? {
        SharedContainer.url?
            .appendingPathComponent("ScreenshotInbox", isDirectory: true)
    }

    /// Persist one shared image (any UIImage-decodable bytes — the scan pipeline re-encodes).
    static func save(_ data: Data) throws {
        guard let dir = inboxURL else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The shared App Group container isn't available."])
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The epoch orders the files oldest-first and is what `savedAt` reads back; the UUID keeps
        // shares saved in the same second apart.
        let name = "screenshot-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    /// Screenshots waiting to be scanned, oldest first.
    static func pending() -> [URL] {
        guard let dir = inboxURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.lastPathComponent.hasPrefix("screenshot-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Drop every waiting screenshot, however recent. The user asking for this outranks the
    /// hold-onto-them posture that ``purgeStale(now:)`` bounds.
    @discardableResult
    static func removeAll() -> Int {
        let waiting = pending()
        waiting.forEach(remove)
        return waiting.count
    }

    // MARK: Bounds

    /// How long an unresolved screenshot is kept. A share that never scanned is still something the
    /// user asked us to hold, so it survives failures and restarts — but "hold it" was never meant
    /// to mean "keep a picture of the user's screen in the App Group forever." A month is long
    /// enough to cover the reason files land here in the first place (AI not set up yet, no signal,
    /// a scan the user cut short) and short enough that a screenshot they forgot about goes away.
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    /// Ceiling on how many are kept at once, oldest dropped first. The age limit is the real rule;
    /// this only catches the pathological case — a user sharing in dozens of screenshots while AI
    /// is unconfigured, where nothing has aged out yet and every one of them is still on disk.
    static let maxCount = 20

    /// Drop screenshots that have aged out or overflowed the ceiling.
    ///
    /// Called at launch, before anything decides whether to scan, so it runs even on the paths that
    /// return early — an unconfigured provider is exactly when files accumulate.
    @discardableResult
    static func purgeStale(now: Date = Date()) -> Int {
        let waiting = pending()
        guard !waiting.isEmpty else { return 0 }

        var doomed = waiting.filter { url in
            guard let saved = savedAt(url) else { return false }
            return now.timeIntervalSince(saved) > maxAge
        }

        // `pending()` sorts by filename and the names embed the save-time epoch, so the survivors
        // stay in age order and the overflow comes off the front.
        let survivors = waiting.filter { !doomed.contains($0) }
        if survivors.count > maxCount {
            doomed += survivors.prefix(survivors.count - maxCount)
        }

        doomed.forEach(remove)
        return doomed.count
    }

    /// When `save` wrote this file, read back out of the name it chose. Preferred over a filesystem
    /// date because a copy or a container migration rewrites those and would silently reset the age.
    private static func savedAt(_ url: URL) -> Date? {
        let parts = url.lastPathComponent.split(separator: "-")
        guard parts.count >= 2, let epoch = TimeInterval(parts[1]) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }
}
