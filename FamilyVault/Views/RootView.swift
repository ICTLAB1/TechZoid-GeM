import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: VaultSession

    var body: some View {
        ZStack {
            switch session.phase {
            case .launching:
                LaunchView()
            case .setup:
                CreateVaultView()
            case .locked:
                UnlockView()
            case .unlocked:
                HomeView()
            case .deviceLimitReached(let devices):
                DeviceLimitView(registered: devices)
            case .unavailable(let reason):
                UnavailableView(reason: reason)
            }

            if session.isPrivacyShieldUp {
                PrivacyShield()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isPrivacyShieldUp)
        .alert("This iPhone's copy was erased", isPresented: $session.didWipeAfterFailures) {
            Button("OK", role: .cancel) { session.didWipeAfterFailures = false }
        } message: {
            Text("Too many wrong passphrases. Nothing is lost — your partner's phone still has everything, and you can set this one up again from a fresh invitation.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { session.errorMessage = nil } },
            message: { Text(session.errorMessage ?? "") }
        )
    }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
    }
}

struct UnavailableView: View {
    var reason: String
    @EnvironmentObject private var session: VaultSession

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Vault can't open yet")
                .font(.title2.weight(.semibold))
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await session.bootstrap() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
    }
}

/// Shown when a third device tries to join — the whole point of the app is
/// that exactly two phones can open it.
struct DeviceLimitView: View {
    var registered: [VaultDevice]
    @EnvironmentObject private var session: VaultSession

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 52))
                .foregroundStyle(.red)
            Text("This vault is already on two iPhones")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("For safety only two devices can ever hold this vault. To use it here, remove one of these from the other phone: Settings → Devices.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                ForEach(registered) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.body)
                            Text("Added \(device.addedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    if device.id != registered.last?.id { Divider().padding(.leading, 46) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))

            Button("Check again") {
                Task { await session.bootstrap() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
    }
}
