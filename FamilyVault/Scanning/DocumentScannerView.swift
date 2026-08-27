import SwiftUI
import UIKit
import VisionKit

/// Apple's own document camera: edge detection, perspective correction,
/// multi-page. Writing this by hand with AVFoundation would be worse in every
/// way that matters — including the deskewing that makes OCR work at all.
struct DocumentScannerView: UIViewControllerRepresentable {

    /// Called with the captured pages, in order.
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void = {}
    /// Called when the scanner itself fails (not a user cancel). `onCancel`
    /// still runs right after, so existing callers keep dismissing exactly as
    /// before — this is purely additive for a caller that wants to tell the
    /// two apart and show an error instead of silently closing.
    var onFailure: (Error) -> Void = { _ in }

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([UIImage]) -> Void
        private let onCancel: () -> Void
        private let onFailure: (Error) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void, onFailure: @escaping (Error) -> Void = { _ in }) {
            self.onFinish = onFinish
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // A scan with zero pages (the user opened the scanner and backed
            // out without capturing anything reachable only via this path,
            // rather than the explicit cancel button) should behave like a
            // cancel, not hand callers an empty document to build a PDF from.
            guard scan.pageCount > 0 else {
                onCancel()
                return
            }
            var pages: [UIImage] = []
            for index in 0 ..< scan.pageCount {
                pages.append(scan.imageOfPage(at: index))
            }
            // SwiftUI owns the presentation here, so the callbacks lower the
            // flag and SwiftUI dismisses. Calling `controller.dismiss` as well
            // would be a second, competing dismissal.
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFailure(error)
            onCancel()
        }
    }
}
