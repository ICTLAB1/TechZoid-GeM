import SwiftUI
import UIKit

/// Copies a secret to the pasteboard and takes it back again shortly after, so
/// a card number doesn't sit in the clipboard for the rest of the day.
enum ClipboardService {

    static func copy(_ value: String, clearAfter seconds: Int) {
        let pasteboard = UIPasteboard.general

        if seconds > 0 {
            // iOS clears it for us at the deadline even if the app is killed.
            pasteboard.setItems(
                [[UIPasteboard.typeAutomatic: value]],
                options: [.expirationDate: Date().addingTimeInterval(TimeInterval(seconds))]
            )
        } else {
            pasteboard.string = value
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func clearNow() {
        UIPasteboard.general.items = []
    }
}
