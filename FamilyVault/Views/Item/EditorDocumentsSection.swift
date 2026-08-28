import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A document captured while the entry is still being written.
///
/// The editor can be cancelled, and an entry being created does not exist in
/// the store yet, so bytes are held here — in memory, unencrypted, for as long
/// as the sheet is open — and only handed to `VaultStore.addAttachment` once
/// the entry is actually saved. Cancelling drops them, writing nothing.
struct StagedDocument: Identifiable {
    let id = UUID()
    var data: Data
    var filename: String
    var typeIdentifier: String
    var extractedText: String
    var pageCount: Int?

    var type: UTType { UTType(typeIdentifier) ?? .data }

    var icon: String {
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        return "doc"
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

/// Scan-and-attach for the entry editor, for every category.
///
/// Mirrors `AttachmentPicker` on the detail screen, with one difference that
/// drives the whole design: nothing here may touch the store. Documents are
/// staged, and fields read off them are written into the in-flight item rather
/// than through `VaultStore.autoFill`.
struct EditorDocumentsSection: View {
    @Binding var item: VaultItem
    @Binding var staged: [StagedDocument]

    @State private var isScanning = false
    @State private var isCapturing = false
    @State private var isImportingFile = false
    @State private var isPickingPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []

    @State private var progress: String?
    @State private var errorMessage: String?
    @State private var filledLabels: [String] = []
    @State private var uncertainLabels: [String] = []

    private var isCard: Bool { item.category == .card }

    var body: some View {
        actionRows
        stagedRows
        statusRows
    }

    // Split out so the type checker isn't handed one enormous expression.

    @ViewBuilder
    private var actionRows: some View {
        if DocumentScannerView.isAvailable {
            Button {
                isScanning = true
            } label: {
                Label(isCard ? "Scan card" : "Scan document", systemImage: "doc.viewfinder")
            }
            .fullScreenCover(isPresented: $isScanning) {
                DocumentScannerView(
                    onFinish: { pages in
                        isScanning = false
                        Task { await handleScan(pages) }
                    },
                    onCancel: { isScanning = false }
                )
                .ignoresSafeArea()
            }
        }

        if CameraCaptureView.isAvailable {
            Button {
                isCapturing = true
            } label: {
                Label("Take a photo", systemImage: "camera")
            }
            .fullScreenCover(isPresented: $isCapturing) {
                CameraCaptureView(
                    onCapture: { image in
                        isCapturing = false
                        Task { await handleCapture(image) }
                    },
                    onCancel: { isCapturing = false }
                )
                .ignoresSafeArea()
            }
        }

        Button {
            isImportingFile = true
        } label: {
            Label("Upload a PDF or file", systemImage: "folder")
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.pdf, .image, .plainText, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): Task { await importFiles(urls) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Document", isPresented: alertBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }

        Button {
            isPickingPhotos = true
        } label: {
            Label("Choose from Photos", systemImage: "photo.on.rectangle")
        }
        .photosPicker(isPresented: $isPickingPhotos, selection: $photoSelection, maxSelectionCount: 5, matching: .images)
        .onChange(of: photoSelection) { _, selection in
            guard !selection.isEmpty else { return }
            Task { await importPhotos(selection) }
        }
    }

    @ViewBuilder
    private var stagedRows: some View {
        ForEach(staged) { document in
            HStack(spacing: 10) {
                Image(systemName: document.icon)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.filename)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(document.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onDelete { offsets in
            staged.remove(atOffsets: offsets)
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        if let progress {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress).font(.footnote).foregroundStyle(.secondary)
            }
        }

        if !filledLabels.isEmpty {
            Label(
                "Filled in from the document: \(filledLabels.joined(separator: ", ")).",
                systemImage: "wand.and.stars"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if !uncertainLabels.isEmpty {
            Label(
                "Read less clearly — please check: \(uncertainLabels.joined(separator: ", ")).",
                systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
        }
    }

    // MARK: - Scanning

    @MainActor
    private func handleScan(_ pages: [UIImage]) async {
        guard !pages.isEmpty else { return }
        progress = isCard ? "Reading…" : "Building the PDF…"
        defer { progress = nil }

        // A card read off the plastic is used to fill fields and then thrown
        // away, never filed — a picture of the card beside its number would
        // put both in one place for nothing.
        if isCard {
            let text = await TextRecognizer.text(from: pages)
            if DocumentIntake.isPlasticCardFace(text) {
                if let plastic = DocumentIntake.plasticCardFields(in: text) {
                    fill(with: plastic)
                } else {
                    errorMessage = "That's a card, but the embossed digits couldn't be read — try again with the card flat, filling the frame, in even light. The photo isn't kept either way."
                }
                return
            }
        }

        progress = "Reading the document…"
        do {
            let document = try await DocumentIntake.scanned(pages)
            stage(document)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func handleCapture(_ image: UIImage) async {
        progress = "Adding the photo…"
        defer { progress = nil }
        do {
            stage(try await DocumentIntake.captured(image))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Picking

    @MainActor
    private func importPhotos(_ selection: [PhotosPickerItem]) async {
        progress = "Adding photos…"
        defer { progress = nil; photoSelection = [] }

        for (offset, picked) in selection.enumerated() {
            guard let document = await DocumentIntake.picked(picked, index: offset) else { continue }
            // Only the first image drives the fields; five photos shouldn't
            // each fight over the same policy number.
            stage(document, fillFields: offset == 0)
        }
    }

    @MainActor
    private func importFiles(_ urls: [URL]) async {
        progress = "Reading…"
        defer { progress = nil }

        for (offset, url) in urls.enumerated() {
            do {
                stage(try await DocumentIntake.imported(url), fillFields: offset == 0)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Staging and filling

    /// Holds the document until the entry is saved, and fills in what it says.
    private func stage(_ document: CapturedDocument, fillFields: Bool = true) {
        staged.append(
            StagedDocument(
                data: document.data,
                filename: document.filename,
                typeIdentifier: document.typeIdentifier,
                extractedText: document.text,
                pageCount: document.pageCount
            )
        )
        guard fillFields, !document.text.isEmpty else { return }
        fill(with: DocumentFieldExtractor.fields(in: document.text, category: item.category))
    }

    /// Writes what the document said into the entry being edited, under the
    /// shared rules in `DocumentIntake.fill` — empty fields only, and never a
    /// masked reading. Anything read less clearly is still filled in, but
    /// named separately below so it gets checked rather than taken on trust.
    private func fill(with candidates: [ExtractedField]) {
        guard !candidates.isEmpty else { return }
        let result = DocumentIntake.fill(&item, from: candidates)

        for label in result.filled where !filledLabels.contains(label) {
            filledLabels.append(label)
        }
        for label in result.uncertain where !uncertainLabels.contains(label) {
            uncertainLabels.append(label)
        }
    }
}

extension EditorDocumentsSection {
    /// Alert plumbing, kept off the body so the section stays readable.
    var alertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
