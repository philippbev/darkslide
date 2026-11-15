import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Photos

/// The app's exported recipe UTI (mirrors Info.plist `UTExportedTypeDeclarations`).
///
/// `exportedAs:` traps if this string and the Info.plist declaration disagree, so the two move
/// together or not at all — see `RecipeUTITests`. `.fujirecipe` files exported under an older
/// identifier still open, because Launch Services matches them on the filename extension in
/// `UTTypeTagSpecification`, not on the identifier itself.
extension UTType {
    static var fujiRecipe: UTType {
        UTType(exportedAs: "xyz.grovehouse.fujicookbook.recipe", conformingTo: .json)
    }
}

/// The files a share sheet offers, for use with `.sheet(item:)`. Several at once for a tiled export,
/// in posting order.
struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]

    init(urls: [URL]) { self.urls = urls }
    init(url: URL) { self.init(urls: [url]) }

    /// Writes each file under its own name in the temporary directory, so the share sheet carries
    /// names a person can read. A same-named file from an earlier share is replaced.
    static func temporaryFiles(_ files: [(data: Data, name: String)]) throws -> ShareItem {
        let urls = try files.map { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try file.data.write(to: url, options: .atomic)
            return url
        }
        return ShareItem(urls: urls)
    }

    /// The alert line when the files couldn't be written.
    static func preparationFailure(_ error: Error) -> String {
        "Couldn't prepare the file to share: \(error.localizedDescription)"
    }
}

extension View {
    /// The share sheet and the outcome alert behind every Save to Photos and Share pair. One
    /// optional message carries both outcomes, so a save and a failed share read the same way.
    func photoExportPresentation(share: Binding<ShareItem?>, message: Binding<String?>,
                                 title: String = "Save to Photos") -> some View {
        sheet(item: share) { ShareSheet(items: $0.urls) }
            .alert(title, isPresented: Binding(isPresent: message)) {
                Button("OK", role: .cancel) { message.wrappedValue = nil }
            } message: { Text(message.wrappedValue ?? "") }
    }
}

/// Saves developed JPEGs to the user's photo library **preserving their embedded metadata** (EXIF:
/// camera, lens, exposure, capture date, etc.). Requires `NSPhotoLibraryAddUsageDescription`.
///
/// It saves the original file **bytes** via `PHAssetCreationRequest.addResource(with:.photo,data:)`,
/// which writes them verbatim; `UIImageWriteToSavedPhotosAlbum` on a decoded `UIImage` would
/// re-encode the pixels and drop all EXIF.
struct ImageSaver {
    /// Save JPEG (or other image-file) bytes to the photo library, keeping embedded EXIF intact.
    /// Requests add-only access if needed; `completion` is always called on the main queue.
    func save(data: Data, completion: @escaping (Error?) -> Void) {
        func finish(_ error: Error?) { DispatchQueue.main.async { completion(error) } }

        func write() {
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: PHAssetResourceCreationOptions())
            } completionHandler: { success, error in
                finish(success ? nil : (error ?? Self.genericError))
            }
        }

        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            write()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited { write() }
                else { finish(Self.deniedError) }
            }
        default:
            finish(Self.deniedError)
        }
    }

    /// The alert line for a save's outcome.
    static func message(for error: Error?) -> String {
        error.map { "Couldn't save: \($0.localizedDescription)" } ?? "Saved to your photo library."
    }

    private static let genericError = NSError(domain: "FujiCookbook.ImageSaver", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "The photo couldn't be saved."])
    private static let deniedError = NSError(domain: "FujiCookbook.ImageSaver", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Photo library access is off. Enable it for Darkslide in Settings, then try again."])
}

/// `UIActivityViewController` for SwiftUI, for shares whose outcome nothing records: recipes,
/// backups and exported photos. Reports use `ReportShareSheet`, which reports the outcome.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Wraps `UIDocumentPickerViewController` for importing recipe files from within the app.
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.fujiRecipe, .json])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

