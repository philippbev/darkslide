import CoreGraphics
import Foundation

/// Where photos are imported from: the camera's card over USB, or the demo card. A source only
/// reads. Nothing on the card is changed, renamed or deleted.
@MainActor
protocol PhotoSource: AnyObject {
    /// The camera's name, for the status card.
    var displayName: String { get }

    /// Connect and list the card. Returns the whole list once the camera has given it; meanwhile
    /// reports how far it has got and hands over what it has so far, so the newest days can be
    /// shown and imported long before a full card is listed. Throws `PhotoImportError`.
    func open(progress: @escaping @MainActor (CatalogProgress) -> Void,
              partial: @escaping @MainActor ([ImportFile]) -> Void) async throws -> [ImportFile]

    /// Whether older files are left to read: a source that lists a portion at a time.
    var canLoadMore: Bool { get }

    /// Read the next portion of older files and return everything listed so far.
    func loadMore(progress: @escaping @MainActor (CatalogProgress) -> Void) async throws -> [ImportFile]

    /// A small picture of the file, or nil when the source has none.
    func thumbnail(for file: ImportFile) async -> CGImage?

    /// The film simulation the file was taken with, read from the camera's own preview of it; nil
    /// when the preview carries no Fujifilm MakerNote or the source has none. Only reads.
    func filmSimulation(for file: ImportFile) async -> FilmSimulation?

    /// Copy the file into `directory` under its own name and return where it landed.
    func download(_ file: ImportFile, to directory: URL) async throws -> URL

    func close() async
}

extension PhotoSource {
    /// A source that lists the whole card at once has nothing more to read.
    var canLoadMore: Bool { false }
    func loadMore(progress: @escaping @MainActor (CatalogProgress) -> Void) async throws -> [ImportFile] { [] }
    func filmSimulation(for file: ImportFile) async -> FilmSimulation? { nil }
}

/// The film simulation in a preview's Fujifilm MakerNote, if the preview carries one.
enum PreviewSimulation {
    static func read(_ preview: Data, name: String) -> FilmSimulation? {
        guard let reading = try? PhotoRecipeReader.read(preview, filename: name),
              reading.recipeStatus == .found else { return nil }
        return reading.settings.filmSimulation
    }
}

/// How far a card's listing has got: a full card takes a while over USB.
struct CatalogProgress: Equatable, Sendable {
    /// What the camera reports, 0 to 100.
    var percent: Int
    /// Files listed so far.
    var files: Int
    /// How long the listing has gone without getting further.
    var idleSeconds: Int = 0
    /// What the camera is doing, when there is more to say than a percentage.
    var note: String? = nil

    /// A minute without progress: worth saying, though a camera can sit at 0 % that long before
    /// the first file arrives (X100VI, iPhone, 2026-11-13), so it isn't treated as a failure.
    var looksStuck: Bool { idleSeconds >= 60 }
}

enum PhotoImportError: LocalizedError, Equatable {
    case recipeSessionActive
    case noCamera
    case permissionDenied
    /// The camera answered but lists no photos: an empty card, or a USB mode that doesn't show the
    /// card.
    /// `diagnostics`: what the camera answered, shown beneath the message.
    case noPhotos(diagnostics: String? = nil)
    case catalogTimedOut
    case sourceFailed(String)
    case downloadFailed(file: String, detail: String)
    case photoLibraryDenied
    case destinationUnavailable(String)
    case localMacBuild

    /// The setting a Fujifilm body needs for the card to be readable over USB.
    static let cardReaderHint = "On the camera, set Network/USB Setting → Connection Mode to “USB Card Reader”. Recipes need “USB RAW Conv./Backup Restore”, so switch back afterwards."

    var errorDescription: String? {
        switch self {
        case .recipeSessionActive:
            return "The camera is connected for recipes. Disconnect it in the Camera tab first: importing photos uses a different USB mode. \(Self.cardReaderHint)"
        case .noCamera:
            return "No camera detected. Connect it with a USB data cable. \(Self.cardReaderHint)"
        case .permissionDenied:
            return "Camera access is off. Enable it for Darkslide in Settings, then try again."
        case .noPhotos(let diagnostics):
            let message = "The camera lists no photos. If the card isn't empty, the camera is in another USB mode. \(Self.cardReaderHint)"
            return diagnostics.map { "\(message)\n\nWhat the camera answered: \($0)" } ?? message
        case .catalogTimedOut:
            return "The camera didn't finish listing its card. Reconnect it and try again. \(Self.cardReaderHint)"
        case .sourceFailed(let detail):
            return "Couldn't read the camera's card: \(detail)"
        case .downloadFailed(let file, let detail):
            return "Couldn't copy \(file) from the camera: \(detail)"
        case .photoLibraryDenied:
            return "Photo library access is off. Enable it for Darkslide in Settings, then try again."
        case .destinationUnavailable(let detail):
            return "The destination folder can't be written to: \(detail)"
        case .localMacBuild:
            return "This Mac build is signed to run locally, without an Apple developer team, and macOS doesn't let such a build reach a camera over USB. The Demo Card under the diagnostic tools works. A build signed with your team can import from the camera."
        }
    }
}
