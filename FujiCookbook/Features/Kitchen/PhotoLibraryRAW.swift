import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Copies the RAW file out of photos picked from the photo library, so a pick from Photos reaches
/// `PickedRAFStore` as a file URL, the way a pick from Files does.
///
/// Each item is loaded through a `Transferable` that imports a RAW image and nothing else, so a
/// photo's JPEG or HEIC can never stand in for the RAF the camera is about to develop. A photo
/// without a RAW resource is counted rather than dropped, so the picker can say what it left out.
///
/// The picker shares a RAW-only photo's RAF — a RAF the Fujifilm app downloaded to the phone is one
/// (X-T50 owner, 2026-10-31). A RAW+JPEG pair held as one photo is different: in the iOS 27
/// Simulator (2026-10-23) such a pair offered `public.jpeg` and two private thumbnail types, and
/// asking it for a RAW returned nothing; unconfirmed on a phone. Reaching that pair's RAF would take
/// photo library access, which this avoids.
enum PhotoLibraryRAW {
    /// What copying a selection produced: the RAW files now in the app's temporary directory, and
    /// how many picked photos didn't yield one.
    struct Import: Equatable {
        var urls: [URL] = []
        /// Photos the picker shares no RAW for: a JPEG or HEIC with nothing attached, which is the
        /// usual case, or a RAW+JPEG pair held as one photo.
        var withoutRAW = 0
        /// Photos that offer a RAW but couldn't be copied out of the library.
        var failed = 0
    }

    /// Whether a picked photo offers a RAW resource, judged from its content types before anything
    /// is loaded, so "no RAW here" stays distinct from "the copy failed".
    static func carriesRAW(_ types: [UTType]) -> Bool {
        types.contains { $0.conforms(to: .rawImage) }
    }

    /// Copy each picked photo's RAW file into the app, in the order picked. Stops early, and returns
    /// what it has so far, if the task is cancelled.
    static func copy(_ items: [PhotosPickerItem]) async -> Import {
        var result = Import()
        for item in items {
            guard !Task.isCancelled else { break }
            guard carriesRAW(item.supportedContentTypes) else {
                result.withoutRAW += 1
                continue
            }
            do {
                if let raw = try await item.loadTransferable(type: ReceivedRAW.self) {
                    result.urls.append(raw.url)
                } else {
                    result.failed += 1
                }
            } catch {
                result.failed += 1
                AppLog.error(.kitchen, "Couldn't copy a picked photo's RAW out of the library — \(AppLog.bounded(error))")
            }
        }
        return result
    }
}

extension PhotoLibraryRAW.Import {
    /// What to tell the user about the photos that didn't make it into the selection.
    struct Problem: Equatable {
        let title: String
        let message: String
    }

    /// Nil when every picked photo arrived as a RAW file.
    var problem: Problem? {
        guard withoutRAW + failed > 0 else { return nil }
        let total = urls.count + withoutRAW + failed
        var sentences: [String] = []
        if withoutRAW > 0 {
            // The plain fact first: the picked photo has no RAW, which for a JPEG is simply what it
            // is. The pair case is real but rare and unconfirmed on a phone, so it comes last and
            // hedged, and doesn't make a plain JPEG sound like a RAW the app failed to reach.
            if total == 1 {
                sentences.append("That photo has no RAW file attached.")
            } else if withoutRAW == total {
                sentences.append("None of those photos has a RAW file attached.")
            } else {
                sentences.append("\(withoutRAW) of the \(total) photos \(withoutRAW == 1 ? "has" : "have") no RAW file attached.")
            }
            sentences.append("Pick the .RAF itself — from Photos if the Fujifilm app downloaded it to your phone, or with Browse Files.")
            sentences.append("A photo Photos holds as a RAW+JPEG pair may offer only its JPEG; bring its .RAF in on its own.")
        }
        if failed > 0 {
            if total == 1 {
                sentences.append("Couldn't copy that photo from your library. Try again.")
            } else if failed == total {
                sentences.append("Couldn't copy those photos from your library. Try again.")
            } else {
                sentences.append("\(failed) of the \(total) photos couldn't be copied from your library. Try picking \(failed == 1 ? "it" : "them") again.")
            }
        }
        let title: String
        if total == 1 {
            title = "Couldn't Use That Photo"
        } else if urls.isEmpty {
            title = "Couldn't Use Those Photos"
        } else {
            title = "Some Photos Weren't Added"
        }
        return Problem(title: title, message: sentences.joined(separator: " "))
    }
}

/// A picked photo's RAW file, copied out of the picker's hands. The file `received` points at is
/// the system's and lasts only as long as the import closure, so the copy is made there.
private struct ReceivedRAW: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .rawImage) { received in
            // A directory per copy keeps the original name without two picks colliding.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ReceivedRAW(url: destination)
        }
    }
}
