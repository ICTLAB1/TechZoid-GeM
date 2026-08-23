import Combine
import Foundation

/// User-tunable security behaviour. Deliberately small — every option here is
/// one someone might reasonably want to trade convenience against.
final class AppSettings: ObservableObject {

    private enum Key {
        static let autoLockSeconds = "settings.autoLockSeconds"
        static let biometricsEnabled = "settings.biometricsEnabled"
        static let clipboardClearSeconds = "settings.clipboardClearSeconds"
        static let remindersEnabled = "settings.remindersEnabled"
        static let hasCompletedSetup = "settings.hasCompletedSetup"
        static let requireBiometricsToReveal = "settings.requireBiometricsToReveal"
        static let lastHolder = "settings.lastHolder"
        static let detailedNotifications = "settings.detailedNotifications"
        static let wipeAfterFailedAttempts = "settings.wipeAfterFailedAttempts"
        static let failedAttempts = "settings.failedAttempts"
    }

    static let autoLockChoices: [Int] = [0, 30, 60, 300, 900]

    @Published var autoLockSeconds: Int {
        didSet { defaults.set(autoLockSeconds, forKey: Key.autoLockSeconds) }
    }

    @Published var biometricsEnabled: Bool {
        didSet { defaults.set(biometricsEnabled, forKey: Key.biometricsEnabled) }
    }

    @Published var clipboardClearSeconds: Int {
        didSet { defaults.set(clipboardClearSeconds, forKey: Key.clipboardClearSeconds) }
    }

    @Published var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Key.remindersEnabled) }
    }

    @Published var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: Key.hasCompletedSetup) }
    }

    /// A second Face ID check before any individual secret is shown.
    @Published var requireBiometricsToReveal: Bool {
        didSet { defaults.set(requireBiometricsToReveal, forKey: Key.requireBiometricsToReveal) }
    }

    /// Notifications name the person, the bank and the amount. Turning this
    /// off falls back to "an EMI is due soon" with no identifying detail.
    @Published var detailedNotifications: Bool {
        didSet { defaults.set(detailedNotifications, forKey: Key.detailedNotifications) }
    }

    /// 0 = never. Otherwise the vault erases itself from this iPhone after
    /// this many wrong passphrases — the other phone keeps everything.
    @Published var wipeAfterFailedAttempts: Int {
        didSet { defaults.set(wipeAfterFailedAttempts, forKey: Key.wipeAfterFailedAttempts) }
    }

    @Published var failedAttempts: Int {
        didSet { defaults.set(failedAttempts, forKey: Key.failedAttempts) }
    }

    /// Pre-fills "belongs to" with whatever was used last.
    @Published var lastHolder: String {
        didSet { defaults.set(lastHolder, forKey: Key.lastHolder) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoLockSeconds: 60,
            Key.biometricsEnabled: true,
            Key.clipboardClearSeconds: 45,
            Key.remindersEnabled: true,
            Key.hasCompletedSetup: false,
            Key.requireBiometricsToReveal: false,
            Key.lastHolder: "",
            Key.detailedNotifications: true,
            Key.wipeAfterFailedAttempts: 0,
            Key.failedAttempts: 0
        ])
        autoLockSeconds = defaults.integer(forKey: Key.autoLockSeconds)
        biometricsEnabled = defaults.bool(forKey: Key.biometricsEnabled)
        clipboardClearSeconds = defaults.integer(forKey: Key.clipboardClearSeconds)
        remindersEnabled = defaults.bool(forKey: Key.remindersEnabled)
        hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup)
        requireBiometricsToReveal = defaults.bool(forKey: Key.requireBiometricsToReveal)
        lastHolder = defaults.string(forKey: Key.lastHolder) ?? ""
        detailedNotifications = defaults.bool(forKey: Key.detailedNotifications)
        wipeAfterFailedAttempts = defaults.integer(forKey: Key.wipeAfterFailedAttempts)
        failedAttempts = defaults.integer(forKey: Key.failedAttempts)
    }

    static let wipeAttemptChoices = [0, 5, 10, 20]

    static func wipeAttemptsLabel(_ attempts: Int) -> String {
        attempts == 0 ? "Never" : "After \(attempts) wrong tries"
    }

    static func autoLockLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Immediately"
        case 30: "After 30 seconds"
        case 60: "After 1 minute"
        case 300: "After 5 minutes"
        case 900: "After 15 minutes"
        default: "After \(seconds) seconds"
        }
    }
}
