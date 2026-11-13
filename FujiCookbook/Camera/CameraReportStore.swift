import Foundation

/// Where the latest report lives on disk: the App Group container, next to the logs, so it survives
/// disconnect, relaunch and — when the session ends in one — a crash. One file, holding the newest
/// report; the JSON carries its own timestamps.
enum CameraReportStore {
    static var directoryURL: URL? {
        SharedContainer.url?
            .appendingPathComponent("Reports", isDirectory: true)
    }

    static var latestURL: URL? { directoryURL?.appendingPathComponent("camera-compatibility-latest.json") }

    @discardableResult
    static func save(_ report: CameraCompatibilityReport) -> URL? {
        guard let dir = directoryURL, let url = latestURL else { return nil }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try report.json.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.error(.camera, "Report: could not save the compatibility report — \(AppLog.bounded(error))")
            return nil
        }
    }

    static func loadLatest() -> CameraCompatibilityReport? {
        guard let url = latestURL, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try CameraCompatibilityReport.decode(data)
        } catch {
            AppLog.error(.camera, "Report: the saved compatibility report could not be decoded — \(AppLog.bounded(error))")
            return nil
        }
    }

    /// What Clear Diagnostics calls: keep the drift baseline, drop everything else. Deletes the
    /// file outright when there is no applied push to keep a baseline for — a report with nothing
    /// in it is not worth a file.
    static func stripLatestToDriftBaseline() {
        guard var report = loadLatest() else { return }
        report.stripToDriftBaseline()
        if report.pushes == nil { deleteLatest(); return }
        save(report)
    }

    /// Delete the stored report. The file outlives the camera being unplugged by design — that is
    /// what lets a user write up a problem after they have packed the camera away — so the slot
    /// contents it carries stay on disk until this runs.
    static func deleteLatest() {
        guard let url = latestURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
