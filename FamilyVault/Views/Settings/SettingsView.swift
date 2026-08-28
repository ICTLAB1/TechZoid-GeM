import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var session: VaultSession
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminders: ReminderScheduler

    @State private var confirmingWipe = false

    private var notificationStatusNeedsAttention: Bool {
        settings.remindersEnabled && !reminders.isAuthorized
    }

    private var notificationStatusLabel: String {
        guard settings.remindersEnabled else { return "Off" }
        switch reminders.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "\(reminders.scheduledCount) scheduled"
        case .denied: return "Blocked"
        default: return "Not allowed yet"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Sharing") {
                    NavigationLink {
                        ShareVaultView()
                    } label: {
                        Label(store.isOwner ? "Share with my partner" : "Shared vault", systemImage: "person.2.fill")
                    }

                    NavigationLink {
                        DevicesView()
                    } label: {
                        HStack {
                            Label("Devices", systemImage: "iphone")
                            Spacer()
                            StatusBadge(text: "\(store.devices.count) of \(VaultStore.maximumDevices)")
                        }
                    }

                    NavigationLink {
                        FamilyMembersView()
                    } label: {
                        HStack {
                            Label("Family Members", systemImage: "person.2.crop.square.stack")
                            Spacer()
                            if !store.familyMembers.isEmpty {
                                StatusBadge(text: "\(store.familyMembers.count)")
                            }
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { settings.biometricsEnabled },
                        set: { session.setBiometricsEnabled($0) }
                    )) {
                        Label("Unlock with \(session.biometryName)", systemImage: "faceid")
                    }

                    Toggle(isOn: $settings.requireBiometricsToReveal) {
                        Label("Ask again before showing a secret", systemImage: "eye.trianglebadge.exclamationmark")
                    }

                    Picker(selection: $settings.autoLockSeconds) {
                        ForEach(AppSettings.autoLockChoices, id: \.self) { seconds in
                            Text(AppSettings.autoLockLabel(seconds)).tag(seconds)
                        }
                    } label: {
                        Label("Lock when I leave the app", systemImage: "lock.rotation")
                    }

                    Picker(selection: $settings.clipboardClearSeconds) {
                        Text("After 15 seconds").tag(15)
                        Text("After 45 seconds").tag(45)
                        Text("After 2 minutes").tag(120)
                        Text("Never").tag(0)
                    } label: {
                        Label("Clear copied values", systemImage: "doc.on.clipboard")
                    }

                    NavigationLink {
                        ChangePassphraseView()
                    } label: {
                        Label("Change master passphrase", systemImage: "key.horizontal")
                    }

                    Picker(selection: $settings.wipeAfterFailedAttempts) {
                        ForEach(AppSettings.wipeAttemptChoices, id: \.self) { attempts in
                            Text(AppSettings.wipeAttemptsLabel(attempts)).tag(attempts)
                        }
                    } label: {
                        Label("Erase this copy", systemImage: "exclamationmark.shield")
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text(settings.wipeAfterFailedAttempts == 0
                         ? "Wrong passphrases are simply refused, however many times."
                         : "After \(settings.wipeAfterFailedAttempts) wrong passphrases this iPhone erases its copy of the vault. The other phone keeps everything, and you can set this one up again from the invitation.")
                }

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        HStack {
                            Label("Notifications", systemImage: "bell.badge")
                            Spacer()
                            StatusBadge(
                                text: notificationStatusLabel,
                                emphasis: notificationStatusNeedsAttention ? .urgent : .neutral
                            )
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Renewal, EMI and bill reminders, and whether they name the person and the bank.")
                }

                Section {
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Encrypted backup", systemImage: "externaldrive")
                    }

                    NavigationLink {
                        EmergencySheetView()
                    } label: {
                        Label("Printable emergency sheet", systemImage: "doc.richtext")
                    }

                    NavigationLink {
                        SpreadsheetView()
                    } label: {
                        Label("Import or export a spreadsheet", systemImage: "tablecells")
                    }

                    NavigationLink {
                        TrashView()
                    } label: {
                        HStack {
                            Label("Recently Deleted", systemImage: "trash")
                            Spacer()
                            if !store.deletedItems.isEmpty {
                                StatusBadge(text: "\(store.deletedItems.count)")
                            }
                        }
                    }
                } header: {
                    Text("Backup & recovery")
                }

                Section {
                    Button {
                        session.lock()
                    } label: {
                        Label("Lock vault now", systemImage: "lock.fill")
                    }

                    Button(role: .destructive) {
                        confirmingWipe = true
                    } label: {
                        Label("Remove vault from this iPhone", systemImage: "iphone.slash")
                    }
                } footer: {
                    Text("Removing wipes the local copy and this device's key. The other phone keeps everything, and this iPhone frees up its slot.")
                }

                Section {
                    LabeledContent("Entries", value: "\(store.items.count)")
                    LabeledContent("Documents", value: "\(store.attachmentCount)")
                    LabeledContent("Encryption", value: "AES-256-GCM")
                    LabeledContent("Key derivation", value: "PBKDF2 · 600k rounds")
                    LabeledContent("This device") {
                        Text(store.isOwner ? "Vault owner" : "Invited")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Your data is encrypted on this iPhone before it is stored or synced. The master passphrase never leaves your devices — nobody else, including Apple, can read what's in here.")
                }
            }
            .navigationTitle("Settings")
            .task { await reminders.refreshAuthorizationStatus() }
            .confirmationDialog("Remove this vault from this iPhone?", isPresented: $confirmingWipe, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { session.removeVaultFromThisDevice() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need the invitation and the master passphrase to set it up here again.")
            }
        }
    }
}
