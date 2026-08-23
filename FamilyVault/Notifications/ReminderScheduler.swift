import Foundation
import UserNotifications

/// Local notifications for renewals, EMIs and expiries.
///
/// The notification text stays deliberately vague — "A policy is due for
/// renewal" — because lock-screen banners are visible to anyone holding the
/// phone. Details only appear inside the unlocked app.
final class ReminderScheduler {

    private let center = UNUserNotificationCenter.current()
    private let prefix = "vault-reminder-"

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    func reschedule(for items: [VaultItem]) {
        Task { await rescheduleAsync(for: items) }
    }

    /// Mirrors `AppSettings.remindersEnabled` — read straight from defaults so
    /// the scheduler stays usable from the store, which has no settings object.
    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "settings.remindersEnabled")
    }

    private func rescheduleAsync(for items: [VaultItem]) async {
        guard isEnabled else {
            cancelAll()
            return
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )

        let calendar = Calendar.current
        for item in items {
            guard let reminderDate = item.reminderDate else { continue }
            guard let fireDate = calendar.date(byAdding: .day, value: -item.reminderLeadDays, to: reminderDate) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: fireDate)
            components.hour = 9
            guard let resolved = calendar.date(from: components), resolved > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminderTitle(for: item.category)
            content.body = "Open Vault to see the details."
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour], from: resolved),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: prefix + item.id.uuidString,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private func reminderTitle(for category: ItemCategory) -> String {
        switch category {
        case .insurance: "A policy is coming up for renewal"
        case .investment: "An investment is reaching maturity"
        case .loan: "An EMI is due soon"
        case .card: "A card payment is due soon"
        case .identity: "A document is expiring soon"
        default: "You have a reminder due"
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
