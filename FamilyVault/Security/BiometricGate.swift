import Foundation
import LocalAuthentication

/// A second Face ID check in front of individual secrets, for people who leave
/// the app open on a table. Off by default — the vault is already locked.
enum BiometricGate {

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        // No biometry enrolled *and* no passcode set on the device means
        // there is no owner-authentication mechanism to check at all. That's
        // rare, but this gate exists specifically to stand in front of a
        // secret — failing open here would make it a no-op exactly when it's
        // least expected. Fail closed instead: the secret simply won't
        // reveal, same as if the user tapped Cancel.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            // Covers "no biometry enrolled", "biometry temporarily locked
            // out" (too many failed attempts) and a user-cancelled prompt —
            // all of which should simply not reveal the secret, not crash.
            return false
        }
    }
}
