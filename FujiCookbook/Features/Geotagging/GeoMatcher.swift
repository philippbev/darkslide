import Foundation
import ImageIO

/// Finds where the phone was when a photo was taken.
struct GeoMatcher {
    /// A photo between two points no further apart than this is placed on the line between them.
    static let maxInterpolationGap: TimeInterval = 10 * 60
    /// Otherwise the nearest point counts if it is this close in time.
    static let maxNearestDistance: TimeInterval = 5 * 60

    private let points: [GeoPoint]

    /// `points` in any order.
    init(points: [GeoPoint]) {
        self.points = points.sorted { $0.timestamp < $1.timestamp }
    }

    var isEmpty: Bool { points.isEmpty }

    /// Nil when the track has nothing near that time: better no location than a wrong one.
    func point(at date: Date) -> GeoPoint? {
        guard !points.isEmpty else { return nil }
        // First point at or after `date`.
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp < date { low = mid + 1 } else { high = mid }
        }
        let after = low < points.count ? points[low] : nil
        let before = low > 0 ? points[low - 1] : nil

        if let before, let after {
            let gap = after.timestamp.timeIntervalSince(before.timestamp)
            if gap <= Self.maxInterpolationGap {
                return Self.interpolate(before, after, at: date)
            }
        }
        let nearest = [before, after].compactMap { $0 }
            .min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
        guard let nearest, abs(nearest.timestamp.timeIntervalSince(date)) <= Self.maxNearestDistance else { return nil }
        return GeoPoint(timestamp: date, latitude: nearest.latitude, longitude: nearest.longitude,
                        altitude: nearest.altitude, horizontalAccuracy: nearest.horizontalAccuracy)
    }

    private static func interpolate(_ a: GeoPoint, _ b: GeoPoint, at date: Date) -> GeoPoint {
        let span = b.timestamp.timeIntervalSince(a.timestamp)
        let f = span > 0 ? date.timeIntervalSince(a.timestamp) / span : 0
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        let altitude: Double? = { if let x = a.altitude, let y = b.altitude { return mix(x, y) }; return a.altitude ?? b.altitude }()
        return GeoPoint(timestamp: date, latitude: mix(a.latitude, b.latitude), longitude: mix(a.longitude, b.longitude),
                        altitude: altitude, horizontalAccuracy: max(a.horizontalAccuracy, b.horizontalAccuracy))
    }
}

/// How far the camera's clock is off. Positive when the camera is ahead: a photo it stamps 12:05
/// was taken at 12:00 with an offset of five minutes.
///
/// Also covers a camera left on home time abroad, which is an offset of whole hours.
enum CameraClockOffset {
    static let key = "geotag.cameraClockOffset"

    static func load(from defaults: UserDefaults = .standard) -> TimeInterval {
        defaults.double(forKey: key)
    }

    static func save(_ offset: TimeInterval, to defaults: UserDefaults = .standard) {
        defaults.set(offset, forKey: key)
    }

    /// "In sync", "Ahead 1 h 5 min", "Behind 3 min".
    static func label(_ offset: TimeInterval) -> String {
        let minutes = Int((abs(offset) / 60).rounded())
        guard minutes > 0 else { return "In Sync" }
        let text = minutes >= 60 ? "\(minutes / 60) h\(minutes % 60 == 0 ? "" : " \(minutes % 60) min")" : "\(minutes) min"
        return "\(offset > 0 ? "Ahead" : "Behind") \(text)"
    }
}

/// When a photo was taken, from its own EXIF.
enum CaptureTime {
    /// A Fujifilm body writes local time; newer firmware adds the zone (`OffsetTimeOriginal`). With
    /// no zone in the file the camera is taken to be on the phone's zone, which a camera clock
    /// offset corrects when it isn't.
    static func date(dateTimeOriginal: String, subsecond: String? = nil, offset: String? = nil,
                     fallbackZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = offset.flatMap(zone(fromOffset:)) ?? fallbackZone
        guard var date = formatter.date(from: dateTimeOriginal.trimmingCharacters(in: .whitespaces)) else { return nil }
        if let subsecond, let digits = Double("0.\(subsecond.trimmingCharacters(in: .whitespaces))") {
            date.addTimeInterval(digits)
        }
        return date
    }

    /// "+01:00" → UTC+1.
    static func zone(fromOffset offset: String) -> TimeZone? {
        let parts = offset.trimmingCharacters(in: .whitespaces)
        guard parts.count == 6, let sign = parts.first, sign == "+" || sign == "-" else { return nil }
        let fields = parts.dropFirst().split(separator: ":")
        guard fields.count == 2, let hours = Int(fields[0]), let minutes = Int(fields[1]) else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }

    /// The capture time an image file states, or nil when it states none.
    static func date(ofFileAt url: URL, fallbackZone: TimeZone = .current) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return date(dateTimeOriginal: original,
                    subsecond: exif[kCGImagePropertyExifSubsecTimeOriginal] as? String,
                    offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String,
                    fallbackZone: fallbackZone)
    }
}
