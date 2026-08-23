import SwiftUI

/// Marks the instalment an entry is pointing at as settled.
struct RecordPaymentView: View {
    var item: VaultItem

    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var paidOn = Date()
    @State private var note = ""
    @State private var didPrefill = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let due = item.nextDueDate {
                        LabeledContent("Instalment due", value: due.formatted(date: .abbreviated, time: .omitted))
                    }
                    if !item.subtitle.isEmpty {
                        LabeledContent(institutionLabel, value: item.subtitle)
                    }
                    if !item.holder.isEmpty {
                        LabeledContent("Belongs to", value: item.holder)
                    }
                } header: {
                    Text(item.displayTitle)
                }

                Section("Payment") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("Paid on", selection: $paidOn, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }

                Section {
                    Button {
                        store.recordPayment(for: item, amount: amount, paidOn: paidOn, note: note)
                        dismiss()
                    } label: {
                        Text("Mark as paid").fontWeight(.semibold)
                    }
                } footer: {
                    if item.reminderRepeat != .never {
                        Text("The reminder moves on to the next \(item.reminderRepeat.shortLabel.lowercased()) instalment on its own — there's nothing to re-date.")
                    } else {
                        Text("This is logged against the entry. A one-off reminder stays where it is; clear it in Edit if it's done with.")
                    }
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                guard !didPrefill else { return }
                didPrefill = true
                amount = store.suggestedPaymentAmount(for: item)
            }
        }
    }

    private var institutionLabel: String {
        CategoryTemplates.institutionField(for: item.category)
    }
}
