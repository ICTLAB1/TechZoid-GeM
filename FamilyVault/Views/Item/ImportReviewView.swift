import SwiftUI

/// Shown after a document has been read: what went in, and what needs a
/// decision. Nothing here overwrites anything on its own.
struct ImportReviewView: View {
    var outcome: VaultStore.AutoFillOutcome
    var documentName: String

    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var accepted: Set<UUID> = []
    @State private var didUndo = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headline)
                            .font(.headline)
                        Text("Read from **\(documentName)** on this iPhone. Nothing was sent anywhere.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !outcome.applied.isEmpty {
                    Section {
                        ForEach(outcome.applied) { field in
                            ExtractedRow(field: field, state: .applied)
                        }
                    } header: {
                        Label("Filled in", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } footer: {
                        Text("These fields were empty, so the values went straight in.")
                    }
                }

                if !outcome.conflicts.isEmpty {
                    Section {
                        ForEach(outcome.conflicts) { field in
                            Button {
                                toggle(field)
                            } label: {
                                ExtractedRow(
                                    field: field,
                                    state: accepted.contains(field.id) ? .chosen : .conflict(current: currentValue(for: field.label))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label("Already filled in — replace?", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("The document disagrees with what's on the entry. Tap to use the document's version instead.")
                    }
                }

                if !outcome.uncertain.isEmpty {
                    Section {
                        ForEach(outcome.uncertain) { field in
                            Button {
                                toggle(field)
                            } label: {
                                ExtractedRow(
                                    field: field,
                                    state: accepted.contains(field.id) ? .chosen : .uncertain
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label("Not sure about these", systemImage: "questionmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("The layout wasn't clear enough to be confident. Check each one against the document before using it.")
                    }
                }

                if !outcome.applied.isEmpty && !didUndo {
                    Section {
                        Button(role: .destructive) {
                            store.undoAutoFill(outcome)
                            didUndo = true
                        } label: {
                            Label("Undo everything the document filled in", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .navigationTitle("From the document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use \(accepted.count)") {
                        let fields = outcome.needsReview.filter { accepted.contains($0.id) }
                        if let itemID = outcome.itemID { store.applyExtracted(fields, to: itemID) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(accepted.isEmpty)
                }
            }
        }
    }

    private var headline: String {
        let filled = outcome.applied.count
        let pending = outcome.needsReview.count
        if filled > 0 && pending > 0 {
            return "Filled in \(filled) field\(filled == 1 ? "" : "s"), \(pending) need\(pending == 1 ? "s" : "") a look"
        }
        if filled > 0 { return "Filled in \(filled) field\(filled == 1 ? "" : "s")" }
        if pending > 0 { return "\(pending) thing\(pending == 1 ? "" : "s") found — none applied yet" }
        return "Nothing recognisable in this one"
    }

    private func currentValue(for label: String) -> String {
        guard let itemID = outcome.itemID, let item = store.item(id: itemID) else { return "" }
        return item.value(forLabel: label) ?? ""
    }

    private func toggle(_ field: ExtractedField) {
        if accepted.contains(field.id) { accepted.remove(field.id) } else { accepted.insert(field.id) }
    }
}

struct ExtractedRow: View {
    enum State {
        case applied
        case chosen
        case conflict(current: String)
        case uncertain
    }

    var field: ExtractedField
    var state: State

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(field.value)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if case .conflict(let current) = state, !current.isEmpty {
                    Text("currently: \(current)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(field.evidence)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        switch state {
        case .applied: "checkmark.circle.fill"
        case .chosen: "checkmark.circle.fill"
        case .conflict: "circle"
        case .uncertain: "circle"
        }
    }

    private var tint: Color {
        switch state {
        case .applied, .chosen: .green
        case .conflict: .orange
        case .uncertain: .secondary
        }
    }
}
