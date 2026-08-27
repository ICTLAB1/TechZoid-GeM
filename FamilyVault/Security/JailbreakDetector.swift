import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Best-effort, non-blocking signal that this device may be jailbroken or
/// otherwise tampered with.
///
/// None of this is a security boundary — a sufficiently determined jailbreak
/// tweak can hide every signal checked here. It exists only to warn the
/// people using this vault that on-device encryption may be easier to bypass
/// than they'd expect, so they can make an informed call about what they
/// store here. False negatives (a jailbroken phone reported as clean) are
/// expected and fine. A crash or a hang is not, so every check is wrapped
/// defensively and nothing here is allowed to propagate an error.
enum JailbreakDetector {

    /// Paths that only exist once a jailbreak tool (or the package manager it
    /// installs) has written to the filesystem outside the App Store sandbox.
    private static let suspiciousPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/Library/MobileSubstrate/DynamicLibraries",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/usr/bin/ssh",
        "/etc/apt",
        "/private/var/lib/apt",
        "/private/var/lib/cydia",
        "/private/var/stash",
        "/var/checkra1n.dmg",
        "/.installed_unc0ver"
    ]

    /// A file this app has no business being able to write outside its own
    /// sandbox container. A jailbroken device typically has a world-writable
    /// filesystem, so this write quietly succeeds instead of failing.
    private static let sandboxEscapeTestPath = "/private/jailbreak-test.txt"

    /// Computed once and cached for the lifetime of the process — this is a
    /// launch-time signal, not something that needs to be re-polled while the
    /// app runs.
    private static let cached: Bool = computeIsLikelyCompromised()

    /// True if this device shows one or more well-known signs of a jailbreak
    /// or filesystem tampering. Never throws, never blocks the main thread
    /// for long, and a `false` here is not a guarantee of anything.
    static var isLikelyCompromised: Bool { cached }

    private static func computeIsLikelyCompromised() -> Bool {
        #if targetEnvironment(simulator)
        // The simulator fails several of these checks for reasons that have
        // nothing to do with jailbreaking (e.g. /bin/bash is just... there).
        return false
        #else
        if hasSuspiciousPaths() { return true }
        if canEscapeSandbox() { return true }
        if canOpenCydiaURLScheme() { return true }
        return false
        #endif
    }

    private static func hasSuspiciousPaths() -> Bool {
        let fileManager = FileManager.default
        for path in suspiciousPaths {
            if fileManager.fileExists(atPath: path) { return true }
        }
        return false
    }

    private static func canEscapeSandbox() -> Bool {
        let path = sandboxEscapeTestPath
        do {
            try "jailbreak test".write(toFile: path, atomically: true, encoding: .utf8)
            // Clean up after ourselves regardless of what happens above —
            // best effort, ignore any error.
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// `cydia://` only resolves on a jailbroken device with Cydia installed.
    /// `canOpenURL` must run on the main thread and only makes sense with a
    /// running `UIApplication`, so this is skipped entirely when neither
    /// holds (e.g. an app/action extension, or a very early launch context).
    private static func canOpenCydiaURLScheme() -> Bool {
        #if canImport(UIKit)
        guard let url = URL(string: "cydia://package/com.example.package") else { return false }
        if Thread.isMainThread {
            return UIApplication.shared.canOpenURL(url)
        } else {
            return DispatchQueue.main.sync { UIApplication.shared.canOpenURL(url) }
        }
        #else
        return false
        #endif
    }
}
