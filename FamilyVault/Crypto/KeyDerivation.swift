import CommonCrypto
import CryptoKit
import Foundation

/// Turns the human master passphrase into a 256-bit key-encryption key.
///
/// PBKDF2-HMAC-SHA256 with a high iteration count: the passphrase itself is
/// never stored anywhere, and a stolen iCloud copy of the wrapped key is
/// useless without brute-forcing the passphrase at ~600k hashes per guess.
enum KeyDerivation {

    static let defaultIterations = 600_000
    static let saltLength = 32

    enum Failure: LocalizedError {
        case derivationFailed
        var errorDescription: String? { "Could not derive the encryption key from that passphrase." }
    }

    static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passphraseBytes = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)

        let status = salt.withUnsafeBytes { saltBuffer -> Int32 in
            guard let saltBase = saltBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return Int32(kCCParamError)
            }
            return CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passphraseBytes.map { Int8(bitPattern: $0) }, passphraseBytes.count,
                saltBase, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }

        guard status == kCCSuccess else { throw Failure.derivationFailed }
        return SymmetricKey(data: Data(derived))
    }

    /// Rough strength check shown while the user is choosing a passphrase.
    static func strength(of passphrase: String) -> PassphraseStrength {
        let length = passphrase.count
        var classes = 0
        if passphrase.rangeOfCharacter(from: .lowercaseLetters) != nil { classes += 1 }
        if passphrase.rangeOfCharacter(from: .uppercaseLetters) != nil { classes += 1 }
        if passphrase.rangeOfCharacter(from: .decimalDigits) != nil { classes += 1 }
        if passphrase.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { classes += 1 }
        let words = passphrase.split(separator: " ").count

        if length < 10 { return .tooShort }
        if words >= 4 && length >= 20 { return .strong }
        if length >= 16 && classes >= 3 { return .strong }
        if length >= 12 && classes >= 2 { return .fair }
        return .weak
    }
}

enum PassphraseStrength {
    case tooShort, weak, fair, strong

    var label: String {
        switch self {
        case .tooShort: "Too short — use at least 10 characters"
        case .weak: "Weak"
        case .fair: "Fair"
        case .strong: "Strong"
        }
    }

    var isAcceptable: Bool {
        switch self {
        case .tooShort, .weak: false
        case .fair, .strong: true
        }
    }
}
