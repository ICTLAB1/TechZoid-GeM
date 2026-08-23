import SwiftUI
import UIKit

/// A plain "take a photo" camera, separate from the document scanner.
///
/// The scanner is the right tool for paperwork — it finds the edges, flattens
/// the perspective and produces a PDF. It is the wrong tool for a photograph:
/// the locker key, the dented bumper for a motor claim, the boundary of a plot.
/// Those want to stay pictures.
struct CameraCaptureView: UIViewControllerRepresentable {

    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void = {}

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true      // lets you crop before it is stored
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // SwiftUI owns the presentation, so the callback lowers the flag
            // and SwiftUI dismisses — no competing dismissal from here.
            guard let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) else {
                onCancel()
                return
            }
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
