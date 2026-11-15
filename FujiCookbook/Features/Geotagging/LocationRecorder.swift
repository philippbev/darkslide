import CoreLocation
import Foundation
import Observation

/// Records the phone's position while the user is out taking pictures, so an import can place
/// each photo by the time it was taken.
///
/// Runs with "While Using" permission. Started in the foreground, it carries on with the screen
/// locked or the app in the background (`UIBackgroundModes` location; iOS shows the location
/// indicator meanwhile). It doesn't survive the app being quit: what was recorded until then is
/// kept, and the track is closed at its last point on the next launch.
@MainActor
@Observable
final class LocationRecorder: NSObject {
    static let shared = LocationRecorder()

    private(set) var current: LocationTrack?
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastError: String?

    var isRecording: Bool { current != nil }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let store: LocationTrackStore
    @ObservationIgnored private var unsavedPoints = 0
    @ObservationIgnored private var startWhenAuthorized = false

    init(store: LocationTrackStore = .standard) {
        self.store = store
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        Self.closeUnfinished(in: store)
    }

    func start() {
        lastError = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            startWhenAuthorized = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            begin()
        default:
            lastError = "Location access is off. Enable it for Darkslide in Settings to record a track."
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        guard var track = current else { return }
        track.endedAt = track.points.last?.timestamp ?? .now
        current = nil
        persist(track)
    }

    private func begin() {
        guard current == nil else { return }
        let track = LocationTrack(startedAt: .now)
        current = track
        persist(track)
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        CameraLog.info("Location: recording started")
    }

    private func append(_ locations: [CLLocation]) {
        guard var track = current else { return }
        for location in locations {
            let point = GeoPoint(location)
            guard LocationTrack.shouldKeep(point, after: track.points.last) else { continue }
            track.points.append(point)
            unsavedPoints += 1
        }
        current = track
        // Every few points rather than every one: a long walk writes the file a few hundred
        // times, not thousands, and a quit loses at most the last few.
        if unsavedPoints >= 10 { persist(track) }
    }

    private func persist(_ track: LocationTrack) {
        do {
            try store.save(track)
            unsavedPoints = 0
        } catch {
            lastError = "The track couldn't be saved: \(error.localizedDescription)"
        }
    }

    /// A track left open by an app that was quit while recording ends at its last point.
    private static func closeUnfinished(in store: LocationTrackStore) {
        for var track in store.all() where track.endedAt == nil {
            track.endedAt = track.points.last?.timestamp ?? track.startedAt
            try? store.save(track)
        }
    }
}

extension LocationRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.startWhenAuthorized {
                self.startWhenAuthorized = false
                self.start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.append(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // `locationUnknown` is transient; the manager keeps trying.
        guard (error as? CLError)?.code != .locationUnknown else { return }
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}
