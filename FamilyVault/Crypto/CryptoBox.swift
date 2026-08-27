import CryptoKit
import Foundation
import Security

/// Symmetric authenticated encryption used for every byte the vault ever writes
/// to disk or hands to iCloud. AES-256-GCM: confidentiality + tamper detection.
enum CryptoBox {

    enum Failure: LocalizedError {
        case malformedCiphertext
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .malformedCiphertext: "The encrypted data is malformed."
            case .authenticationFailed: "The encrypted data could not be authenticated. Wrong key, or the data was altered."
            }
        }
    }

    /// Encrypts `plaintext`, returning nonce + ciphertext + tag in one blob.
    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw Failure.malformedCiphertext }
        return combined
    }

    static func open(_ combined: Data, key: SymmetricKey) throws -> Data {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw Failure.malformedCiphertext
        }
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            throw Failure.authenticationFailed
        }
    }

    static func randomKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "The system random number generator failed.")
        return Data(bytes)
    }
}

extension SymmetricKey {
    var rawData: Data { withUnsafeBytes { Data($0) } }
}

// MARK: - Best-effort memory wiping

/// Swift's `Data`/`Array` give no hard guarantee that a buffer was never
/// copied elsewhere before this runs, but overwriting our own copy of
/// sensitive bytes (derived keys, raw passphrase bytes) as soon as we're
/// done with it keeps key material from lingering in freed heap memory any
/// longer than necessary.
extension Data {
    mutating func secureZeroOut() {
        withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            let typed = base.bindMemory(to: UInt8.self, capacity: raw.count)
            for i in 0..<raw.count { typed[i] = 0 }
        }
    }
}

extension Array where Element == UInt8 {
    mutating func secureZeroOut() {
        withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            let typed = base.bindMemory(to: UInt8.self, capacity: raw.count)
            for i in 0..<raw.count { typed[i] = 0 }
        }
    }
}

extension Array where Element == Int8 {
    mutating func secureZeroOut() {
        withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            let typed = base.bindMemory(to: UInt8.self, capacity: raw.count)
            for i in 0..<raw.count { typed[i] = 0 }
        }
    }
}
