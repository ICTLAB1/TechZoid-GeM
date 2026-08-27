import CryptoKit
import Foundation

/// The key material that travels with the vault.
///
/// It is safe for this to sit in iCloud: `wrappedKey` is the real data key
/// sealed under a key derived from the master passphrase, which is never
/// stored, transmitted, or recoverable by Apple, by us, or by anyone holding
/// the iCloud account. Both phones unwrap the *same* data key from the *same*
/// passphrase, which is what lets two people read one vault.
struct VaultKeyMaterial: Codable, Equatable {
    var version: Int
    var vaultID: String
    var salt: Data
    var iterations: Int
    var wrappedKey: Data
    var createdAt: Date

    init(version: Int = 1, vaultID: String, salt: Data, iterations: Int, wrappedKey: Data, createdAt: Date) {
        self.version = version
        self.vaultID = vaultID
        self.salt = salt
        self.iterations = iterations
        self.wrappedKey = wrappedKey
        self.createdAt = createdAt
    }
}

enum AppPaths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FamilyVault", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.complete])
        }
        return dir
    }

    static var keyMaterialFile: URL { appSupport.appendingPathComponent("key-material.json") }
    static var vaultFile: URL { appSupport.appendingPathComponent("vault.enc") }
    static var syncTokensFile: URL { appSupport.appendingPathComponent("sync-tokens.dat") }
}

/// The freshly minted keys for a brand new vault.
struct NewVaultKeys: Sendable {
    let material: VaultKeyMaterial
    let dataKey: SymmetricKey
}

/// Creates, unwraps, caches and rotates the vault key material.
/// Stateless — every method reads from disk or the keychain — so it is safe to
/// call from any thread, which matters because key derivation runs off-main.
final class VaultKeyManager: @unchecked Sendable {

    static let dataKeyAccount = "vault-data-key"
    static let deviceIDAccount = "vault-device-id"

    enum Failure: LocalizedError {
        case wrongPassphrase
        case noKeyMaterial
        case corruptedKeyMaterial

        var errorDescription: String? {
            switch self {
            case .wrongPassphrase: "That passphrase doesn't unlock this vault."
            case .noKeyMaterial: "This vault hasn't been set up on this device yet."
            case .corruptedKeyMaterial: "This vault's key material is damaged and can't be read, independent of the passphrase."
            }
        }
    }

    // MARK: - Local cache of the key material

    func cachedMaterial() -> VaultKeyMaterial? {
        guard let data = try? Data(contentsOf: AppPaths.keyMaterialFile) else { return nil }
        return try? JSONDecoder.vault.decode(VaultKeyMaterial.self, from: data)
    }

    func cache(_ material: VaultKeyMaterial) {
        guard let data = try? JSONEncoder.vault.encode(material) else { return }
        try? data.write(to: AppPaths.keyMaterialFile, options: [.atomic, .completeFileProtection])
    }

    func clearCachedMaterial() {
        try? FileManager.default.removeItem(at: AppPaths.keyMaterialFile)
    }

    // MARK: - Creating and opening

    /// Brand new vault: random data key, wrapped under the chosen passphrase.
    func createMaterial(passphrase: String) throws -> NewVaultKeys {
        let dataKey = CryptoBox.randomKey()
        let salt = CryptoBox.randomBytes(KeyDerivation.saltLength)
        let iterations = KeyDerivation.defaultIterations
        let wrappingKey = try KeyDerivation.deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        var rawDataKey = dataKey.rawData
        defer { rawDataKey.secureZeroOut() }
        let wrapped = try CryptoBox.seal(rawDataKey, key: wrappingKey)

        let material = VaultKeyMaterial(
            vaultID: UUID().uuidString,
            salt: salt,
            iterations: iterations,
            wrappedKey: wrapped,
            createdAt: Date()
        )
        return NewVaultKeys(material: material, dataKey: dataKey)
    }

    func unwrap(material: VaultKeyMaterial, passphrase: String) throws -> SymmetricKey {
        let wrappingKey = try KeyDerivation.deriveKey(
            passphrase: passphrase, salt: material.salt, iterations: material.iterations
        )
        do {
            var raw = try CryptoBox.open(material.wrappedKey, key: wrappingKey)
            defer { raw.secureZeroOut() }
            return SymmetricKey(data: raw)
        } catch CryptoBox.Failure.malformedCiphertext {
            // The wrapped key blob itself is structurally invalid — this is
            // data corruption, not a wrong guess, and no passphrase will fix
            // it. Keep this distinguishable from `.wrongPassphrase` so the UI
            // doesn't tell the user to just retype their passphrase.
            throw Failure.corruptedKeyMaterial
        } catch {
            // Any other failure (GCM authentication failure) means the key
            // we derived doesn't open this blob — almost always a wrong
            // passphrase.
            throw Failure.wrongPassphrase
        }
    }

    /// Re-wraps the *same* data key under a new passphrase, so existing items
    /// stay readable and the other phone only needs the new passphrase.
    func rewrap(material: VaultKeyMaterial, dataKey: SymmetricKey, newPassphrase: String) throws -> VaultKeyMaterial {
        let salt = CryptoBox.randomBytes(KeyDerivation.saltLength)
        let iterations = KeyDerivation.defaultIterations
        let wrappingKey = try KeyDerivation.deriveKey(passphrase: newPassphrase, salt: salt, iterations: iterations)
        var rawDataKey = dataKey.rawData
        defer { rawDataKey.secureZeroOut() }
        var updated = material
        updated.salt = salt
        updated.iterations = iterations
        updated.wrappedKey = try CryptoBox.seal(rawDataKey, key: wrappingKey)
        return updated
    }

    // MARK: - Biometric convenience unlock

    var hasBiometricKey: Bool { Keychain.exists(account: Self.dataKeyAccount) }

    func enableBiometricUnlock(dataKey: SymmetricKey) throws {
        var raw = dataKey.rawData
        defer { raw.secureZeroOut() }
        try Keychain.storeBiometryProtected(raw, account: Self.dataKeyAccount)
    }

    func disableBiometricUnlock() {
        try? Keychain.delete(account: Self.dataKeyAccount)
    }

    func biometricUnlock(prompt: String) throws -> SymmetricKey {
        var raw = try Keychain.readBiometryProtected(account: Self.dataKeyAccount, prompt: prompt)
        defer { raw.secureZeroOut() }
        return SymmetricKey(data: raw)
    }

    // MARK: - Stable per-device identity (used for the two-device limit)

    var deviceID: String {
        if let data = Keychain.read(account: Self.deviceIDAccount), let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString
        try? Keychain.store(Data(id.utf8), account: Self.deviceIDAccount)
        return id
    }

    /// Wipes every trace of the vault from this device.
    func resetDevice() {
        disableBiometricUnlock()
        clearCachedMaterial()
        try? FileManager.default.removeItem(at: AppPaths.vaultFile)
        try? FileManager.default.removeItem(at: AppPaths.syncTokensFile)
    }
}

extension JSONEncoder {
    static var vault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var vault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
