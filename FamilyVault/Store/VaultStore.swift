import CloudKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum SyncState: Equatable {
    case idle
    case syncing
    case failed(String)

    var isSyncing: Bool { self == .syncing }
}

enum DeviceAdmission: Equatable {
    case admitted
    case blocked(registered: [VaultDevice])
    case unknown          // could not reach iCloud yet; offline use is still allowed
}

enum ItemSort: String, CaseIterable, Identifiable {
    case name
    case recentlyUpdated
    case reminderDate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: "Name"
        case .recentlyUpdated: "Recently changed"
        case .reminderDate: "Next due"
        }
    }
}

/// The single source of truth once the vault is unlocked: holds the decrypted
/// items in memory, writes them back encrypted, and reconciles with the other
/// phone through CloudKit.
@MainActor
final class VaultStore: ObservableObject {

    @Published private(set) var items: [VaultItem] = []
    @Published private(set) var deletedItems: [VaultItem] = []
    @Published private(set) var devices: [VaultDevice] = []
    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var pendingChangeCount: Int = 0
    @Published private(set) var scope: VaultScope?
    /// Bumped whenever attachment bytes land, so views re-render thumbnails.
    @Published private(set) var attachmentRevision: Int = 0

    static let maximumDevices = 2
    /// How long a deleted entry stays recoverable in Recently Deleted before
    /// it — and its attachments — are destroyed on both phones.
    static let trashRetentionDays = 30

    private let cloud: CloudKitService
    private let keyManager: VaultKeyManager
    private let tokens = SyncTokenStore()
    private let reminders = ReminderScheduler()

    private var dataKey: SymmetricKey?
    private var material: VaultKeyMaterial?
    private var file = VaultFile.empty
    private var syncTask: Task<Void, Never>?

    init(cloud: CloudKitService, keyManager: VaultKeyManager) {
        self.cloud = cloud
        self.keyManager = keyManager
    }

    var isOpen: Bool { dataKey != nil }
    var isOwner: Bool { scope?.isOwner ?? true }
    var currentDeviceID: String { keyManager.deviceID }
    var keyMaterial: VaultKeyMaterial? { material }

    /// Used to stamp "last changed on …" onto every edit.
    var currentDeviceName: String {
        file.devices.first { $0.id == keyManager.deviceID }?.name ?? ""
    }

    // MARK: - Opening and closing

    func open(dataKey: SymmetricKey, material: VaultKeyMaterial) throws {
        self.dataKey = dataKey
        self.material = material
        self.file = try LocalPersistence.load(key: dataKey)
        refreshPublished()
    }

    func close() {
        syncTask?.cancel()
        syncTask = nil
        dataKey = nil
        material = nil
        file = .empty
        items = []
        deletedItems = []
        devices = []
        syncState = .idle
        pendingChangeCount = 0
    }

    /// Removes the vault from this device only. The other phone keeps its copy.
    func wipeThisDevice() {
        close()
        LocalPersistence.wipe()
        tokens.reset()
        keyManager.resetDevice()
        reminders.cancelAll()
    }

    // MARK: - Reading

    func items(in category: ItemCategory, sortedBy sort: ItemSort = .name, holder: String? = nil) -> [VaultItem] {
        let filtered = items.filter { item in
            guard item.category == category else { return false }
            guard let holder else { return true }
            return item.holder.caseInsensitiveCompare(holder) == .orderedSame
        }
        return sorted(filtered, by: sort)
    }

    func sorted(_ input: [VaultItem], by sort: ItemSort) -> [VaultItem] {
        switch sort {
        case .name:
            input.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .recentlyUpdated:
            input.sorted { $0.updatedAt > $1.updatedAt }
        case .reminderDate:
            input.sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
        }
    }

    func item(id: UUID) -> VaultItem? {
        items.first { $0.id == id }
    }

    func count(in category: ItemCategory) -> Int {
        items.filter { $0.category == category }.count
    }

