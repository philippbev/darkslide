import Foundation

/// How hard to try to get a dropped session back.
enum RecoveryPolicy {

    /// The delay before each reconnect attempt, in nanoseconds, and how long each attempt waits for
    /// the device to reappear.
    ///
    /// Pure, so the schedule can be tested without sitting through the loop it feeds.
    ///
    /// The expected wait is a ceiling, not a delay: `CameraDeviceBrowser.firstCamera` resolves the
    /// instant the device appears. GFX100S, 2026-09-15 Camera Test: 19 s to reappear after a
    /// power cycle. What the longer wait costs is that a dead cable during an expected removal is
    /// reported that much later.
    static func plan(expected: Bool) -> (delays: [UInt64], deviceWait: TimeInterval) {
        expected
            ? ([1_000_000_000, 3_000_000_000, 5_000_000_000], 20)
            : ([500_000_000, 1_500_000_000, 3_000_000_000], 4)
    }
}
