import Combine
import UIKit

/// Watches for screen recording, AirPlay mirroring, or a screen-sharing
/// session — anything that routes what's on screen somewhere this app can't
/// see or control. An app whose whole purpose is showing bank details and
/// passwords can't rely on the app-switcher privacy shield alone, since that
/// only covers backgrounding: a recording started while the vault sits open
/// would otherwise capture everything untouched.
@MainActor
final class ScreenProtectionMonitor: ObservableObject {

    static let shared = ScreenProtectionMonitor()

    /// True while the screen is being recorded, mirrored, or otherwise
    /// captured — mirrors `UIScreen.main.isCaptured`.
    @Published private(set) var isBeingRecorded: Bool = false

    private var observer: NSObjectProtocol?

    private init() {}

    /// Starts observing capture-state changes. Safe to call more than once —
    /// a second call is a no-op rather than stacking duplicate observers.
    func startMonitoring() {
        guard observer == nil else { return }

        isBeingRecorded = UIScreen.main.isCaptured

        observer = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isBeingRecorded = UIScreen.main.isCaptured
            }
        }
    }

    func stopMonitoring() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        isBeingRecorded = false
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
