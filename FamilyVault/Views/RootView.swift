import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: VaultSession
    @StateObject private var screenProtection = ScreenProtectionMonitor.shared

    @State private var isDeviceLikelyCompromised = false
    @State private var didDismissCompromiseBanner = false

    private var isUnlocked: Bool {
        if case .unlocked = session.phase { return true }
        return false
    }

    /// A recording/mirroring session is just as much a leak as the app
    /// switcher snapshot the existing shield already covers, so it reuses
    /// the exact same `PrivacyShield` and the exact same condition shape.
    private var isScreenShieldNeeded: Bool {
        isUnlocked && (session.isPrivacyShieldUp || screenProtection.isBeingRecorded)
    }

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

            if isUnlocked && isDeviceLikelyCompromised && !didDismissCompromiseBanner {
                VStack {
                    CompromisedDeviceBanner {
                        didDismissCompromiseBanner = true
                    }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isScreenShieldNeeded {
                PrivacyShield()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isScreenShieldNeeded)
        .animation(.easeInOut(duration: 0.2), value: didDismissCompromiseBanner)
        .task {
            screenProtection.startMonitoring()
            // File I/O and (rarely) a main-thread hop for the Cydia URL
            // check — keep it off the main actor so launch never hitches.
            let compromised = await Task.detached(priority: .utility) {
                JailbreakDetector.isLikelyCompromised
            }.value
            isDeviceLikelyCompromised = compromised
        }
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

/// Small, dismissible, non-blocking notice — the whole point is that a
/// possibly-tampered device still gets to see its own vault, just informed.
private struct CompromisedDeviceBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("This iPhone shows signs of a modified operating system, which can make on-device encryption easier to bypass.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
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
