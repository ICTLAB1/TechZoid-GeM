import Foundation
import UIKit
import UserNotifications

/// Local notifications for renewals, EMIs, card bills and expiries.
///
/// Notifications name the person and the bank — "HDFC Bank EMI due in 3 days
/// · Priya · ₹45,000" — because a reminder you can't act on without unlocking
/// the app isn't much of a reminder. That text is visible on the lock screen,
/// so Settings keeps a discreet mode that says only that *something* is due,
/// for anyone who'd rather trade the detail away.
@MainActor
final class ReminderScheduler: ObservableObject {

    static let shared = ReminderScheduler()

    /// iOS only keeps 64 pending local notifications per app. Staying under it
    /// deliberately — rather than letting the system silently drop the tail —
    /// means the ones that survive are always the soonest.
    static let maximumPending = 60
    private static let horizonMonths = 18
    /// Per-entry cap, so one monthly EMI can't eat the whole budget.
    private static let maximumPerItem = 18

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduledCount: Int = 0

    private let center = UNUserNotificationCenter.current()
    private let prefix = "vault-reminder-"

    private init() {}

    // MARK: - Permission

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    @discardableResult
    func refreshAuthorizationStatus() async -> UNAuthorizationStatus {
        let status = await center.notificationSettings().authorizationStatus
        authorizationStatus = status
        return status
    }

