import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: VaultSession
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var settings: AppSettings

    @State private var confirmingWipe = false

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
                            Text("\(store.devices.count) of \(VaultStore.maximumDevices)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Security") {
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
                }

                Section {
                    NavigationLink {
                        HealthCheckView()
                    } label: {
                        HStack {
                            Label("Check-up", systemImage: "stethoscope")
                            Spacer()
                            let urgent = store.healthFindings.filter { $0.severity != .suggestion }.count
                            if urgent > 0 {
                                Text("\(urgent)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    NavigationLink {
                        SummaryView()
                    } label: {
                        Label("At a glance", systemImage: "chart.pie")
                    }
                } header: {
                    Text("Review")
                }

                Section {
                    Toggle(isOn: $settings.remindersEnabled) {
                        Label("Renewal & EMI reminders", systemImage: "bell.badge")
                    }
                    .onChange(of: settings.remindersEnabled) { _, enabled in
                        if enabled {
                            store.scheduleSync()
                        } else {
                            ReminderScheduler().cancelAll()
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Notifications only say that something is due — never which policy or which card. Details stay inside the locked app.")
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
                        TrashView()
                    } label: {
                        HStack {
                            Label("Recently Deleted", systemImage: "trash")
                            Spacer()
                            if !store.deletedItems.isEmpty {
                                Text("\(store.deletedItems.count)").foregroundStyle(.secondary)
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
            .confirmationDialog("Remove this vault from this iPhone?", isPresented: $confirmingWipe, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { session.removeVaultFromThisDevice() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need the invitation and the master passphrase to set it up here again.")
            }
        }
    }
}
