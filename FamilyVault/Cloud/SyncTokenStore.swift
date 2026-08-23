import CloudKit
import Foundation

/// Persists the CloudKit server change token so each sync only pulls what is new.
final class SyncTokenStore {

    private var tokens: [String: Data] = [:]

    init() {
        load()
    }

    func token(for key: String) -> CKServerChangeToken? {
        guard let data = tokens[key] else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func setToken(_ token: CKServerChangeToken?, for key: String) {
        if let token, let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            tokens[key] = data
        } else {
            tokens.removeValue(forKey: key)
        }
        save()
    }

    func reset() {
        tokens.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.syncTokensFile),
              let decoded = try? JSONDecoder().decode([String: Data].self, from: data)
        else { return }
        tokens = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        try? data.write(to: AppPaths.syncTokensFile, options: [.atomic, .completeFileProtection])
    }
}
