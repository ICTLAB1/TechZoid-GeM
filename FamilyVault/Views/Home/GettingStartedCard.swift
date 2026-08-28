import SwiftUI

/// A short checklist that disappears once it's done.
///
/// The three things that make this vault actually work — a first entry, the
/// partner invited, notifications on — are each easy to not get round to, and
/// the app is useless until all three have happened.
struct GettingStartedCard: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminders: ReminderScheduler

    var onAddEntry: () -> Void
    @State private var shareDestination = false
    @State private var notificationDestination = false

    private var hasEntry: Bool { !store.items.isEmpty }
    private var hasPartner: Bool { store.devices.count >= 2 }
    private var hasNotifications: Bool { reminders.isAuthorized && settings.remindersEnabled }

    var isComplete: Bool { hasEntry && hasPartner && hasNotifications }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GETTING STARTED")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                Text("\(completedCount) of 3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            step(
                done: hasEntry,
                title: "Add your first entry",
                detail: "A bank account, a policy, a card — anything.",
                action: onAddEntry
            )

            step(
                done: hasPartner,
                title: "Invite your partner",
                detail: hasPartner ? "Both phones are set up." : "Send the invitation, then tell them the passphrase in person."
            ) { shareDestination = true }

            step(
                done: hasNotifications,
                title: "Turn on notifications",
                detail: hasNotifications ? "Reminders will reach you." : "Without this, no renewal or EMI reminder can reach you."
            ) { notificationDestination = true }
        }
        .padding(Theme.Spacing.content)
        .vaultCard()
        .navigationDestination(isPresented: $shareDestination) { ShareVaultView() }
        .navigationDestination(isPresented: $notificationDestination) { NotificationSettingsView() }
    }

    private var completedCount: Int {
        [hasEntry, hasPartner, hasNotifications].filter { $0 }.count
    }

    private func step(done: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(done ? .regular : .medium))
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !done {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(done)
    }
}
