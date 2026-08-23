import SwiftUI
import UniformTypeIdentifiers

struct SpreadsheetView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var settings: AppSettings

    @State private var isPickingFile = false
    @State private var preview: SpreadsheetService.ImportPreview?
    @State private var importCategory: ItemCategory = .insurance
    @State private var importHolder = ""
    @State private var message: String?

    @State private var maskOnExport = true
    @State private var exportFile: BackupFile?
    @State private var isExporting = false

    var body: some View {
        Form {
            Section {
                Button {
                    isPickingFile = true
                } label: {
                    Label("Choose a CSV file", systemImage: "tablecells")
                }

                if let preview {
                    LabeledContent("Rows found", value: "\(preview.rowCount)")
                    LabeledContent("Columns", value: preview.headers.filter { !$0.isEmpty }.joined(separator: ", "))

                    Picker("Add them as", selection: $importCategory) {
                        ForEach(ItemCategory.allCases) { category in
                            Text(category.singular).tag(category)
                        }
                    }
                    TextField("Belongs to (optional)", text: $importHolder)

                    Button {
                        runImport(preview)
                    } label: {
                        Label("Import \(preview.rowCount) entries", systemImage: "square.and.arrow.down")
                            .fontWeight(.semibold)
                    }
                }
            } header: {
                Text("Import")
            } footer: {
                Text("The first row must be column names. Each following row becomes one entry, with a field per column. Columns matching the category's own fields — “Policy number”, “CVV” — arrive already marked secret; anything else that looks sensitive is marked secret too. Dates aren't imported, so set reminders afterwards.")
            }

            Section {
                Toggle("Hide account & policy numbers", isOn: $maskOnExport)
                Button {
                    runExport()
                } label: {
                    HStack {
                        Label("Export all entries as CSV", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting { ProgressView() }
                    }
                }
                .disabled(store.items.isEmpty || isExporting)
            } header: {
                Text("Export")
            } footer: {
                if maskOnExport {
                    Text("A plain spreadsheet of everything, with secret values shown as ••••3417.")
                } else {
                    Text("⚠️ A CSV is plain readable text with no password on it — every card number, PIN and password in the open. For a copy you can actually keep, use the encrypted backup instead.")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Spreadsheet")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    preview = try SpreadsheetService.preview(from: url)
                    importHolder = settings.lastHolder
                } catch {
                    message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Spreadsheet", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func runImport(_ preview: SpreadsheetService.ImportPreview) {
        let items = SpreadsheetService.items(from: preview, category: importCategory, holder: importHolder)
        for item in items { store.save(item) }
        self.preview = nil
        message = items.isEmpty
            ? "No rows had anything in them."
            : "Added \(items.count) \(importCategory.title.lowercased()). Open each one to set its renewal or EMI date."
    }

    private func runExport() {
        isExporting = true
        let csv = SpreadsheetService.csv(for: store.items, maskSecrets: maskOnExport)
        do {
            let stamp = Date().formatted(.iso8601.year().month().day())
            let url = try SpreadsheetService.write(csv: csv, filename: "Vault-\(stamp).csv")
            exportFile = BackupFile(url: url)
        } catch {
            message = error.localizedDescription
        }
        isExporting = false
    }
}
