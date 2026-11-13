import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes a position into imported photos without touching their pictures.
///
/// Only copies are changed, after they have left the camera; nothing on the card is.
enum GeoTagWriter {
    /// Adds the GPS block to a JPEG or HEIF in place. The image data is copied over as it is, not
    /// decoded and compressed again; only the metadata changes. False when ImageIO can't do that for
    /// this file, which is then left exactly as it was.
    @discardableResult
    static func embed(_ point: GeoPoint, into url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else { return false }
        let metadata = CGImageMetadataCreateMutable()
        for (key, value) in gpsProperties(for: point) {
            guard CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyGPSDictionary,
                                                               key, value as CFTypeRef) else { return false }
        }
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-\(url.lastPathComponent)")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil) else { return false }
        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata,
                                        kCGImageDestinationMergeMetadata: true]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            try? FileManager.default.removeItem(at: temporary)
            return false
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            return true
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            return false
        }
    }

    /// Whether an image file already carries a position.
    static func hasPosition(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] else { return false }
        return gps[kCGImagePropertyGPSLatitude] != nil
    }

    static func gpsProperties(for point: GeoPoint) -> [CFString: Any] {
        var properties: [CFString: Any] = [
            kCGImagePropertyGPSVersion: [2, 3, 0, 0],
            kCGImagePropertyGPSLatitude: abs(point.latitude),
            kCGImagePropertyGPSLatitudeRef: point.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(point.longitude),
            kCGImagePropertyGPSLongitudeRef: point.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSDateStamp: utc("yyyy:MM:dd").string(from: point.timestamp),
            kCGImagePropertyGPSTimeStamp: utc("HH:mm:ss.SS").string(from: point.timestamp),
            kCGImagePropertyGPSHPositioningError: point.horizontalAccuracy
        ]
        if let altitude = point.altitude {
            properties[kCGImagePropertyGPSAltitude] = abs(altitude)
            properties[kCGImagePropertyGPSAltitudeRef] = altitude < 0 ? 1 : 0
        }
        return properties
    }

    // MARK: XMP sidecar

    /// The sidecar beside a RAF: "DSCF1284.RAF" → "DSCF1284.xmp", the name Lightroom and Bridge look
    /// for. The RAF itself is never changed.
    static func sidecarName(for fileName: String) -> String {
        "\((fileName as NSString).deletingPathExtension).xmp"
    }

    /// Writes the sidecar. One that already exists is left alone: it may hold the user's edits.
    @discardableResult
    static func writeSidecar(_ point: GeoPoint, besideFileNamed fileName: String, in folder: URL) throws -> URL? {
        let url = folder.appendingPathComponent(sidecarName(for: fileName))
        guard !FileManager.default.fileExists(atPath: url.path) else { return nil }
        try Data(sidecar(for: point).utf8).write(to: url, options: .withoutOverwriting)
        return url
    }

    static func sidecar(for point: GeoPoint) -> String {
        var attributes = [
            "exif:GPSVersionID=\"2.3.0.0\"",
            "exif:GPSLatitude=\"\(xmpCoordinate(point.latitude, positive: "N", negative: "S"))\"",
            "exif:GPSLongitude=\"\(xmpCoordinate(point.longitude, positive: "E", negative: "W"))\"",
            "exif:GPSTimeStamp=\"\(ISO8601DateFormatter().string(from: point.timestamp))\"",
            "exif:GPSHPositioningError=\"\(Int(point.horizontalAccuracy.rounded()))/1\""
        ]
        if let altitude = point.altitude {
            attributes.append("exif:GPSAltitude=\"\(Int((abs(altitude) * 100).rounded()))/100\"")
            attributes.append("exif:GPSAltitudeRef=\"\(altitude < 0 ? 1 : 0)\"")
        }
        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:exif="http://ns.adobe.com/exif/1.0/"
            \(attributes.joined(separator: "\n    "))/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>

        """
    }

    /// XMP's GPS coordinate form: degrees, decimal minutes and the hemisphere, "38,28.1234N".
    static func xmpCoordinate(_ value: Double, positive: String, negative: String) -> String {
        let magnitude = abs(value)
        let degrees = Int(magnitude)
        let minutes = (magnitude - Double(degrees)) * 60
        return "\(degrees),\(String(format: "%.6f", minutes))\(value >= 0 ? positive : negative)"
    }

    private static func utc(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}
