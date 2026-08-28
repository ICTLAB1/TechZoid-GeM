import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var session: VaultSession

    @State private var passphrase = ""
    @State private var didAttemptBiometrics = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                Text("Vault is locked")
                    .font(.title2.weight(.semibold))
                Text("Enter the master passphrase to open it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SecureField("Master passphrase", text: $passphrase)
                    .textContentType(.password)
                    .focused($isFocused)
                    .submitLabel(.go)
                    .onSubmit(attemptUnlock)
                    .padding(Theme.Spacing.content)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))

                Button(action: attemptUnlock) {
                    HStack {
                        Spacer()
                        if session.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text("Unlock").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(passphrase.isEmpty ? Color.gray.opacity(0.4) : Theme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(passphrase.isEmpty || session.isWorking)

                if session.canUseBiometrics {
                    Button {
                        Task { await session.unlockWithBiometrics() }
                    } label: {
                        Label("Unlock with \(session.biometryName)", systemImage: biometryIcon)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(.container)
        .task {
            guard !didAttemptBiometrics else { return }
            didAttemptBiometrics = true
            if session.canUseBiometrics {
                await session.unlockWithBiometrics()
            } else {
                isFocused = true
            }
        }
    }

    private var biometryIcon: String {
        switch session.biometryName {
        case "Face ID": "faceid"
        case "Touch ID": "touchid"
        case "Optic ID": "opticid"
        default: "lock.open"
        }
    }

    private func attemptUnlock() {
        guard !passphrase.isEmpty else { return }
        let entered = passphrase
        passphrase = ""
        isFocused = false
        Task { await session.unlock(passphrase: entered) }
    }
}
