import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var store: VaultStore

    @State private var renaming = false
    @State private var newName = ""
    @State private var pendingRemoval: VaultDevice?

    var body: some View {
        List {
            Section {
                ForEach(store.devices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(device.name)
                                if device.id == store.currentDeviceID {
                                    Text("This iPhone")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text("Added \(device.addedAt.formatted(date: .abbreviated, time: .omitted)) · last opened \(device.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if device.id != store.currentDeviceID {
                            Button(role: .destructive) {
                                pendingRemoval = device
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Registered iPhones")
            } footer: {
                Text("This vault is limited to \(VaultStore.maximumDevices) iPhones — yours and your wife's. A third device is refused even if it has the invitation and the passphrase. Remove a device here to free its slot, for example when replacing a phone.")
            }

            Section {
                Button {
                    newName = store.devices.first { $0.id == store.currentDeviceID }?.name ?? ""
                    renaming = true
                } label: {
                    Label("Rename this iPhone", systemImage: "pencil")
                }
            }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.sync() }
        .alert("Rename this iPhone", isPresented: $renaming) {
            TextField("Device name", text: $newName)
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                store.renameCurrentDevice(to: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let device = pendingRemoval {
                    Task { await store.removeDevice(device) }
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("That phone loses its slot. Its local copy stays until the vault is removed there too.")
        }
    }
}
