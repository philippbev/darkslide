import Foundation
import UIKit

/// Who this build is and what it is running on — the four lines every report starts with.
///
/// One fallback for a missing `Info.plist` key, `"?"`, rather than one per reader — a state that
/// cannot occur in a built app either way.
enum AppIdentity {
    /// `CFBundleShortVersionString` — the marketing version someone quotes in a bug report.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// `CFBundleVersion` — the build number that pins down which binary they actually have.
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// `1.0 (12)`. What a person reads; never what a machine parses.
    static var versionString: String { "\(version) (\(build))" }

    /// The iOS version, **bare** — `26.1`, not `iOS 26.1`.
    ///
    /// Load-bearing: `CameraCompatibilityReport.HostInfo.systemVersion` is a `Codable` field in the
    /// JSON artifact and stores it unprefixed; the `"iOS "` is added when rendering. Prefixing here
    /// would change the wire format.
    @MainActor
    static var systemVersion: String { UIDevice.current.systemVersion }

    /// The hardware identifier — `iPhone16,1` rather than `UIDevice.current.model`'s bare "iPhone",
    /// which can't tell an iPhone SE from an iPad and so answers none of the questions a report is
    /// opened to answer. On the Simulator this reads the host's architecture, so fall back to the
    /// name the Simulator advertises.
    static var deviceIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            raw.prefix { $0 != 0 }.map { Character(UnicodeScalar(UInt8($0))) }
        }
        return String(machine)
    }

    /// The four lines that open every report and feedback file, padded to one column so two
    /// messages from one tester line up when read side by side.
    @MainActor
    static var reportLines: [String] {
        ["App          \(versionString)",
         "Channel      \(BuildChannel.current.rawValue)",
         "System       iOS \(systemVersion)",
         "Device       \(deviceIdentifier)"]
    }
}
