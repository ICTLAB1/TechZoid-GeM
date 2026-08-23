import CloudKit
import UIKit

/// SwiftUI's app lifecycle is scene-based, and iOS delivers CloudKit share
/// invitations to the *scene* delegate — the app-delegate callback is never
/// called for a scene-based app. Installing this class as the scene delegate
/// (see `AppDelegate.application(_:configurationForConnecting:options:)`) is
/// what makes tapping the invitation on the second iPhone actually work.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Cold launch straight from the invitation link.
        if let metadata = connectionOptions.cloudKitShareMetadata {
            post(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        post(cloudKitShareMetadata)
    }

    private func post(_ metadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: .vaultShareAccepted, object: CKShareMetadataBox(metadata))
    }
}
