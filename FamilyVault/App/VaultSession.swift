import CloudKit
import Combine
import CryptoKit
import Foundation
import SwiftUI

enum SessionPhase: Equatable {
    case launching
    /// Nothing exists yet anywhere — this phone gets to create the vault.
    case setup
    case locked
    case unlocked
    /// Two phones are already registered and this isn't one of them.
    case deviceLimitReached([VaultDevice])
    /// No vault on this device and iCloud can't be reached to look for one.
    case unavailable(String)
}

/// Owns the lock state and everything that has to happen around it: finding
/// the vault, deriving keys off the main thread, opening the store, holding
/// the two-device rule, and re-locking when the app goes away.
@MainActor
final class VaultSession: ObservableObject {

    @Published private(set) var phase: SessionPhase = .launching
    /// True while a slow key derivation is running, so the visible screen can
    /// show a spinner without being swapped out from under the user.
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var isPrivacyShieldUp = false
    /// Set when the vault erased itself here after too many wrong tries.
    @Published var didWipeAfterFailures = false

    let settings: AppSettings
    let store: VaultStore

    private let keyManager: VaultKeyManager
    private let cloud: CloudKitService
    private let reminders = ReminderScheduler.shared

    private var backgroundedAt: Date?
    private var dataKey: SymmetricKey?

    init(containerIdentifier: String) {
        let keyManager = VaultKeyManager()
        let cloud = CloudKitService(containerIdentifier: containerIdentifier)
        self.keyManager = keyManager
        self.cloud = cloud
        self.settings = AppSettings()
        self.store = VaultStore(cloud: cloud, keyManager: keyManager)
    }

    var biometryName: String { Keychain.biometryDescription }
    var canUseBiometrics: Bool { settings.biometricsEnabled && keyManager.hasBiometricKey }
    var isOwnerDevice: Bool { store.isOwner }

    // MARK: - Launch

