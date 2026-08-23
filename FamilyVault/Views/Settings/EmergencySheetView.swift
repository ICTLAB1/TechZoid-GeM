import SwiftUI

struct EmergencySheetView: View {
    @EnvironmentObject private var store: VaultStore

    @State private var maskSecrets = true
    @State private var includeNotes = false
    @State private var preparedFor = ""
    @State private var selected: Set<ItemCategory> = Set(ItemCategory.allCases)
    @State private var generated: BackupFile?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("A one-page printable summary of what exists and who to call — for a nominee, a parent, or a safe. It does not need the app or the passphrase to read.")
                    .font(.subheadline)
            }

            Section {
                TextField("Prepared for (optional)", text: $preparedFor)
                Toggle("Hide account & policy numbers", isOn: $maskSecrets)
                Toggle("Include notes", isOn: $includeNotes)
            } header: {
                Text("Contents")
            } footer: {
                if maskSecrets {
                    Text("Numbers print as ••••3417 — enough to recognise an account, not enough to use it.")
                } else {
                    Text("⚠️ The PDF will contain full account numbers, policy numbers and passwords in plain readable text. Anyone who picks it up can use them. Print it once, keep it in a safe, and don't email it.")
                        .foregroundStyle(.red)
                }
            }

            Section("Include") {
                ForEach(ItemCategory.allCases) { category in
                    Toggle(isOn: Binding(
                        get: { selected.contains(category) },
                        set: { isOn in
                            if isOn { selected.insert(category) } else { selected.remove(category) }
                        }
                    )) {
                        Label(category.title, systemImage: category.icon)
                    }
                }
            }

            Section {
                Button {
                    generate()
                } label: {
                    HStack {
                        Label("Create PDF", systemImage: "doc.richtext")
                        Spacer()
                        if isWorking { ProgressView() }
                    }
                }
                .disabled(selected.isEmpty || isWorking || store.items.isEmpty)
            }
        }
        .navigationTitle("Emergency sheet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $generated) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Emergency sheet", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func generate() {
        isWorking = true
        var options = EmergencySheet.Options()
        options.maskSecrets = maskSecrets
        options.includeNotes = includeNotes
        options.categories = selected
        options.preparedFor = preparedFor.trimmingCharacters(in: .whitespaces)

        let items = store.items
        Task {
            let url = EmergencySheet.render(items: items, options: options)
            isWorking = false
            if let url {
                generated = BackupFile(url: url)
            } else {
                errorMessage = "The PDF could not be created."
            }
        }
    }
}
