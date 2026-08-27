import SwiftUI

/// First run on the first phone: choose the one passphrase that protects
/// everything. It is never stored or sent anywhere, which also means it can
/// never be reset — so the screen says so plainly.
struct CreateVaultView: View {
    @EnvironmentObject private var session: VaultSession

    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var deviceName = ""
    @State private var acknowledged = false
    @FocusState private var focus: Field?

    private enum Field { case passphrase, confirmation, device }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.accent)
                        Text("Set up your vault")
                            .font(.title2.weight(.semibold))
                        Text("Pick a master passphrase. Everything you store is encrypted with it before it leaves this iPhone, so only the two of you can ever read it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .passphrase)
                        .submitLabel(.next)
                        .onSubmit { focus = .confirmation }

                    SecureField("Confirm passphrase", text: $confirmation)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirmation)
                        .submitLabel(.next)
                        .onSubmit { focus = .device }

                    if !passphrase.isEmpty {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(strengthColor)
                                .frame(width: 8, height: 8)
                            Text(strength.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Master passphrase")
                } footer: {
                    Text("Four unrelated words you both remember beats a short complicated one. Example: *marble-rickshaw-cardamom-92*")
                        .font(.caption)
                }

                Section("Name this iPhone") {
                    TextField("e.g. Abhinav's iPhone", text: $deviceName)
                        .focused($focus, equals: .device)
                        .submitLabel(.done)
                }

                Section {
                    Toggle(isOn: $acknowledged) {
                        Text("I understand this passphrase cannot be recovered. If we both forget it, the data is gone for good.")
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        focus = nil
                        Task { await session.createVault(passphrase: passphrase, deviceName: deviceName) }
                    } label: {
                        HStack {
                            Spacer()
                            if session.isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text("Create vault").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canCreate)
                    .listRowBackground(canCreate ? Theme.accent : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                }

                Section {
                    NavigationLink("My partner already set it up on their phone") {
                        JoinVaultHelpView()
                    }
                    .font(.subheadline)
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var strength: PassphraseStrength { KeyDerivation.strength(of: passphrase) }

    private var strengthColor: Color {
        switch strength {
        case .tooShort, .weak: .red
        case .fair: .orange
        case .strong: .green
        }
    }

    private var canCreate: Bool {
        strength.isAcceptable
            && passphrase == confirmation
            && acknowledged
            && !session.isWorking
    }
}

struct JoinVaultHelpView: View {
    var body: some View {
        List {
            Section {
                Text("The vault is created once, on one phone. The second phone joins by invitation — there is nothing to type in here.")
                    .font(.subheadline)
            }
            Section("On the first iPhone") {
                Label("Open Vault and go to Settings", systemImage: "1.circle.fill")
                Label("Tap “Share with my partner”", systemImage: "2.circle.fill")
                Label("Send the invitation over iMessage", systemImage: "3.circle.fill")
            }
            Section("On this iPhone") {
                Label("Open the invitation link", systemImage: "4.circle.fill")
                Label("Vault opens and asks for the master passphrase", systemImage: "5.circle.fill")
                Label("Enter the same passphrase you both agreed on", systemImage: "6.circle.fill")
            }
            Section {
                Text("The invitation only grants access to the encrypted data. Without the passphrase — which is never sent through iCloud or iMessage — the invitation is worthless on its own.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Joining a vault")
        .navigationBarTitleDisplayMode(.inline)
    }
}
