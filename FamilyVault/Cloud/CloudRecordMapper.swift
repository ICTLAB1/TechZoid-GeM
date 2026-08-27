import CloudKit
import CryptoKit
import Foundation

/// Converts vault objects to and from CloudKit records.
///
/// Exactly one field ever leaves the device with meaning in it — `payload` —
/// and that field is AES-GCM ciphertext. `updatedAt` is stored in the clear
/// only so conflicts can be resolved without decrypting.
enum CloudRecordMapper {

    enum Field {
        static let payload = "payload"
        static let updatedAt = "updatedAt"
        static let schemaVersion = "schemaVersion"
        static let deviceID = "deviceID"
        static let salt = "salt"
        static let iterations = "iterations"
        static let wrappedKey = "wrappedKey"
        static let vaultID = "vaultID"
        static let asset = "asset"
        static let itemID = "itemID"
    }

    static let schemaVersion = 1

    // MARK: - Items

    static func record(for item: VaultItem, key: SymmetricKey, zoneID: CKRecordZone.ID, existingSystemFields: Data?) throws -> CKRecord {
        let record = makeRecord(
            type: CloudRecordType.item,
            name: item.id.uuidString,
            zoneID: zoneID,
            systemFields: existingSystemFields
        )
        let json = try JSONEncoder.vault.encode(item)
        record[Field.payload] = try CryptoBox.seal(json, key: key) as CKRecordValue
        record[Field.updatedAt] = item.updatedAt as CKRecordValue
        record[Field.schemaVersion] = schemaVersion as CKRecordValue
        return record
    }

    static func item(from record: CKRecord, key: SymmetricKey) throws -> VaultItem {
        guard let payload = record[Field.payload] as? Data else {
            throw MappingError.missingPayload
        }
        let json = try CryptoBox.open(payload, key: key)
        return try JSONDecoder.vault.decode(VaultItem.self, from: json)
    }

    // MARK: - Key material

    static func metaRecord(for material: VaultKeyMaterial, zoneID: CKRecordZone.ID, existingSystemFields: Data?) -> CKRecord {
        let record = makeRecord(
            type: CloudRecordType.meta,
            name: CloudKitService.metaRecordName,
            zoneID: zoneID,
            systemFields: existingSystemFields
        )
        record[Field.vaultID] = material.vaultID as CKRecordValue
        record[Field.salt] = material.salt as CKRecordValue
        record[Field.iterations] = material.iterations as CKRecordValue
        record[Field.wrappedKey] = material.wrappedKey as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        return record
    }

    static func material(from record: CKRecord) throws -> VaultKeyMaterial {
        guard let vaultID = record[Field.vaultID] as? String,
              let salt = record[Field.salt] as? Data,
              let iterations = record[Field.iterations] as? Int,
              let wrapped = record[Field.wrappedKey] as? Data
        else { throw MappingError.missingPayload }

        return VaultKeyMaterial(
            vaultID: vaultID,
            salt: salt,
            iterations: iterations,
            wrappedKey: wrapped,
            createdAt: record.creationDate ?? Date()
        )
    }

    // MARK: - Devices

    static func deviceRecord(for device: VaultDevice, key: SymmetricKey, zoneID: CKRecordZone.ID, existingSystemFields: Data?) throws -> CKRecord {
        let record = makeRecord(
            type: CloudRecordType.device,
            name: device.id,
            zoneID: zoneID,
            systemFields: existingSystemFields
        )
        let json = try JSONEncoder.vault.encode(device)
        record[Field.payload] = try CryptoBox.seal(json, key: key) as CKRecordValue
        record[Field.deviceID] = device.id as CKRecordValue
        record[Field.updatedAt] = device.lastSeenAt as CKRecordValue
        return record
    }

    static func device(from record: CKRecord, key: SymmetricKey) throws -> VaultDevice {
        guard let payload = record[Field.payload] as? Data else { throw MappingError.missingPayload }
        let json = try CryptoBox.open(payload, key: key)
        return try JSONDecoder.vault.decode(VaultDevice.self, from: json)
    }

    // MARK: - Attachments

    /// The asset handed to CloudKit is the local file verbatim — and that file
    /// is already ciphertext, so nothing is encrypted twice and nothing leaves
    /// in the clear.
    static func attachmentRecord(
        attachmentID: UUID,
        itemID: UUID,
        sealedFileURL: URL,
        zoneID: CKRecordZone.ID,
        existingSystemFields: Data?
    ) -> CKRecord {
        let record = makeRecord(
            type: CloudRecordType.attachment,
            name: attachmentID.uuidString,
            zoneID: zoneID,
            systemFields: existingSystemFields
        )
        record[Field.asset] = CKAsset(fileURL: sealedFileURL)
        record[Field.itemID] = itemID.uuidString as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        return record
    }

    /// Writes the downloaded ciphertext into the local attachment store.
    static func saveAttachment(from record: CKRecord) throws {
        guard let id = UUID(uuidString: record.recordID.recordName) else { throw MappingError.missingPayload }
        guard let asset = record[Field.asset] as? CKAsset, let url = asset.fileURL else {
            throw MappingError.missingPayload
        }
        try AttachmentStore.storeSealed(from: url, id: id)
    }

    // MARK: - System fields

    /// Rebuilds a record from the cached server metadata so CloudKit can tell
    /// an edit from a fresh insert (and detect conflicts).
    private static func makeRecord(type: String, name: String, zoneID: CKRecordZone.ID, systemFields: Data?) -> CKRecord {
        if let systemFields,
           let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) {
            coder.requiresSecureCoding = true
            // `finishDecoding()` must be called before the unarchiver goes
            // away no matter how decoding turns out — the original code only
            // called it on the success path, so a corrupt/incompatible blob
            // (e.g. after an app update changes what CKRecord archives) would
            // skip it and trip NSKeyedUnarchiver's "finishDecoding was never
            // called" assertion instead of falling back cleanly.
            defer { coder.finishDecoding() }
            if let record = CKRecord(coder: coder) {
                return record
            }
        }
        return CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
    }

    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    enum MappingError: LocalizedError {
        case missingPayload
        var errorDescription: String? { "A synced record was incomplete and has been skipped." }
    }
}
