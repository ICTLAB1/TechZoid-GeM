import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminders: ReminderScheduler

    @State private var isRequesting = false

    var body: some View {
        Form {
            permissionSection

            Section {
                Toggle(isOn: $settings.remindersEnabled) {
                    Label("Renewal, EMI & bill reminders", systemImage: "bell.badge")
                }
                .onChange(of: settings.remindersEnabled) { _, _ in refresh() }

                Toggle(isOn: $settings.detailedNotifications) {
                    Label("Name the person and the bank", systemImage: "text.bubble")
                }
                .onChange(of: settings.detailedNotifications) { _, _ in refresh() }
            } header: {
                Text("Reminders")
            } footer: {
                Text(settings.detailedNotifications
                     ? "Notifications say whose account it is, which bank or insurer, and how much — so you can act without unlocking. That text shows on the lock screen, where anyone holding the phone can read it."
                     : "Notifications say only that something is due, with no names or amounts. Open the app to see which entry.")
            }

            if let preview = reminders.previewLines(for: store.items) {
                Section {
                    NotificationPreview(title: preview.title, subtitle: preview.subtitle, body: preview.body)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                } header: {
                    Text("Your next reminder will look like this")
                }
            }

            Section {
                LabeledContent("Scheduled", value: "\(reminders.scheduledCount)")
            } footer: {
                Text("iOS holds at most 64 pending reminders per app, so the \(ReminderScheduler.maximumPending) soonest are kept and the list is rebuilt every time you open Vault. With a handful of monthly EMIs that covers well over a year ahead.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reminders.refreshAuthorizationStatus()
            refresh()
        }
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionSection: some View {
        switch reminders.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Section {
                Label {
                    Text("Notifications are on")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }

        case .denied:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text("Notifications are turned off").fontWeight(.medium)
                    } icon: {
                        Image(systemName: "bell.slash.fill").foregroundStyle(.red)
                    }
                    Text("iOS is blocking them, so no renewal or EMI reminder can reach you. Only the Settings app can turn them back on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open iPhone Settings") {
                        reminders.openSystemSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }

        default:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text("Turn on notifications").fontWeight(.medium)
                    } icon: {
                        Image(systemName: "bell.badge.fill").foregroundStyle(Theme.accent)
                    }
                    Text("Without permission, Vault can remind you inside the app but can't reach you when a premium or an EMI is actually due.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        isRequesting = true
                        Task {
                            await reminders.requestAuthorization()
                            refresh()
                            isRequesting = false
                        }
                    } label: {
                        HStack {
                            Text("Allow notifications")
                            if isRequesting { ProgressView().controlSize(.mini) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequesting)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func refresh() {
        Task { await reminders.rescheduleAsync(for: store.items) }
    }
}

/// A mock lock-screen banner, so the privacy trade-off is made by looking at it.
struct NotificationPreview: View {
    var title: String
    var subtitle: String
    var body_: String

    init(title: String, subtitle: String, body: String) {
        self.title = title
        self.subtitle = subtitle
        self.body_ = body
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent.gradient)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(body_)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
