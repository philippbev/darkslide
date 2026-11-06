import Foundation

/// The fixed header at the front of every Fujifilm RAF, read before the file goes anywhere.
///
/// Bytes 0–15 are the magic `FUJIFILMCCD-RAW `, 16–19 a format version (`0201`), 20–27 the camera
/// ID (`FF189504` on the X-T50, the same string the conversion profile carries as its IOPCode),
/// 28–59 the model name NUL-padded to 32 bytes (`X-T50`), 60–63 the firmware that wrote the file
/// (`0132`). Layout from ExifTool's `FujiFilm::RAFHeader` table at the revision the record pins
/// (13.55, `de11d240`), whose example header gives the leading fields and which calls bytes 60–63
/// `RAFVersion`, and from libopenraw's RAF format page, which gives the model name's 32 bytes.
/// X-T50 fw 1.32, 2026-10-19: a RAF's first 64 bytes match, with `0132` in bytes 60–63.
///
/// The model name is what the Kitchen checks before an upload: a Fujifilm body develops only its
/// own files, so a file that names another body can be refused without sending it, and a `0x2002`
/// after sending a file that names this body is not blamed on the file. The body
/// requirement is recorded in zgrimz/fujifilm-ptp-reference `docs/05-raw-conversion.md#prerequisites`.
struct RAFHeader: Equatable {
    static let magic = Data("FUJIFILMCCD-RAW ".utf8)
    static let length = 64

    /// Bytes 20–27, as ASCII.
    let cameraID: String
    /// Bytes 28–59 with the NUL padding removed.
    let model: String
    /// Bytes 60–63, as ASCII; nil when they aren't printable.
    let firmware: String?

    init?(_ data: Data) {
        guard data.count >= Self.length, data.prefix(Self.magic.count) == Self.magic else { return nil }
        let start = data.startIndex
        func ascii(_ range: Range<Int>) -> String? {
            let bytes = data[(start + range.lowerBound)..<(start + range.upperBound)]
                .prefix { $0 != 0 }
            guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
            return String(decoding: bytes, as: UTF8.self)
        }
        guard let cameraID = ascii(20..<28), let model = ascii(28..<60), !model.isEmpty else { return nil }
        self.cameraID = cameraID
        self.model = model
        self.firmware = ascii(60..<64).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// What the header says about the file against the connected body.
    enum Origin: Equatable {
        /// The header names the connected body.
        case sameBody
        /// The header names another registry body.
        case otherBody(CameraModel)
        /// Nothing to compare: the demo camera, or a model name the registry can't place.
        case undetermined
    }

    /// Which body the file names, judged against `model` through the registry's own identification
    /// (`CameraModelRegistry.identify`), so a spelling the registry recognises as this body counts
    /// as this body and one it can't place decides nothing. The demo camera renders locally and
    /// develops any file, so it is never a mismatch. The camera ID isn't compared: the registry
    /// doesn't carry one per body, and the model name already settles the question.
    func origin(for model: CameraModel, registry: CameraModelRegistry = .shared) -> Origin {
        guard model.id != CameraModelRegistry.demoModelID else { return .undetermined }
        let identification = registry.identify(productName: self.model)
        guard identification.isTrusted, let declared = identification.model else { return .undetermined }
        return declared.id == model.id ? .sameBody : .otherBody(declared)
    }
}
