import SwiftUI

struct ChangePassphraseView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var updated = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var didSucceed = false

    var body: some View {
        Form {
            Section("Current passphrase") {
                SecureField("Current passphrase", text: $current)
                    .textContentType(.password)
            }

            Section("New passphrase") {
                SecureField("New passphrase", text: $updated)
                    .textContentType(.newPassword)
                SecureField("Confirm new passphrase", text: $confirmation)
                    .textContentType(.newPassword)
                if !updated.isEmpty {
                    Text(KeyDerivation.strength(of: updated).label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    change()
                } label: {
                    HStack {
                        Text("Change passphrase")
                        Spacer()
                        if isWorking { ProgressView() }
                    }
                }
                .disabled(!canSubmit)
            } footer: {
                Text("Your entries are not re-encrypted, so nothing needs to be re-uploaded. Tell your wife the new passphrase — her iPhone will ask for it the next time it locks.")
            }
        }
        .navigationTitle("Master passphrase")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Passphrase", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {
                message = nil
                if didSucceed { dismiss() }
            }
        } message: {
            Text(message ?? "")
        }
    }

    private var canSubmit: Bool {
        !current.isEmpty
            && KeyDerivation.strength(of: updated).isAcceptable
            && updated == confirmation
            && !isWorking
    }

    private func change() {
        isWorking = true
        Task {
            do {
                try await session.changePassphrase(current: current, new: updated)
                didSucceed = true
                message = "Done. Both phones now use the new passphrase."
            } catch {
                didSucceed = false
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isWorking = false
            current = ""; updated = ""; confirmation = ""
        }
    }
}
