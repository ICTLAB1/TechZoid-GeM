import CryptoKit
import Foundation

/// A portable, password-protected copy of the vault — entries *and* the
/// documents attached to them.
///
/// Deliberately independent of iCloud: if the iCloud account is ever lost, or
/// you want a copy in a safe deposit box, this is the escape hatch. The file is
/// useless without its own password.
struct VaultBackup: Codable {
    var format: String
    var version: Int
    var createdAt: Date
    var itemCount: Int
    var attachmentCount: Int
    var salt: Data
    var iterations: Int
    var ciphertext: Data

    static let formatIdentifier = "family-vault-backup"
    static let currentVersion = 2
}

/// What actually sits inside the sealed blob.
struct BackupPayload: Codable {
    var items: [VaultItem]
    /// Attachment id (as a string) to its plaintext bytes. Sealed along with
    /// everything else, so the file as a whole is still one encrypted unit.
    var attachments: [String: Data]

    init(items: [VaultItem], attachments: [String: Data] = [:]) {
        self.items = items
        self.attachments = attachments
    }
}

enum BackupService {

    enum Failure: LocalizedError {
        case unrecognisedFile
        case wrongPassword

        var errorDescription: String? {
            switch self {
            case .unrecognisedFile: "That file isn't a Vault backup."
            case .wrongPassword: "That password doesn't open this backup."
            }
        }
    }

    static func makeBackup(payload: BackupPayload, password: String) throws -> VaultBackup {
        let salt = CryptoBox.randomBytes(KeyDerivation.saltLength)
        let iterations = KeyDerivation.defaultIterations
        let key = try KeyDerivation.deriveKey(passphrase: password, salt: salt, iterations: iterations)
        let json = try JSONEncoder.vault.encode(payload)

        return VaultBackup(
            format: VaultBackup.formatIdentifier,
            version: VaultBackup.currentVersion,
            createdAt: Date(),
            itemCount: payload.items.count,
            attachmentCount: payload.attachments.count,
            salt: salt,
            iterations: iterations,
            ciphertext: try CryptoBox.seal(json, key: key)
        )
    }

    static func write(_ backup: VaultBackup) throws -> URL {
        let name = "Vault-\(Self.fileStamp(backup.createdAt)).vaultbackup"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let data = try JSONEncoder.vault.encode(backup)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func restore(from url: URL, password: String) throws -> BackupPayload {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer { if needsScopedAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard let backup = try? JSONDecoder.vault.decode(VaultBackup.self, from: data),
              backup.format == VaultBackup.formatIdentifier
        else { throw Failure.unrecognisedFile }

        let key = try KeyDerivation.deriveKey(passphrase: password, salt: backup.salt, iterations: backup.iterations)
        let json: Data
        do {
            json = try CryptoBox.open(backup.ciphertext, key: key)
        } catch {
            throw Failure.wrongPassword
        }

        if let payload = try? JSONDecoder.vault.decode(BackupPayload.self, from: json) {
            return payload
        }
        // Version 1 files held a bare array of items.
        let items = try JSONDecoder.vault.decode([VaultItem].self, from: json)
        return BackupPayload(items: items)
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }
}