    func search(_ query: String, in category: ItemCategory? = nil) -> [VaultItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return items
            .filter { item in
                guard category == nil || item.category == category else { return false }
                return item.matches(trimmed)
            }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    var favourites: [VaultItem] {
        items.filter(\.isFavourite)
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    /// Every distinct "belongs to" value in use, for the filter chips and the
    /// editor's suggestions.
    var holders: [String] {
        let names = items.map(\.holder)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Renewals, EMIs and expiries worth surfacing on the home screen.
    func upcomingReminders(within days: Int = 120) -> [VaultItem] {
        items.filter { item in
            guard let remaining = item.daysUntilReminder else { return false }
            return remaining <= days
        }
        .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
    }

    var summary: VaultSummary { VaultSummary.build(from: items) }

    var healthFindings: [HealthFinding] { VaultHealth.findings(for: items) }

    // MARK: - Writing

    func save(_ item: VaultItem) {
        var updated = item
        updated.touch(on: currentDeviceName)
        if let index = file.items.firstIndex(where: { $0.id == updated.id }) {
            file.items[index] = updated
        } else {
            file.items.append(updated)
        }
        markPending(itemID: updated.id.uuidString)
        persistAndSync()
    }

    /// Moves an entry to Recently Deleted. Its contents are kept — that is what
    /// makes restoring possible — until the retention window closes.
    func delete(_ item: VaultItem) {
        guard let index = file.items.firstIndex(where: { $0.id == item.id }) else { return }
        file.items[index].isDeleted = true
        file.items[index].deletedAt = Date()
        file.items[index].reminderDate = nil
        file.items[index].isFavourite = false
        file.items[index].touch(on: currentDeviceName)
        markPending(itemID: item.id.uuidString)
        persistAndSync()
    }

    func restore(_ item: VaultItem) {
        guard let index = file.items.firstIndex(where: { $0.id == item.id }) else { return }
        file.items[index].isDeleted = false
        file.items[index].deletedAt = nil
        file.items[index].touch(on: currentDeviceName)
        markPending(itemID: item.id.uuidString)
        persistAndSync()
    }

    /// Destroys an entry immediately on both phones, skipping the wait.
    func deleteForever(_ item: VaultItem) {
        for attachment in item.attachments {
            AttachmentStore.remove(attachment.id)
            queueAttachmentDeletion(attachment.id)
        }
        file.items.removeAll { $0.id == item.id }
        file.pendingItemIDs.removeAll { $0 == item.id.uuidString }
        file.recordSystemFields.removeValue(forKey: item.id.uuidString)

        if let scope {
            let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: scope.zoneID)
            let cloud = self.cloud
            Task { _ = try? await cloud.save(records: [], deleting: [recordID], scope: scope) }
        }
        persistAndSync()
    }

    func emptyTrash() {
        for item in deletedItems { deleteForever(item) }
    }

    func toggleFavourite(_ item: VaultItem) {
        var updated = item
        updated.isFavourite.toggle()
        save(updated)
    }

    private func markPending(itemID: String) {
        if !file.pendingItemIDs.contains(itemID) { file.pendingItemIDs.append(itemID) }
    }

    private func markPendingDevice(_ id: String) {
        if !file.pendingDeviceIDs.contains(id) { file.pendingDeviceIDs.append(id) }
    }

    private func queueAttachmentDeletion(_ id: UUID) {
        file.pendingAttachmentIDs.removeAll { $0 == id.uuidString }
        if !file.attachmentIDsToDelete.contains(id.uuidString) {
            file.attachmentIDsToDelete.append(id.uuidString)
        }
    }

    private func persistAndSync() {
        persist()
        refreshPublished()
        scheduleSync()
    }

    private func persist() {
        guard let dataKey else { return }
        do {
            try LocalPersistence.save(file, key: dataKey)
        } catch {
            syncState = .failed("Could not save to this device: \(error.localizedDescription)")
        }
    }

    private func refreshPublished() {
        items = file.items.filter { !$0.isDeleted }
        deletedItems = file.items.filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        devices = file.devices.sorted { $0.addedAt < $1.addedAt }
        pendingChangeCount = file.pendingItemIDs.count
            + file.pendingDeviceIDs.count
            + file.pendingAttachmentIDs.count
            + (file.metaNeedsPush ? 1 : 0)
        reminders.reschedule(for: items)
    }

    // MARK: - Attachments

    /// Encrypts the bytes, files them against the item, and queues the upload.
    @discardableResult
    func addAttachment(data: Data, filename: String, typeIdentifier: String, to item: VaultItem) throws -> ItemAttachment {
        guard let dataKey else { throw VaultKeyManager.Failure.noKeyMaterial }
        let type = UTType(typeIdentifier) ?? .data
        let prepared = try AttachmentStore.prepare(data: data, filename: filename, type: type)
        try AttachmentStore.store(data: prepared.data, id: prepared.attachment.id, key: dataKey)

        var updated = item
        updated.attachments.append(prepared.attachment)
        if !file.pendingAttachmentIDs.contains(prepared.attachment.id.uuidString) {
            file.pendingAttachmentIDs.append(prepared.attachment.id.uuidString)
        }
        save(updated)
        attachmentRevision += 1
        return prepared.attachment
    }

    func removeAttachment(_ attachment: ItemAttachment, from item: VaultItem) {
        AttachmentStore.remove(attachment.id)
        queueAttachmentDeletion(attachment.id)

        var updated = item
        updated.attachments.removeAll { $0.id == attachment.id }
        save(updated)
        attachmentRevision += 1
    }

    /// Decrypted bytes for display. Never written back to disk in the clear.
    func attachmentData(_ attachment: ItemAttachment) throws -> Data {
        guard let dataKey else { throw VaultKeyManager.Failure.noKeyMaterial }
        return try AttachmentStore.load(id: attachment.id, key: dataKey)
    }

    func isAttachmentAvailable(_ attachment: ItemAttachment) -> Bool {
        AttachmentStore.exists(attachment.id)
    }

    var attachmentCount: Int { items.reduce(0) { $0 + $1.attachments.count } }

    /// Decrypted attachment bytes, keyed by id — used only when building an
    /// encrypted backup, which immediately re-seals them under its own password.
    func attachmentPayloads() -> [String: Data] {
        var payloads: [String: Data] = [:]
        for item in items {
            for attachment in item.attachments {
                guard let data = try? attachmentData(attachment) else { continue }
                payloads[attachment.id.uuidString] = data
            }
        }
        return payloads
    }

    /// Puts a document from a backup back into the store and queues its upload.
    func restoreAttachment(id: UUID, data: Data) {
        guard let dataKey else { return }
        guard (try? AttachmentStore.store(data: data, id: id, key: dataKey)) != nil else { return }
        if !file.pendingAttachmentIDs.contains(id.uuidString) {
            file.pendingAttachmentIDs.append(id.uuidString)
        }
        attachmentRevision += 1
    }

    // MARK: - Passphrase rotation

    /// Stores re-wrapped key material and pushes it so the other phone picks it up.
    func updateKeyMaterial(_ updated: VaultKeyMaterial) {
        material = updated
        keyManager.cache(updated)
        file.metaNeedsPush = true
        persistAndSync()
    }

    // MARK: - Devices

    func registerCurrentDevice(named name: String? = nil) async -> DeviceAdmission {
        guard dataKey != nil else { return .unknown }
        await sync()
        guard scope != nil else { return .unknown }

        let deviceID = keyManager.deviceID
        if let index = file.devices.firstIndex(where: { $0.id == deviceID }) {
            file.devices[index].lastSeenAt = Date()
            if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                file.devices[index].name = name
            }
            markPendingDevice(deviceID)
            persistAndSync()
            return .admitted
        }

        guard file.devices.count < Self.maximumDevices else {
            return .blocked(registered: file.devices)
        }

        let device = VaultDevice.current(id: deviceID, name: name)
        file.devices.append(device)
        markPendingDevice(deviceID)
        persistAndSync()
        return .admitted
    }

    func removeDevice(_ device: VaultDevice) async {
        guard device.id != keyManager.deviceID else { return }
        file.devices.removeAll { $0.id == device.id }
        file.recordSystemFields.removeValue(forKey: device.id)
        persist()
        refreshPublished()

        guard let scope else { return }
        let recordID = CKRecord.ID(recordName: device.id, zoneID: scope.zoneID)
        _ = try? await cloud.save(records: [], deleting: [recordID], scope: scope)
    }

    func renameCurrentDevice(to name: String) {
        let deviceID = keyManager.deviceID
        guard let index = file.devices.firstIndex(where: { $0.id == deviceID }) else { return }
        file.devices[index].name = name
        file.devices[index].lastSeenAt = Date()
        markPendingDevice(deviceID)
        persistAndSync()
    }

    // MARK: - Sync

    /// Fire-and-forget sync, for callers that shouldn't wait (a save, a
    /// foreground event, a silent push).
    func scheduleSync() {
        Task { await sync() }
    }

    /// Runs a sync, or joins the one already in flight. Callers that need the
    /// result — device registration in particular — can await this safely.
    func sync() async {
        if let existing = syncTask {
            await existing.value
            // Anything queued after that run started still needs a trip up.
            guard pendingChangeCount > 0 else { return }
        }
        let task = Task { await performSync() }
        syncTask = task
        await task.value
        if syncTask == task { syncTask = nil }
    }

    private func performSync() async {
        guard let dataKey else { return }
        syncState = .syncing

        do {
            let scope = try await cloud.resolveScope()
            self.scope = scope
            await cloud.subscribeToChanges(scope: scope)

            try await pull(scope: scope, key: dataKey)
            try await push(scope: scope, key: dataKey)
            purgeExpiredTrash()

            persist()
            refreshPublished()
            lastSyncedAt = Date()
            syncState = .idle
        } catch {
            syncState = .failed(friendlyMessage(for: error))
        }
    }

    private func pull(scope: VaultScope, key: SymmetricKey) async throws {
        let tokenKey = "zone-\(scope.zoneID.zoneName)-\(scope.zoneID.ownerName)"
        let result = try await cloud.fetchChanges(scope: scope, since: tokens.token(for: tokenKey))

        if result.zoneWasPurged {
            tokens.setToken(nil, for: tokenKey)
        }

        var didReceiveAttachment = false

        for record in result.changedRecords {
            switch record.recordType {
            case CloudRecordType.item:
                guard let remote = try? CloudRecordMapper.item(from: record, key: key) else { continue }
                merge(remote: remote, systemFields: CloudRecordMapper.systemFields(of: record))

            case CloudRecordType.meta:
                if let remoteMaterial = try? CloudRecordMapper.material(from: record) {
                    // The other phone may have rotated the passphrase; the data
                    // key inside is unchanged, so nothing needs re-encrypting.
                    if remoteMaterial != material {
                        material = remoteMaterial
                        keyManager.cache(remoteMaterial)
                    }
                    file.recordSystemFields[CloudKitService.metaRecordName] = CloudRecordMapper.systemFields(of: record)
                    file.metaNeedsPush = false
                }

            case CloudRecordType.device:
                guard let remote = try? CloudRecordMapper.device(from: record, key: key) else { continue }
                if let index = file.devices.firstIndex(where: { $0.id == remote.id }) {
                    if remote.lastSeenAt >= file.devices[index].lastSeenAt { file.devices[index] = remote }
                } else {
                    file.devices.append(remote)
                }
                file.recordSystemFields[remote.id] = CloudRecordMapper.systemFields(of: record)

            case CloudRecordType.attachment:
                // The asset's temporary file disappears once this batch is
                // released, so copy it into the store right now.
                try? CloudRecordMapper.saveAttachment(from: record)
                file.recordSystemFields[record.recordID.recordName] = CloudRecordMapper.systemFields(of: record)
                didReceiveAttachment = true

            default:
                continue
            }
        }

        for recordID in result.deletedRecordIDs {
            let name = recordID.recordName
            file.recordSystemFields.removeValue(forKey: name)
            file.devices.removeAll { $0.id == name }
            if let uuid = UUID(uuidString: name) {
                file.items.removeAll { $0.id == uuid }
                AttachmentStore.remove(uuid)
            }
        }

        if didReceiveAttachment { attachmentRevision += 1 }
        tokens.setToken(result.newToken, for: tokenKey)
    }

    private func merge(remote: VaultItem, systemFields: Data) {
        file.recordSystemFields[remote.id.uuidString] = systemFields

        guard let index = file.items.firstIndex(where: { $0.id == remote.id }) else {
            file.items.append(remote)
            return
        }

        let local = file.items[index]
        let localIsPending = file.pendingItemIDs.contains(remote.id.uuidString)

        if localIsPending && local.updatedAt > remote.updatedAt {
            return   // our edit is newer; it goes up in the push phase
        }
        file.items[index] = remote
        file.pendingItemIDs.removeAll { $0 == remote.id.uuidString }
    }

    private func push(scope: VaultScope, key: SymmetricKey) async throws {
        var records: [CKRecord] = []

        let hasServerMeta = file.recordSystemFields.keys.contains(CloudKitService.metaRecordName)
        if file.metaNeedsPush || (scope.isOwner && !hasServerMeta) {
            if let material {
                let existing = try? await cloud.fetchRecord(named: CloudKitService.metaRecordName, scope: scope)
                let systemFields = existing.map(CloudRecordMapper.systemFields(of:))
                    ?? file.recordSystemFields[CloudKitService.metaRecordName]
                records.append(CloudRecordMapper.metaRecord(for: material, zoneID: scope.zoneID, existingSystemFields: systemFields))
            }
        }

        for id in file.pendingItemIDs {
            guard let uuid = UUID(uuidString: id), let item = file.items.first(where: { $0.id == uuid }) else { continue }
            let record = try CloudRecordMapper.record(
                for: item, key: key, zoneID: scope.zoneID,
                existingSystemFields: file.recordSystemFields[id]
            )
            records.append(record)
        }

        for id in file.pendingDeviceIDs {
            guard let device = file.devices.first(where: { $0.id == id }) else { continue }
            let record = try CloudRecordMapper.deviceRecord(
                for: device, key: key, zoneID: scope.zoneID,
                existingSystemFields: file.recordSystemFields[id]
            )
            records.append(record)
        }

        for id in file.pendingAttachmentIDs {
            guard let uuid = UUID(uuidString: id),
                  AttachmentStore.exists(uuid),
                  let owner = file.items.first(where: { $0.attachments.contains { $0.id == uuid } })
            else { continue }
            records.append(CloudRecordMapper.attachmentRecord(
                attachmentID: uuid,
                itemID: owner.id,
                sealedFileURL: AttachmentStore.fileURL(for: uuid),
                zoneID: scope.zoneID,
                existingSystemFields: file.recordSystemFields[id]
            ))
        }

        let attachmentDeletions = file.attachmentIDsToDelete.compactMap { name -> CKRecord.ID? in
            guard UUID(uuidString: name) != nil else { return nil }
            return CKRecord.ID(recordName: name, zoneID: scope.zoneID)
        }

        guard !records.isEmpty || !attachmentDeletions.isEmpty else { return }
        let outcome = try await cloud.save(records: records, deleting: attachmentDeletions, scope: scope)

        // Conflicts keep their pending flag: we take the server's change tag so
        // the retry is accepted, and whichever edit is newer wins on merge.
        for record in outcome.saved + outcome.conflicted {
            file.recordSystemFields[record.recordID.recordName] = CloudRecordMapper.systemFields(of: record)
        }
        let savedNames = Set(outcome.saved.map(\.recordID.recordName))
        file.pendingItemIDs.removeAll { savedNames.contains($0) }
        file.pendingDeviceIDs.removeAll { savedNames.contains($0) }
        file.pendingAttachmentIDs.removeAll { savedNames.contains($0) }
        for name in file.attachmentIDsToDelete { file.recordSystemFields.removeValue(forKey: name) }
        file.attachmentIDsToDelete.removeAll()
        if savedNames.contains(CloudKitService.metaRecordName) { file.metaNeedsPush = false }
    }

    /// Entries sitting in Recently Deleted past the retention window are
    /// destroyed for good, on both phones, along with their attachments.
    private func purgeExpiredTrash() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.trashRetentionDays, to: Date()) ?? .distantPast
        let expired = file.items.filter { $0.isDeleted && ($0.deletedAt ?? $0.updatedAt) < cutoff }
        guard !expired.isEmpty, let scope else { return }

        var recordIDs: [CKRecord.ID] = []
        for item in expired {
            recordIDs.append(CKRecord.ID(recordName: item.id.uuidString, zoneID: scope.zoneID))
            for attachment in item.attachments {
                AttachmentStore.remove(attachment.id)
                recordIDs.append(CKRecord.ID(recordName: attachment.id.uuidString, zoneID: scope.zoneID))
            }
            file.items.removeAll { $0.id == item.id }
            file.recordSystemFields.removeValue(forKey: item.id.uuidString)
        }

        let cloud = self.cloud
        Task { _ = try? await cloud.save(records: [], deleting: recordIDs, scope: scope) }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return "No internet connection — your changes are saved on this iPhone and will sync later."
            case .quotaExceeded:
                return "Your iCloud storage is full, so syncing is paused."
            case .notAuthenticated:
                return "Sign in to iCloud in Settings to sync with your other phone."
            case .zoneNotFound, .userDeletedZone:
                return "The shared vault is no longer available in iCloud."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