    /// Asks the system, the first time. Once someone has said no, only the
    /// Settings app can change it — hence `openSystemSettings`.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let status = await refreshAuthorizationStatus()
        if status == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await refreshAuthorizationStatus()
            return granted
        }
        return isAuthorized
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Scheduling

    private var remindersEnabled: Bool {
        UserDefaults.standard.bool(forKey: "settings.remindersEnabled")
    }

    private var detailedNotifications: Bool {
        UserDefaults.standard.bool(forKey: "settings.detailedNotifications")
    }

    func reschedule(for items: [VaultItem]) {
        Task { await rescheduleAsync(for: items) }
    }

    func rescheduleAsync(for items: [VaultItem]) async {
        await refreshAuthorizationStatus()

        guard remindersEnabled, isAuthorized else {
            await clearScheduled()
            return
        }

        let planned = plan(for: items)

        // Replace ours wholesale; anything the app didn't schedule is left alone.
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )

        for occurrence in planned {
            let request = UNNotificationRequest(
                identifier: identifier(for: occurrence),
                content: content(for: occurrence),
                trigger: trigger(for: occurrence)
            )
            try? await center.add(request)
        }

        scheduledCount = planned.count
        await updateBadge(for: items)
    }

    /// Every upcoming reminder across the whole vault, soonest first, trimmed
    /// to what iOS will actually hold.
    private func plan(for items: [VaultItem]) -> [Occurrence] {
        let now = Date()
        var occurrences: [Occurrence] = []

        for item in items {
            guard let anchor = item.reminderDate else { continue }

            let dueDates = item.reminderRepeat.dueDates(
                from: anchor,
                notBefore: Calendar.current.startOfDay(for: now),
                horizonMonths: Self.horizonMonths,
                limit: Self.maximumPerItem
            )

            let settled = item.lastPaidDueDate.map { Calendar.current.startOfDay(for: $0) }

            for due in dueDates {
                // An instalment already marked paid shouldn't ring.
                if let settled, Calendar.current.startOfDay(for: due) <= settled { continue }
                guard let fireDate = fireDate(due: due, leadDays: item.reminderLeadDays), fireDate > now else { continue }
                occurrences.append(Occurrence(item: item, dueDate: due, fireDate: fireDate))
            }
        }

        return occurrences
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.maximumPending)
            .map { $0 }
    }

    /// Reminders land at 9am local, `leadDays` before the due date.
    private func fireDate(due: Date, leadDays: Int) -> Date? {
        let calendar = Calendar.current
        guard let shifted = calendar.date(byAdding: .day, value: -max(leadDays, 0), to: due) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: shifted)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components)
    }

    private func trigger(for occurrence: Occurrence) -> UNCalendarNotificationTrigger {
        // Each occurrence is its own one-shot request. A repeating trigger
        // can't express "every 3 months", and a monthly one keyed on day 31
        // silently skips the short months.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: occurrence.fireDate
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func identifier(for occurrence: Occurrence) -> String {
        let stamp = Int(occurrence.dueDate.timeIntervalSince1970)
        return "\(prefix)\(occurrence.item.id.uuidString)-\(stamp)"
    }

    private func clearScheduled() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )
        scheduledCount = 0
        try? await center.setBadgeCount(0)
    }

    func cancelAll() {
        Task {
            await clearScheduled()
            center.removeAllPendingNotificationRequests()
        }
    }

    /// The app icon carries the count of things already overdue.
    private func updateBadge(for items: [VaultItem]) async {
        let overdue = items.filter { ($0.daysUntilReminder ?? 1) < 0 }.count
        try? await center.setBadgeCount(overdue)
    }

    // MARK: - What the notification says

    private struct Occurrence {
        let item: VaultItem
        let dueDate: Date
        let fireDate: Date
    }

    private func content(for occurrence: Occurrence) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = occurrence.item.category.rawValue

        guard detailedNotifications else {
            content.title = discreetTitle(for: occurrence.item.category)
            content.body = "Open Vault to see the details."
            return content
        }

        let item = occurrence.item
        let institution = institution(of: item)
        let when = whenPhrase(from: occurrence.fireDate, to: occurrence.dueDate)

        // "HDFC Bank EMI due in 3 days"
        content.title = [institution, action(for: item.category), when]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // "Home loan"
        content.subtitle = item.displayTitle

        // "Priya · ₹45,000 · due 5 Sep"
        var detail: [String] = []
        if !item.holder.isEmpty { detail.append(item.holder) }
        if let amount = amount(of: item) { detail.append(amount) }
        detail.append("due \(occurrence.dueDate.formatted(.dateTime.day().month(.abbreviated)))")
        content.body = detail.joined(separator: " · ")

        return content
    }

    /// The bank, insurer or lender the entry belongs to.
    private func institution(of item: VaultItem) -> String {
        if !item.subtitle.isEmpty { return item.subtitle }
        return item.value(forLabel: CategoryTemplates.institutionField(for: item.category)) ?? ""
    }

    private func amount(of item: VaultItem) -> String? {
        guard let label = CategoryTemplates.amountField(for: item.category),
              let raw = item.value(forLabel: label)
        else { return nil }
        return MoneyValue.display(raw)
    }

    private func action(for category: ItemCategory) -> String {
        switch category {
        case .loan: "EMI due"
        case .insurance: "policy renewal"
        case .card: "card payment due"
        case .investment: "matures"
        case .identity: "expires"
        case .bankAccount: "reminder"
        default: "reminder"
        }
    }

    private func whenPhrase(from fireDate: Date, to dueDate: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: fireDate),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? 0

        switch days {
        case ..<0: return "was due"
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }

    private func discreetTitle(for category: ItemCategory) -> String {
        switch category {
        case .insurance: "A policy is coming up for renewal"
        case .investment: "An investment is reaching maturity"
        case .loan: "An EMI is due soon"
        case .card: "A card payment is due soon"
        case .identity: "A document is expiring soon"
        default: "You have a reminder due"
        }
    }

    // MARK: - Preview shown in Settings

    /// Renders what the next real notification will look like, so the choice
    /// between named and discreet is made by seeing it, not guessing.
    func previewLines(for items: [VaultItem]) -> (title: String, subtitle: String, body: String)? {
        guard let next = plan(for: items).first else { return nil }
        let content = content(for: next)
        return (content.title, content.subtitle, content.body)
    }
}
