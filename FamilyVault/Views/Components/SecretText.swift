import SwiftUI

/// A field value that stays masked until tapped, with copy-to-clipboard and —
/// when the setting is on — a Face ID check before anything is shown.
struct SecretValueView: View {
    var value: String
    var kind: FieldKind
    var clipboardClearSeconds: Int
    var requireBiometricsToReveal: Bool = false

    @State private var isRevealed = false
    @State private var didCopy = false
    @State private var isAuthenticating = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(displayValue)
                .font(monospaced ? .body.monospaced() : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)

            if kind.isSecret {
                Button(action: toggleReveal) {
                    if isAuthenticating {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isRevealed ? "Hide value" : "Reveal value")
            }

            Button(action: copy) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(didCopy ? Color.green : Color.secondary)
            .accessibilityLabel("Copy")
        }
    }

    private var monospaced: Bool {
        kind.isSecret && (!isRevealed || value.allSatisfy { $0.isNumber || $0 == " " })
    }

    private var displayValue: String {
        if kind.isSecret && !isRevealed {
            return String(repeating: "•", count: min(max(value.count, 4), 16))
        }
        if kind == .money { return MoneyValue.display(value) }
        return value
    }

    private func toggleReveal() {
        // Guards against a double-tap re-entering this while a Face ID prompt
        // from the first tap is still on screen — without this, two concurrent
        // `evaluatePolicy` calls can stack.
        guard !isAuthenticating else { return }
        guard !isRevealed else {
            withAnimation(.easeInOut(duration: 0.15)) { isRevealed = false }
            return
        }
        guard requireBiometricsToReveal else {
            withAnimation(.easeInOut(duration: 0.15)) { isRevealed = true }
            return
        }
        isAuthenticating = true
        Task {
            let allowed = await BiometricGate.authenticate(reason: "Show this value")
            isAuthenticating = false
            if allowed { withAnimation(.easeInOut(duration: 0.15)) { isRevealed = true } }
        }
    }

    private func copy() {
        // Copying a hidden secret is allowed — the value goes to the clipboard,
        // not to the screen — but the same Face ID rule applies when it is on.
        // Shares `isAuthenticating` with the reveal flow so a double-tap here
        // (or a tap here while a reveal prompt is already in flight) can't
        // trigger a second, overlapping biometric prompt.
        guard !isAuthenticating else { return }
        guard !requireBiometricsToReveal || isRevealed else {
            isAuthenticating = true
            Task {
                let allowed = await BiometricGate.authenticate(reason: "Copy this value")
                isAuthenticating = false
                guard allowed else { return }
                performCopy()
            }
            return
        }
        performCopy()
    }

    private func performCopy() {
        ClipboardService.copy(value, clearAfter: clipboardClearSeconds)
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { didCopy = false }
        }
    }
}

/// One labelled row inside an item's detail view.
struct FieldRow: View {
    var field: ItemField
    var clipboardClearSeconds: Int
    var requireBiometricsToReveal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecretValueView(
                value: field.value,
                kind: field.kind,
                clipboardClearSeconds: clipboardClearSeconds,
                requireBiometricsToReveal: requireBiometricsToReveal
            )
            let actions = FieldAction.actions(for: field)
            if !actions.isEmpty {
                FieldActionBar(actions: actions)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}
