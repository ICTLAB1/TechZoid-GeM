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

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
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

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
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
            onCancel()
        }
    }
}