/// Pinch-to-zoom / pan container for a single image, backed by `UIScrollView`.
///
/// SwiftUI's `MagnificationGesture` can be wired up by hand, but it doesn't give you rubber-banding,
/// momentum panning, or zoom-around-the-pinch-midpoint — all of which people expect from a photo
/// viewer. `UIScrollView` gives all of that for free.
///
/// The one subtlety is living inside a paged `TabView`: with `bounces = false` the scroll view
/// refuses the pan when it has nothing to scroll (i.e. at fit scale), so horizontal swipes fall
/// through to the pager and photo-to-photo paging keeps working. Once zoomed in, the scroll view
/// consumes the pan and you drag around the image instead.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    /// Upper zoom limit, as a multiple of the fit-to-screen scale.
    var maxZoom: CGFloat = 4

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ZoomScrollView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true

        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.zoomCoordinator = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        // See the type doc: no bouncing at fit scale means the pager still gets horizontal swipes.
        scrollView.bounces = false
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.maxZoom = maxZoom
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            context.coordinator.invalidateLayout()
        }
        scrollView.setNeedsLayout()
    }

    /// `UIScrollView` subclass that re-fits its image whenever UIKit lays it out. `updateUIView`
    /// alone isn't enough: SwiftUI can call it while the view still has zero bounds and then never
    /// call it again, which would leave the image sized 0×0 and invisible.
    final class ZoomScrollView: UIScrollView {
        weak var zoomCoordinator: Coordinator?

        override func layoutSubviews() {
            super.layoutSubviews()
            zoomCoordinator?.layout(self)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var maxZoom: CGFloat = 4
        /// Bounds *size* the last layout was computed for, so rotation re-fits the image. Size, not
        /// the full rect: `bounds.origin` moves on every scroll, and re-fitting mid-pan would snap
        /// the zoom back to fit.
        private var laidOutSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        /// Force the next `layout` to recompute even if the bounds are unchanged (e.g. the image itself changed).
        func invalidateLayout() { laidOutSize = .zero }

        /// Fit the image to the scroll view and re-center it. Called from `layoutSubviews`, so it
        /// must stay cheap — it no-ops unless the bounds size actually changed.
        ///
        /// The image view is kept at the image's **natural** size and "fit to screen" is expressed as
        /// `minimumZoomScale` rather than by resizing the image view. That's what keeps the frame and
        /// the zoom scale in sync: `UIScrollView` resizes its zoom view relative to the current
        /// `zoomScale`, so setting the frame ourselves while zoomed in would desync the two and
        /// collapse the image to a fraction of its size on the next zoom change.
        func layout(_ scrollView: UIScrollView) {
            guard let imageView, let image = imageView.image else { return }
            let bounds = scrollView.bounds.size
            guard bounds.width > 0, bounds.height > 0,
                  image.size.width > 0, image.size.height > 0,
                  bounds != laidOutSize else { return }
            laidOutSize = bounds

            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size

            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            scrollView.minimumZoomScale = fit
            scrollView.maximumZoomScale = fit * maxZoom
            scrollView.zoomScale = fit
            centerImage(in: scrollView)
        }

        /// Keep the image centered when it's smaller than the scroll view (i.e. at or near fit scale).
        private func centerImage(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let extraX = max(0, (scrollView.bounds.width - imageView.frame.width) / 2)
            let extraY = max(0, (scrollView.bounds.height - imageView.frame.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: extraY, left: extraX,
                                                   bottom: extraY, right: extraX)
        }

        /// Double tap toggles between fit and a 2.5× close-up centred on the tapped point.
        ///
        /// Both bounds are relative to `minimumZoomScale` (which *is* fit — see `layout`), so the
        /// comparison needs the epsilon: after a pinch that rubber-bands back, `zoomScale` settles a
        /// hair above the minimum and an exact `>` would read as "still zoomed in".
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView, let imageView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let target = min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 2.5)
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / target,
                                  height: scrollView.bounds.height / target)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2,
                                           y: point.y - size.height / 2,
                                           width: size.width,
                                           height: size.height),
                                animated: true)
            }
        }
    }
}

/// A general content picker for arbitrary UTI types (e.g. RAF files for the Kitchen flow). Unlike
/// `DocumentPicker` it doesn't hardcode the recipe types, and it copies picked items into the app so
/// the security-scoped originals don't have to stay accessible while we read them.
struct ContentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    var allowsMultiple = true
    var onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
