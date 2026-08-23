import CloudKit
import SwiftUI

struct ShareVaultView: View {
    @EnvironmentObject private var session: VaultSession
    @EnvironmentObject private var store: VaultStore

    @State private var share: CKShare?
    @State private var container: CKContainer?
    @State private var isPresentingShareSheet = false
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var confirmingRevoke = false
    @State private var participants: [String] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(store.isOwner ? "You created this vault" : "You were invited to this vault",
                          systemImage: store.isOwner ? "crown.fill" : "person.crop.circle.badge.checkmark")
                        .font(.subheadline.weight(.medium))
                    Text(store.isOwner
                         ? "Send one invitation to your wife's Apple Account. Only she can open it, and only from her iPhone."
                         : "This vault belongs to your partner's iCloud. You have full read and write access to everything in it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !participants.isEmpty {
                Section("People with access") {
                    ForEach(participants, id: \.self) { name in
                        Label(name, systemImage: "person.fill")
                    }
                }
            }

            if store.isOwner {
                Section {
                    Button {
                        prepareShare()
                    } label: {
                        HStack {
                            Label(participants.count > 1 ? "Manage invitation" : "Send invitation", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isPreparing { ProgressView() }
                        }
                    }
                    .disabled(isPreparing)

                    if participants.count > 1 {
                        Button(role: .destructive) {
                            confirmingRevoke = true
                        } label: {
                            Label("Revoke access", systemImage: "person.badge.minus")
                        }
                    }
                } footer: {
                    Text("The invitation grants access to the encrypted records only. Your partner still has to enter the master passphrase, which is never sent through iCloud or iMessage — tell it to her in person.")
                }
            }

            Section("How it stays private") {
                privacyPoint("Everything is encrypted on this iPhone before it is uploaded.")
                privacyPoint("iCloud stores unreadable ciphertext — Apple holds no key to it.")
                privacyPoint("The master passphrase is never stored or transmitted anywhere.")
                privacyPoint("Only two iPhones can ever be registered to this vault.")
            }
        }
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadShare() }
        .sheet(isPresented: $isPresentingShareSheet) {
            if let share, let container {
                CloudSharingView(
                    share: share,
                    container: container,
                    title: AppConfiguration.vaultShareTitle
                ) {
                    isPresentingShareSheet = false
                    Task { await loadShare() }
                }
                .ignoresSafeArea()
            }
        }
        .alert("Sharing", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Revoke access?", isPresented: $confirmingRevoke, titleVisibility: .visible) {
            Button("Revoke", role: .destructive) {
                Task {
                    do {
                        try await session.revokeSharing()
                        await loadShare()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your partner's iPhone will lose access to the vault. Their local copy stays on their phone until they remove it.")
        }
    }

    private func privacyPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            Text(text).font(.footnote)
        }
    }

    private func loadShare() async {
        guard let existing = await session.currentShare() else {
            participants = []
            return
        }
        share = existing
        participants = existing.participants.compactMap { participant in
            let identity = participant.userIdentity
            if let components = identity.nameComponents {
                let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
                if !name.isEmpty { return participant.role == .owner ? "\(name) (owner)" : name }
            }
            if let email = identity.lookupInfo?.emailAddress { return email }
            if let phone = identity.lookupInfo?.phoneNumber { return phone }
            return participant.role == .owner ? "Owner" : "Invited person"
        }
    }

    private func prepareShare() {
        isPreparing = true
        Task {
            do {
                let (preparedShare, preparedContainer) = try await session.makeShare(title: AppConfiguration.vaultShareTitle)
                share = preparedShare
                container = preparedContainer
                isPreparing = false
                isPresentingShareSheet = true
            } catch {
                isPreparing = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
