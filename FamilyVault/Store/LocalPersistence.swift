import CryptoKit
import Foundation

/// The on-disk shape of the vault. The whole thing is sealed with the data key
/// before it is written, so the file is meaningless without the passphrase —
/// even to someone with a full filesystem dump of the phone.
struct VaultFile: Codable {
    var schemaVersion: Int
    var items: [VaultItem]
    var devices: [VaultDevice]
    var recordSystemFields: [String: Data]
    var pendingItemIDs: [String]
    var pendingDeviceIDs: [String]
    /// Attachments whose bytes still have to go up to iCloud.
    var pendingAttachmentIDs: [String]
    /// Attachment records to delete from iCloud on the next sync.
    var attachmentIDsToDelete: [String]
    var metaNeedsPush: Bool
    var savedAt: Date
    /// Local-only history of the summary tiles, one per calendar month —
    /// derived data, never synced to CloudKit.
    var netWorthSnapshots: [NetWorthSnapshot]

    static let currentSchemaVersion = 1

    static var empty: VaultFile {
        VaultFile(
            schemaVersion: currentSchemaVersion,
            items: [],
            devices: [],
            recordSystemFields: [:],
            pendingItemIDs: [],
            pendingDeviceIDs: [],
            pendingAttachmentIDs: [],
            attachmentIDsToDelete: [],
            metaNeedsPush: false,
            savedAt: Date(),
            netWorthSnapshots: []
        )
    }
}

/// Declared in an extension so the memberwise initialiser survives: a file
/// written by an older build decodes with the newer fields defaulted rather
/// than failing outright and losing the vault.
extension VaultFile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? VaultFile.currentSchemaVersion
        items = (try? container.decode([VaultItem].self, forKey: .items)) ?? []
        devices = (try? container.decode([VaultDevice].self, forKey: .devices)) ?? []
        recordSystemFields = (try? container.decode([String: Data].self, forKey: .recordSystemFields)) ?? [:]
        pendingItemIDs = (try? container.decode([String].self, forKey: .pendingItemIDs)) ?? []
        pendingDeviceIDs = (try? container.decode([String].self, forKey: .pendingDeviceIDs)) ?? []
        pendingAttachmentIDs = (try? container.decode([String].self, forKey: .pendingAttachmentIDs)) ?? []
        attachmentIDsToDelete = (try? container.decode([String].self, forKey: .attachmentIDsToDelete)) ?? []
        metaNeedsPush = (try? container.decode(Bool.self, forKey: .metaNeedsPush)) ?? false
        savedAt = (try? container.decode(Date.self, forKey: .savedAt)) ?? Date()
        netWorthSnapshots = (try? container.decode([NetWorthSnapshot].self, forKey: .netWorthSnapshots)) ?? []
    }
}

enum LocalPersistence {

    static func load(key: SymmetricKey) throws -> VaultFile {
        guard FileManager.default.fileExists(atPath: AppPaths.vaultFile.path) else { return .empty }
        let sealed = try Data(contentsOf: AppPaths.vaultFile)
        guard !sealed.isEmpty else { return .empty }
        let json = try CryptoBox.open(sealed, key: key)
        return try JSONDecoder.vault.decode(VaultFile.self, from: json)
    }

    static func save(_ file: VaultFile, key: SymmetricKey) throws {
        var file = file
        file.savedAt = Date()
        let json = try JSONEncoder.vault.encode(file)
        let sealed = try CryptoBox.seal(json, key: key)
        try sealed.write(to: AppPaths.vaultFile, options: [.atomic, .completeFileProtection])
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: AppPaths.vaultFile)
        AttachmentStore.removeAll()
    }
}
