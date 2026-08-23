import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject private var store: VaultStore

    @State private var exportPassword = ""
    @State private var exportConfirmation = ""
    @State private var includeDocuments = true
    @State private var exportedFile: BackupFile?
    @State private var isExporting = false

    @State private var isImporting = false
    @State private var importURL: URL?
    @State private var importPassword = ""
    @State private var askingImportPassword = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                SecureField("Backup password", text: $exportPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm password", text: $exportConfirmation)
                    .textContentType(.newPassword)
                Toggle("Include documents", isOn: $includeDocuments)
                Button {
                    export()
                } label: {
                    HStack {
                        Label("Create encrypted backup", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting { ProgressView() }
                    }
                }
                .disabled(!canExport)
            } header: {
                Text("Export")
            } footer: {
                Text("One encrypted file holding all \(store.items.count) entries\(includeDocuments && store.attachmentCount > 0 ? " and \(store.attachmentCount) document\(store.attachmentCount == 1 ? "" : "s")" : ""). Keep it somewhere safe — it is your way back in if the iCloud account is ever lost. The file is worthless without this password, which can be different from your master passphrase.")
            }

            Section {
                Button {
                    isImporting = true
                } label: {
                    Label("Restore from a backup file", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Entries from the backup are merged in. Anything already in the vault with a newer change date is left alone.")
            }
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportedFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data, .json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                importURL = urls.first
                askingImportPassword = importURL != nil
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Backup password", isPresented: $askingImportPassword) {
            SecureField("Password", text: $importPassword)
            Button("Restore") { restore() }
            Button("Cancel", role: .cancel) { importPassword = ""; importURL = nil }
        } message: {
            Text("Enter the password this backup file was created with.")
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var canExport: Bool {
        KeyDerivation.strength(of: exportPassword).isAcceptable
            && exportPassword == exportConfirmation
            && !isExporting
    }

    private func export() {
        isExporting = true
        let payload = BackupPayload(
            items: store.items,
            attachments: includeDocuments ? store.attachmentPayloads() : [:]
        )
        let password = exportPassword

        Task {
            do {
                let backup = try await Task.detached(priority: .userInitiated) {
                    try BackupService.makeBackup(payload: payload, password: password)
                }.value
                let url = try BackupService.write(backup)
                exportedFile = BackupFile(url: url)
                exportPassword = ""
                exportConfirmation = ""
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isExporting = false
        }
    }

    private func restore() {
        guard let url = importURL else { return }
        let password = importPassword
        importPassword = ""
        Task {
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try BackupService.restore(from: url, password: password)
                }.value

                var added = 0
                var updatedCount = 0
                for item in payload.items where !item.isDeleted {
                    if let existing = store.item(id: item.id) {
                        guard item.updatedAt > existing.updatedAt else { continue }
                        store.save(item)
                        updatedCount += 1
                    } else {
                        store.save(item)
                        added += 1
                    }
                }

                var documents = 0
                for (key, data) in payload.attachments {
                    guard let id = UUID(uuidString: key) else { continue }
                    store.restoreAttachment(id: id, data: data)
                    documents += 1
                }

                var parts = ["Restored \(added) new entr\(added == 1 ? "y" : "ies")", "updated \(updatedCount)"]
                if documents > 0 { parts.append("and brought back \(documents) document\(documents == 1 ? "" : "s")") }
                message = parts.joined(separator: ", ") + "."
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            importURL = nil
        }
    }
}

struct BackupFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Plain UIActivityViewController — the file goes wherever the user chooses
/// (AirDrop to the other phone, Files, a printer).
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
