import Foundation

/// The App Group folder: the library, the logs and saved camera reports live in it. Only the app
/// uses it now; it stays an App Group because that is where every existing install keeps its data.
///
/// On iOS, and on a Mac build signed by a team, it is the App Group container, exactly as
/// `containerURL(forSecurityApplicationGroupIdentifier:)` gives it.
///
/// A Mac Catalyst build signed to run locally (`scripts/run-mac.sh`) has no provisioning profile,
/// and macOS refuses such an app its `group.` container. That build falls back to a folder in its
/// own Application Support, so it opens a library of its own instead of stopping at launch. iCloud
/// sync doesn't work there; nothing else changes.
enum SharedContainer {
    /// Nil only where the App Group is missing on iOS, which `AppIdentifiers` already stops at.
    static let url: URL? = resolve()

    /// Whether `url` is the App Group container rather than the local Mac fallback.
    static var isAppGroup: Bool { url == groupURL }

    /// A Mac build signed to run locally, without a team. Besides the App Group it can't reach a
    /// camera: macOS never answers its ImageCaptureCore permission request, and a connect left
    /// waiting on that answer brought the app down when it ended (macOS 27.3, 2026-11-13). The
    /// camera's USB functions are off in it.
    static var isLocalMacBuild: Bool {
        #if targetEnvironment(macCatalyst)
        return !isAppGroup
        #else
        return false
        #endif
    }

    private static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)
    }

    private static func resolve() -> URL? {
        #if targetEnvironment(macCatalyst)
        if let group = groupURL, isWritable(group) { return group }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let local = support.appendingPathComponent(AppIdentifiers.base, isDirectory: true)
            .appendingPathComponent("SharedContainer", isDirectory: true)
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        return local
        #else
        return groupURL
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// Whether a file can actually be created there: macOS hands back the path of a group container
    /// it then won't let the app write to.
    private static func isWritable(_ container: URL) -> Bool {
        let probe = container.appendingPathComponent(".write-probe-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }
    #endif
}
