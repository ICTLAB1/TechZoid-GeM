import CloudKit
import SwiftUI
import UIKit

/// Apple's own share sheet for CloudKit invitations. Using it means the
/// invitation is tied to your wife's Apple Account rather than to a link
/// anyone could forward.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var title: String
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let title: String
        private let onDismiss: () -> Void

        init(title: String, onDismiss: @escaping () -> Void) {
            self.title = title
            self.onDismiss = onDismiss
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onDismiss()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onDismiss()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onDismiss()
        }
    }
}