    func bootstrap() async {
        if keyManager.cachedMaterial() != nil {
            phase = .locked
            return
        }

        // Nothing local. Perhaps the other phone already made the vault and
        // shared it with us — look in iCloud before offering to create one.
        do {
            let scope = try await cloud.resolveScope()
            if let record = try await cloud.fetchRecord(named: CloudKitService.metaRecordName, scope: scope) {
                let material = try CloudRecordMapper.material(from: record)
                keyManager.cache(material)
                phase = .locked
            } else {
                phase = .setup
            }
        } catch {
            phase = .setup
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Creating

    func createVault(passphrase: String, deviceName: String) async {
        isWorking = true
        defer { isWorking = false }
        let manager = keyManager
        do {
            let created = try await derive { try manager.createMaterial(passphrase: passphrase) }
            keyManager.cache(created.material)
            try store.open(dataKey: created.dataKey, material: created.material)
            store.updateKeyMaterial(created.material)
            dataKey = created.dataKey

            await finishUnlock(dataKey: created.dataKey, passphrase: passphrase, deviceName: deviceName)
            settings.hasCompletedSetup = true
        } catch {
            phase = .setup
            errorMessage = message(for: error)
        }
    }

    // MARK: - Unlocking

    func unlock(passphrase: String, deviceName: String? = nil) async {
        guard let material = keyManager.cachedMaterial() else {
            phase = .setup
            return
        }
        isWorking = true
        defer { isWorking = false }
        let manager = keyManager
        do {
            let key = try await derive { try manager.unwrap(material: material, passphrase: passphrase) }
            try store.open(dataKey: key, material: material)
            dataKey = key
            await finishUnlock(dataKey: key, passphrase: passphrase, deviceName: deviceName)
        } catch {
            registerFailedAttempt(error, isWrongPassphrase: true)
        }
    }

    /// A wrong passphrase — or a failed biometric check — is usually just a
    /// typo or a bad face/finger read, so the count only matters once the
    /// user has deliberately asked for a limit. `isWrongPassphrase` tells us
    /// whether `error` came from the passphrase path (where only
    /// `VaultKeyManager.Failure.wrongPassphrase` should count) or the
    /// biometric path (where any non-cancellation `Keychain.Failure` counts).
    private func registerFailedAttempt(_ error: Error, isWrongPassphrase: Bool) {
        let countsTowardLimit: Bool
        if isWrongPassphrase {
            if case VaultKeyManager.Failure.wrongPassphrase = error {
                countsTowardLimit = true
            } else {
                countsTowardLimit = false
            }
        } else {
            // Keychain.swift folds a genuine "wrong face/finger" rejection
            // and a deliberate user cancellation into the same
            // `.userCancelled` case, so that specific case is intentionally
            // excluded here — we'd rather under-count than wipe a device
            // because someone backed out of a Face ID prompt. Any other
            // `Keychain.Failure` (auth temporarily unavailable, lockout,
            // etc.) is a real failed attempt.
            switch error {
            case Keychain.Failure.userCancelled:
                countsTowardLimit = false
            case is Keychain.Failure:
                countsTowardLimit = true
            default:
                countsTowardLimit = false
            }
        }

        guard countsTowardLimit else {
            phase = .locked
            if isWrongPassphrase { errorMessage = message(for: error) }
            return
        }

        settings.failedAttempts += 1
        let limit = settings.wipeAfterFailedAttempts

        if limit > 0, settings.failedAttempts >= limit {
            removeVaultFromThisDevice()
            didWipeAfterFailures = true
            return
        }

        phase = .locked
        if limit > 0 {
            let left = limit - settings.failedAttempts
            let reason = isWrongPassphrase ? "That passphrase doesn't unlock this vault." : "That didn't match."
            errorMessage = "\(reason) \(left) tr\(left == 1 ? "y" : "ies") left before this iPhone erases its copy."
        } else {
            errorMessage = message(for: error)
        }
    }

    func unlockWithBiometrics() async {
        guard let material = keyManager.cachedMaterial(), canUseBiometrics else { return }
        isWorking = true
        defer { isWorking = false }
        let manager = keyManager
        do {
            // The keychain read blocks until Face ID resolves — keep it off main.
            let key = try await derive { try manager.biometricUnlock(prompt: "Unlock your vault") }
            try store.open(dataKey: key, material: material)
            dataKey = key
            await finishUnlock(dataKey: key, passphrase: nil, deviceName: nil)
        } catch {
            registerFailedAttempt(error, isWrongPassphrase: false)
        }
    }

    private func finishUnlock(dataKey: SymmetricKey, passphrase: String?, deviceName: String?) async {
        // Reached only once the passphrase (or biometric read) has actually
        // decrypted the vault key, so any run of prior failures is over.
        settings.failedAttempts = 0

        if settings.biometricsEnabled, passphrase != nil, !keyManager.hasBiometricKey {
            try? keyManager.enableBiometricUnlock(dataKey: dataKey)
        }

        phase = .unlocked

        let admission = await store.registerCurrentDevice(named: deviceName)
        switch admission {
        case .blocked(let registered):
            store.close()
            self.dataKey = nil
            phase = .deviceLimitReached(registered)
        case .admitted, .unknown:
            if settings.remindersEnabled {
                await reminders.requestAuthorization()
                await reminders.rescheduleAsync(for: store.items)
            }
        }
    }

    func lock() {
        store.close()
        dataKey = nil
        backgroundedAt = nil
        if keyManager.cachedMaterial() != nil {
            phase = .locked
        } else {
            phase = .setup
        }
    }

    // MARK: - Passphrase

    func changePassphrase(current: String, new: String) async throws {
        guard let material = keyManager.cachedMaterial() else { throw VaultKeyManager.Failure.noKeyMaterial }
        let manager = keyManager
        let key = try await derive { try manager.unwrap(material: material, passphrase: current) }
        let updated = try await derive { try manager.rewrap(material: material, dataKey: key, newPassphrase: new) }
        store.updateKeyMaterial(updated)
        if keyManager.hasBiometricKey {
            keyManager.disableBiometricUnlock()
            if settings.biometricsEnabled {
                try? keyManager.enableBiometricUnlock(dataKey: key)
            }
        }
    }

    func setBiometricsEnabled(_ enabled: Bool) {
        settings.biometricsEnabled = enabled
        if enabled {
            if let dataKey { try? keyManager.enableBiometricUnlock(dataKey: dataKey) }
        } else {
            keyManager.disableBiometricUnlock()
        }
    }

    // MARK: - Removing this device

    func removeVaultFromThisDevice() {
        store.wipeThisDevice()
        dataKey = nil
        settings.hasCompletedSetup = false
        settings.failedAttempts = 0
        phase = .setup
    }

    // MARK: - Scene lifecycle

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            isPrivacyShieldUp = false
            if case .unlocked = phase, let backgroundedAt {
                let elapsed = Date().timeIntervalSince(backgroundedAt)
                if elapsed >= Double(settings.autoLockSeconds) { lock() } else { store.scheduleSync() }
            } else if case .unlocked = phase {
                store.scheduleSync()
            }
            backgroundedAt = nil

        case .inactive:
            // The app switcher snapshot is taken here — hide the contents.
            if case .unlocked = phase { isPrivacyShieldUp = true }

        case .background:
            backgroundedAt = Date()
            if settings.autoLockSeconds == 0, case .unlocked = phase { lock() }

        @unknown default:
            break
        }
    }

    /// The signed-in iCloud account changed (signed out, switched, or Family
    /// Sharing altered). Whether we are owner or participant may now be wrong.
    func handleAccountChange() {
        Task {
            await cloud.invalidateScope()
            if case .unlocked = phase {
                await store.sync()
            } else {
                await bootstrap()
            }
        }
    }

    func handleRemoteChangeNotification() {
        guard case .unlocked = phase else { return }
        store.scheduleSync()
    }

    func handleAcceptedShare(_ metadata: CKShare.Metadata) async {
        do {
            try await cloud.accept(metadata)
            await bootstrap()
            if case .unlocked = phase { await store.sync() }
        } catch {
            errorMessage = "Could not join the shared vault: \(message(for: error))"
        }
    }

    // MARK: - Sharing

    func makeShare(title: String) async throws -> (CKShare, CKContainer) {
        let scope = try await cloud.resolveScope()
        let share = try await cloud.fetchOrCreateShare(scope: scope, title: title)
        return (share, cloud.container)
    }

    func currentShare() async -> CKShare? {
        guard let scope = try? await cloud.resolveScope() else { return nil }
        return await cloud.currentShare(scope: scope)
    }

    func revokeSharing() async throws {
        let scope = try await cloud.resolveScope()
        guard let share = await cloud.currentShare(scope: scope) else { return }
        try await cloud.removeParticipants(from: share, scope: scope)
    }

    // MARK: - Helpers

    /// Key derivation is intentionally slow; keep it off the main thread.
    private func derive<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
