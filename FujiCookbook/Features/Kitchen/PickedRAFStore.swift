import Foundation

/// Where picked RAW files live between the picker and the cook.
///
/// `UIDocumentPickerViewController(asCopy: true)` hands its copies back in `tmp/<bundle id>-Inbox`,
/// and iOS empties that Inbox each time the picker is presented again, so a file still listed as
/// selected can be gone by the time the Kitchen reads it. Picked files move in here at pick time,
/// so a selection stays readable for as long as it's listed.
enum PickedRAFStore {
    /// Application Support rather than Documents: these are working copies of files the user already
    /// has elsewhere, so they have no business showing up in the Files app or in a backup.
    private static var root: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("PickedRAFs", isDirectory: true)
    }

    /// Take ownership of freshly picked files, returning the URLs to use from here on.
    ///
    /// Each pick gets its own directory, and each file its own subdirectory inside it, so staging a
    /// selection on one screen can't disturb one staged on another and two files that share a name
    /// can't collide. A file that can't be staged is passed through at its original URL rather than
    /// dropped — if it's still readable at cook time nothing is lost, and if it isn't, the cook
    /// reports it by name.
    static func stage(_ urls: [URL]) -> [URL] {
        guard !urls.isEmpty, let root else { return urls }
        let pick = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: pick, withIntermediateDirectories: true)) != nil
        else { return urls }
        excludeFromBackup(pick)

        return urls.enumerated().map { index, url in
            let directory = pick.appendingPathComponent("\(index)", isDirectory: true)
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                // The picker's copies are ours to move, and a move within the container is a rename
                // — worth doing over a copy when a single RAF runs to 87 MB from an X-T50 and
                // 198 MiB from a GFX100S (zgrimz/fujifilm-ptp-reference `docs/09-platform-notes.md`,
                // `docs/05-raw-conversion.md`).
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            } catch {
                if (try? FileManager.default.copyItem(at: url, to: destination)) != nil { return destination }
                // Passing the original URL through is the deliberate fallback: a file that's still
                // readable at cook time loses nothing. But it leaves the file where the picker put
                // it, which iOS can empty before the cook reads it. The log line carries no path:
                // `bounded` drops the filename the `CocoaError` would otherwise carry.
                AppLog.error(.kitchen, "Couldn't stage a picked RAF out of the Inbox; using it in place — \(AppLog.bounded(error))")
                return url
            }
        }
    }

    /// Let go of staged files the user has deselected. Only ever deletes inside the staging area, so
    /// a URL that was passed through un-staged is left where it is.
    static func discard(_ urls: [URL]) {
        guard let root else { return }
        let rootComponents = root.standardizedFileURL.pathComponents
        for url in urls {
            // Shaped `<root>/<pick>/<index>/<name>`; anything else isn't ours to remove.
            let components = url.standardizedFileURL.pathComponents
            guard components.count == rootComponents.count + 3,
                  Array(components.prefix(rootComponents.count)) == rootComponents else { continue }
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: directory)
            let pick = directory.deletingLastPathComponent()
            if let remaining = try? FileManager.default.contentsOfDirectory(atPath: pick.path),
               remaining.isEmpty {
                try? FileManager.default.removeItem(at: pick)
            }
        }
    }

    /// Clear the staging area. Called at launch: nothing is selected at that point, so whatever is
    /// still here belongs to a run that ended with files picked.
    static func purge() {
        guard let root else { return }
        try? FileManager.default.removeItem(at: root)
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
