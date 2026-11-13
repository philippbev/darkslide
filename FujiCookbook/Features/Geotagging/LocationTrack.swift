import CoreLocation
import Foundation

/// One recorded position.
struct GeoPoint: Codable, Equatable, Sendable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Metres above sea level; nil when the fix had no vertical component.
    var altitude: Double?
    /// Radius of uncertainty in metres.
    var horizontalAccuracy: Double

    init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double? = nil, horizontalAccuracy: Double = 10) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
    }

    init(_ location: CLLocation) {
        self.init(timestamp: location.timestamp,
                  latitude: location.coordinate.latitude,
                  longitude: location.coordinate.longitude,
                  altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                  horizontalAccuracy: location.horizontalAccuracy)
    }

    var location: CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                   altitude: altitude ?? 0,
                   horizontalAccuracy: horizontalAccuracy,
                   verticalAccuracy: altitude == nil ? -1 : 10,
                   timestamp: timestamp)
    }

    func distance(to other: GeoPoint) -> CLLocationDistance {
        location.distance(from: other.location)
    }
}

/// The positions recorded on one photo walk, in time order.
struct LocationTrack: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var startedAt: Date
    /// Nil while recording.
    var endedAt: Date?
    var points: [GeoPoint] = []

    var duration: TimeInterval { (endedAt ?? points.last?.timestamp ?? startedAt).timeIntervalSince(startedAt) }

    /// Whether a fix is worth keeping: precise enough to place a photo, newer than the last one,
    /// and either moved or a while later. Standing still for an hour still leaves a point every
    /// minute, so a photo taken there still finds one.
    static func shouldKeep(_ point: GeoPoint, after last: GeoPoint?) -> Bool {
        guard point.horizontalAccuracy >= 0, point.horizontalAccuracy <= 100 else { return false }
        guard let last else { return true }
        guard point.timestamp > last.timestamp else { return false }
        return point.distance(to: last) >= 10 || point.timestamp.timeIntervalSince(last.timestamp) >= 60
    }
}

/// Tracks on disk, one JSON file each, in Application Support. Nothing leaves the device.
struct LocationTrackStore {
    let directory: URL

    static var standard: LocationTrackStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocationTrackStore(directory: base.appendingPathComponent("LocationTracks", isDirectory: true))
    }

    /// Newest first. A file that can't be read is skipped rather than failing the list.
    func all() -> [LocationTrack] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? Self.decoder.decode(LocationTrack.self, from: $0) } }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Every point of every track, in time order: what an import matches photos against.
    func allPoints() -> [GeoPoint] {
        all().flatMap(\.points).sorted { $0.timestamp < $1.timestamp }
    }

    func save(_ track: LocationTrack) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(track).write(to: url(for: track.id), options: .atomic)
    }

    func delete(_ id: LocationTrack.ID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
