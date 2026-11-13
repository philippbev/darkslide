import CoreGraphics
import Foundation

/// Where photos are imported from: the camera's card over USB, or the demo card. A source only
/// reads. Nothing on the card is changed, renamed or deleted.
@MainActor
protocol PhotoSource: AnyObject {
    /// The camera's name, for the status card.
    var displayName: String { get }

    /// Connect and list the card. Throws `PhotoImportError`.
    func open() async throws -> [ImportFile]

    /// A small picture of the file, or nil when the source has none.
    func thumbnail(for file: ImportFile) async -> CGImage?

    /// Copy the file into `directory` under its own name and return where it landed.
    func download(_ file: ImportFile, to directory: URL) async throws -> URL

    func close() async
}

enum PhotoImportError: LocalizedError, Equatable {
    case recipeSessionActive
    case noCamera
    case permissionDenied
    /// The camera answered but lists no photos: an empty card, or a USB mode that doesn't show the
    /// card.
    case noPhotos
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
            return "Camera access is off. Enable it for Fuji Cookbook in Settings, then try again."
        case .noPhotos:
            return "The camera lists no photos. If the card isn't empty, the camera is in another USB mode. \(Self.cardReaderHint)"
        case .catalogTimedOut:
            return "The camera didn't finish listing its card. Reconnect it and try again. \(Self.cardReaderHint)"
        case .sourceFailed(let detail):
            return "Couldn't read the camera's card: \(detail)"
        case .downloadFailed(let file, let detail):
            return "Couldn't copy \(file) from the camera: \(detail)"
        case .photoLibraryDenied:
            return "Photo library access is off. Enable it for Fuji Cookbook in Settings, then try again."
        case .destinationUnavailable(let detail):
            return "The destination folder can't be written to: \(detail)"
        case .localMacBuild:
            return "This Mac build is signed to run locally, without an Apple developer team, and macOS doesn't let such a build reach a camera over USB. The Demo Card under the diagnostic tools works. A build signed with your team can import from the camera."
        }
    }
}
