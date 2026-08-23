import CloudKit
import SwiftUI

/// Change this to the iCloud container you create in Signing & Capabilities.
/// It must match the entry in FamilyVault.entitlements.
enum AppConfiguration {
    static let cloudContainerIdentifier = "iCloud.com.example.familyvault"
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
