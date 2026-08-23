import Foundation
import LocalAuthentication
import Security

/// Thin wrapper over the iOS keychain.
///
/// The vault's data key is stored here behind `.userPresence`, so reading it
/// back is *itself* the Face ID prompt — there is no separate "unlock flag"
/// that could be bypassed. Everything is `ThisDeviceOnly`, so it never travels
/// in an iCloud or iTunes backup.
enum Keychain {

    static let service = "com.example.familyvault.keys"

    enum Failure: LocalizedError {
        case unexpectedStatus(OSStatus)
        case userCancelled
        case notFound

        var errorDescription: String? {
            switch self {
            case .userCancelled: "Authentication was cancelled."
            case .notFound: "No saved key on this device."
            case .unexpectedStatus(let status):
                "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
            }
        }
    }

    // MARK: - Biometry-protected items

    static func storeBiometryProtected(_ data: Data, account: String) throws {
        try? delete(account: account)

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            throw error?.takeRetainedValue() as Error? ?? Failure.unexpectedStatus(errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.unexpectedStatus(status) }
    }

    /// Reads a biometry-protected item. Presents Face ID / Touch ID / passcode.
    static func readBiometryProtected(account: String, prompt: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: prompt
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw Failure.notFound }
            return data
        case errSecItemNotFound:
            throw Failure.notFound
        case errSecUserCanceled, errSecAuthFailed:
            throw Failure.userCancelled
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    // MARK: - Plain items (non-secret identifiers)

    static func store(_ data: Data, account: String) throws {
        try? delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.unexpectedStatus(status) }
    }

    static func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func exists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        // `interactionNotAllowed` means the item is there but needs Face ID — which is a "yes".
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.unexpectedStatus(status)
        }
    }

    // MARK: - Biometry availability

    static var biometryDescription: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return "Passcode" }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }
}
