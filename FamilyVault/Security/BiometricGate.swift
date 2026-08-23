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
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
