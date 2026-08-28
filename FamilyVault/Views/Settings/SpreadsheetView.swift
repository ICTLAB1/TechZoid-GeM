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
    /// Set when the chosen file looks like a Google or Apple password export.
    @State private var isPasswordExport = false
    @State private var noteColumn: Int?
    @State private var titleColumn: Int?

    @State private var maskOnExport = true
    @State private var exportFile: BackupFile?
    @State private var isExporting = false
    @State private var isExportingPayments = false
    @State private var isExportingActivity = false

    var body: some View {
        Form {
            Section {
                Button {
                    isPickingFile = true
                } label: {
                    Label("Choose a CSV file", systemImage: "tablecells")
                }

                if let preview {
                    if isPasswordExport {
                        Label(
                            "This looks like a saved-passwords export. The columns have been matched to login fields, and each row will become a Login entry.",
                            systemImage: "key.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

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

            Section {
                Button {
                    runPaymentsExport()
                } label: {
                    HStack {
                        Label("Export payments as CSV", systemImage: "indianrupeesign.circle")
                        Spacer()
                        if isExportingPayments { ProgressView() }
                    }
                }
                .disabled(store.items.allSatisfy { $0.payments.isEmpty } || isExportingPayments)

                Button {
                    runActivityExport()
                } label: {
                    HStack {
                        Label("Export activity log as CSV", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        if isExportingActivity { ProgressView() }
                    }
                }
                .disabled(store.recentActivity().isEmpty || isExportingActivity)
            } header: {
                Text("Records")
            } footer: {
                Text("Separate spreadsheets of every payment you've logged and every change made to the vault, useful for reconciling with bank statements or reviewing who changed what.")
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
                    let raw = try SpreadsheetService.preview(from: url)
                    // A saved-passwords export names its columns its own way.
                    // Recognising it here means the user picks a file and
                    // presses import, rather than renaming columns by hand.
                    if SpreadsheetService.looksLikePasswordExport(raw.headers) {
                        let normalised = SpreadsheetService.normalisedForPasswordImport(raw)
                        preview = normalised.preview
                        noteColumn = normalised.noteColumn
                        titleColumn = normalised.titleColumn
                        isPasswordExport = true
                        importCategory = .login
                    } else {
                        preview = raw
                        noteColumn = nil
                        titleColumn = nil
                        isPasswordExport = false
                    }
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
        let items = SpreadsheetService.items(
            from: preview,
            category: importCategory,
            holder: importHolder,
            noteColumn: noteColumn,
            titleColumn: titleColumn
        )
        for item in items { store.save(item) }
        self.preview = nil
        self.noteColumn = nil
        self.titleColumn = nil
        self.isPasswordExport = false
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

    private func runPaymentsExport() {
        isExportingPayments = true
        let csv = SpreadsheetService.paymentsCSV(for: store.items)
        do {
            let stamp = Date().formatted(.iso8601.year().month().day())
            let url = try SpreadsheetService.write(csv: csv, filename: "Payments-\(stamp).csv")
            exportFile = BackupFile(url: url)
        } catch {
            message = error.localizedDescription
        }
        isExportingPayments = false
    }

    private func runActivityExport() {
        isExportingActivity = true
        let csv = SpreadsheetService.activityCSV(for: store.recentActivity())
        do {
            let stamp = Date().formatted(.iso8601.year().month().day())
            let url = try SpreadsheetService.write(csv: csv, filename: "Activity-\(stamp).csv")
            exportFile = BackupFile(url: url)
        } catch {
            message = error.localizedDescription
        }
        isExportingActivity = false
    }
}
