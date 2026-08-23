import CloudKit
import UIKit

extension Notification.Name {
    static let vaultRemoteChange = Notification.Name("vault.remoteChange")
    static let vaultShareAccepted = Notification.Name("vault.shareAccepted")
}

/// `CKShare.Metadata` travels through NotificationCenter, which wants an object.
final class CKShareMetadataBox: NSObject {
    let metadata: CKShare.Metadata
    init(_ metadata: CKShare.Metadata) { self.metadata = metadata }
}

/// SwiftUI has no hook for either of the two things CloudKit needs from the
/// app delegate: silent push, and accepting a share invitation.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        NotificationCenter.default.post(name: .vaultRemoteChange, object: nil)
        completionHandler(.newData)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Push is a nicety: without it the app still syncs on launch and on
        // every foreground, so there is nothing to recover from here.
    }
}
