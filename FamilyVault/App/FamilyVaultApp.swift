import CloudKit
import SwiftUI

enum AppConfiguration {

    /// The iCloud container, worked out from the app's own bundle identifier.
    ///
    /// Set the bundle identifier in Signing & Capabilities, add a CloudKit
    /// container named `iCloud.` + that identifier, and this matches it
    /// automatically. Hard-coding the string here was one edit too many: get it
    /// a character wrong and the app builds, runs, and silently never syncs.
    static let cloudContainerIdentifier: String = {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return "iCloud.com.example.familyvault"
        }
        return "iCloud.\(bundleID)"
    }()

    static let vaultShareTitle = "Our Family Vault"
}

@main
struct FamilyVaultApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = VaultSession(containerIdentifier: AppConfiguration.cloudContainerIdentifier)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(session.store)
                .environmentObject(session.settings)
                .environmentObject(ReminderScheduler.shared)
                .tint(Theme.accent)
                .preferredColorScheme(nil)
                .task { await session.bootstrap() }
                .onChange(of: scenePhase) { _, newPhase in
                    session.handleScenePhase(newPhase)
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaultRemoteChange)) { _ in
                    session.handleRemoteChangeNotification()
                }
                .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                    session.handleAccountChange()
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaultShareAccepted)) { note in
                    guard let metadata = note.object as? CKShareMetadataBox else { return }
                    Task { await session.handleAcceptedShare(metadata.metadata) }
                }
        }
    }
}
