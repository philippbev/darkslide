/// How the Camera tab presents the camera it holds.
enum CameraCardState: Equatable {
    /// A session that is up: the card says connected.
    case live
    /// A dropped session the connector is getting back. The card keeps the camera last seen,
    /// because recovery only ever re-adopts that same body, but stops calling it connected.
    case reconnecting

    /// Nil when there is no camera to show.
    ///
    /// Decided by the connector's recovery flag rather than by the status, so it holds for the
    /// whole recovery: through each attempt's `.connecting`, a failed attempt's `.failed` while the
    /// next one waits, and the slot re-read's `.working`. That is steadier than
    /// `GuidedTestRunner.gate`, which reports `.reconnecting` only while the status is `.working`,
    /// because a test step only needs to know whether it can run now.
    ///
    /// A recovery that gives up clears the camera before its task clears the flag, so a camera that
    /// is gone is never shown as reconnecting.
    init?(isConnected: Bool, isRecovering: Bool) {
        guard isConnected else { return nil }
        self = isRecovering ? .reconnecting : .live
    }
}
