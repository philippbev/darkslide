import Foundation

/// A RAF to send to the camera, and where its bytes come from.
///
/// The conversion service asks for the bytes with `load` right before the upload and lets them go
/// once the upload has returned, so one file's bytes are in memory at a time however many were
/// picked. ImageCaptureCore takes an upload's data phase as a single `Data`, so that one file is the
/// floor: a RAF uploads at 87 MB from an X-T50 and 208,071,296 bytes from a GFX100S
/// (zgrimz/fujifilm-ptp-reference `docs/09-platform-notes.md`, `docs/05-raw-conversion.md`).
/// `filename` is the user's: it labels results and names the saved JPEG, and never reaches the log.
struct RAFSource {
    let filename: String
    /// Produces the RAF's bytes. The service calls it once per upload, and only then. A throw is
    /// reported for that file as `CameraError.rafUnreadable`, and a batch goes on to its next file.
    let load: () async throws -> Data

    /// Bytes already in hand: the single-file `cook`, the D185 probe, and tests.
    static func inMemory(_ data: Data, filename: String) -> RAFSource {
        RAFSource(filename: filename, load: { data })
    }
}

/// One item of a Develop batch: a RAF and the recipe to develop it with.
struct CookItem {
    let raf: RAFSource
    let settings: RecipeSettings
}
