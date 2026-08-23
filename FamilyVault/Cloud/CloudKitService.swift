import CloudKit
import Foundation

/// Where this device's copy of the vault lives.
enum VaultScope: Equatable {
    /// This device created the vault: records live in our own private database.
    case owner(CKRecordZone.ID)
    /// This device accepted the other person's share: records live in the shared database.
    case participant(CKRecordZone.ID)

    var zoneID: CKRecordZone.ID {
        switch self {
        case .owner(let id), .participant(let id): id
        }
    }

    var isOwner: Bool {
        if case .owner = self { return true }
        return false
    }
}

enum CloudRecordType {
    static let item = "VaultItem"
    static let meta = "VaultMeta"
    static let device = "VaultDevice"
    static let attachment = "VaultAttachment"
}

/// All CloudKit plumbing. It never sees plaintext: callers hand it sealed
/// blobs and it hands sealed blobs back.
actor CloudKitService {

    static let zoneName = "VaultZone"
    static let metaRecordName = "vault-meta"

    nonisolated let container: CKContainer
    private var cachedScope: VaultScope?

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    enum Failure: LocalizedError {
        case accountUnavailable(CKAccountStatus)
        case notShareable

        var errorDescription: String? {
            switch self {
            case .accountUnavailable(let status):
                switch status {
                case .noAccount: "No iCloud account is signed in on this iPhone. Open Settings and sign in to iCloud to sync with your other phone."
                case .restricted: "iCloud is restricted on this iPhone (parental controls or a device policy)."
                case .couldNotDetermine: "Could not reach iCloud. Check your internet connection."
                case .temporarilyUnavailable: "iCloud is temporarily unavailable. Sync will retry."
                @unknown default: "iCloud is unavailable."
                }
            case .notShareable:
                "Only the phone that created the vault can send the invitation."
            }
        }
    }

    // MARK: - Account

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    func requireAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw Failure.accountUnavailable(status) }
    }

    // MARK: - Scope

    private func database(for scope: VaultScope) -> CKDatabase {
        switch scope {
        case .owner: container.privateCloudDatabase
        case .participant: container.sharedCloudDatabase
        }
    }

    /// Decides — once per launch — whether we are the owner or the invited partner.
    func resolveScope() async throws -> VaultScope {
        if let cachedScope { return cachedScope }
        try await requireAccount()

        // An accepted share shows up as a zone in the shared database.
        let sharedZones = (try? await container.sharedCloudDatabase.allRecordZones()) ?? []
        if let zone = sharedZones.first(where: { $0.zoneID.zoneName == Self.zoneName }) {
            let scope = VaultScope.participant(zone.zoneID)
            cachedScope = scope
            return scope
        }

        // Otherwise this device owns (or is about to create) the vault zone.
        let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        let existing = (try? await container.privateCloudDatabase.allRecordZones()) ?? []
        if !existing.contains(where: { $0.zoneID.zoneName == Self.zoneName }) {
            _ = try await container.privateCloudDatabase.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID)], deleting: []
            )
        }
        let scope = VaultScope.owner(zoneID)
        cachedScope = scope
        return scope
    }

    func invalidateScope() {
        cachedScope = nil
    }

    // MARK: - Reading

    struct FetchResult {
        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var newToken: CKServerChangeToken?
        var zoneWasPurged = false
    }

    /// Pulls everything that changed since `token`.
    func fetchChanges(scope: VaultScope, since token: CKServerChangeToken?) async throws -> FetchResult {
        let db = database(for: scope)
        var result = FetchResult()
        var currentToken = token
        var moreComing = true

        while moreComing {
            do {
                let batch = try await db.recordZoneChanges(inZoneWith: scope.zoneID, since: currentToken)
                for (_, modificationResult) in batch.modificationResultsByID {
                    if case .success(let modification) = modificationResult {
                        result.changedRecords.append(modification.record)
                    }
                }
                result.deletedRecordIDs.append(contentsOf: batch.deletions.map(\.recordID))
                currentToken = batch.changeToken
                moreComing = batch.moreComing
            } catch let error as CKError where error.code == .changeTokenExpired {
                // Server dropped our token — start over with a full fetch.
                currentToken = nil
                result = FetchResult()
                result.zoneWasPurged = true
                moreComing = true
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                result.zoneWasPurged = true
                result.newToken = nil
                return result
            }
        }

        result.newToken = currentToken
        return result
    }

    func fetchRecord(named name: String, scope: VaultScope) async throws -> CKRecord? {
        let db = database(for: scope)
        let id = CKRecord.ID(recordName: name, zoneID: scope.zoneID)
        do {
            return try await db.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: - Writing

    struct SaveOutcome {
        /// Records the server accepted.
        var saved: [CKRecord] = []
        /// Records the other phone had already changed. Carries the server's
        /// version so the next attempt uses a current change tag — the local
        /// edit stays pending rather than being thrown away.
        var conflicted: [CKRecord] = []
    }

    @discardableResult
    func save(records: [CKRecord], deleting recordIDs: [CKRecord.ID], scope: VaultScope) async throws -> SaveOutcome {
        var outcome = SaveOutcome()
        guard !records.isEmpty || !recordIDs.isEmpty else { return outcome }
        let db = database(for: scope)

        // CloudKit caps a single request at 400 records; stay well under it.
        for chunk in records.chunked(into: 200) {
            let response = try await db.modifyRecords(saving: chunk, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
            for (_, result) in response.saveResults {
                switch result {
                case .success(let record):
                    outcome.saved.append(record)
                case .failure(let error as CKError) where error.code == .serverRecordChanged:
                    if let serverRecord = error.serverRecord { outcome.conflicted.append(serverRecord) }
                case .failure(let error):
                    throw error
                }
            }
        }

        for chunk in recordIDs.chunked(into: 200) {
            _ = try await db.modifyRecords(saving: [], deleting: chunk, savePolicy: .changedKeys, atomically: false)
        }

        return outcome
    }

    // MARK: - Sharing the vault with one other person

    /// Returns the share for the vault zone, creating it the first time.
    func fetchOrCreateShare(scope: VaultScope, title: String) async throws -> CKShare {
        guard case .owner(let zoneID) = scope else { throw Failure.notShareable }
        let db = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)

        if let existing = try? await db.record(for: shareID) as? CKShare {
            return existing
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .none   // invitation-only, never a public link

        let response = try await db.modifyRecords(saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let outcome = response.saveResults[shareID] else { return share }
        switch outcome {
        case .success(let record):
            return (record as? CKShare) ?? share
        case .failure(let error):
            throw error
        }
    }

    func currentShare(scope: VaultScope) async -> CKShare? {
        let db = database(for: scope)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: scope.zoneID)
        return try? await db.record(for: shareID) as? CKShare
    }

    /// Revokes the partner's access (owner only).
    func removeParticipants(from share: CKShare, scope: VaultScope) async throws {
        guard case .owner = scope else { throw Failure.notShareable }
        for participant in share.participants where participant.role != .owner {
            share.removeParticipant(participant)
        }
        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true
        )
    }

    /// Called when the partner taps the invitation link.
    func accept(_ metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
        cachedScope = nil
    }

    // MARK: - Silent push so the other phone updates on its own

    func subscribeToChanges(scope: VaultScope) async {
        let db = database(for: scope)
        let subscriptionID = scope.isOwner ? "vault-private-changes" : "vault-shared-changes"

        let existing = try? await db.subscription(for: subscriptionID)
        guard existing == nil else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent: no banner, just a nudge to sync
        subscription.notificationInfo = info
        _ = try? await db.save(subscription)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
