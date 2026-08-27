import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Thumbnail strip under an item's details.
struct AttachmentGrid: View {
    var item: VaultItem
    var onOpen: (ItemAttachment) -> Void
    var onDelete: ((ItemAttachment) -> Void)?

    @EnvironmentObject private var store: VaultStore

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(item.attachments) { attachment in
                Button {
                    onOpen(attachment)
                } label: {
                    AttachmentThumbnail(attachment: attachment)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        onOpen(attachment)
                    } label: {
                        Label("Open", systemImage: "eye")
                    }
                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete(attachment)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(16)
        // Redraws when bytes arrive from the other phone.
        .id(store.attachmentRevision)
    }
}

struct AttachmentThumbnail: View {
    var attachment: ItemAttachment
    @EnvironmentObject private var store: VaultStore

    @State private var preview: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else if !store.isAttachmentAvailable(attachment) {
                    VStack(spacing: 4) {
                        Image(systemName: "icloud.and.arrow.down")
                        Text("Downloading").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Image(systemName: attachment.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(attachment.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .task(id: store.attachmentRevision) { await loadPreview() }
    }

    @MainActor
    private func loadPreview() async {
        guard attachment.isImage, preview == nil, store.isAttachmentAvailable(attachment) else { return }
        guard let data = try? store.attachmentData(attachment) else { return }
        preview = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 280, height: 280))
    }
}

/// Full-screen viewer. Decrypted bytes stay in memory — PDFKit and UIImage can
/// both read from `Data`, so no plaintext copy is ever written to disk.
struct AttachmentViewer: View {
    var attachment: ItemAttachment
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var data: Data?
    @State private var loadError: String?
    @State private var exported: BackupFile?

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "Can't open this", message: loadError)
                } else if let data {
                    if attachment.isPDF {
                        PDFDataView(data: data)
                    } else if let image = UIImage(data: data) {
                        ZoomableImage(image: image)
                    } else {
                        EmptyStateView(
                            icon: "doc",
                            title: attachment.filename,
                            message: "\(attachment.sizeDescription) · this file type can't be previewed inside the vault."
                        )
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(attachment.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        exportForSharing()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(data == nil)
                    .accessibilityLabel("Share this document")
                }
            }
            .sheet(item: $exported) { file in
                ShareSheet(activityItems: [file.url])
            }
        }
        .task {
            do {
                data = try store.attachmentData(attachment)
            } catch {
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Sharing needs a real file, so a decrypted copy goes to the temporary
    /// directory under complete file protection and is handed straight to the
    /// share sheet. It is the one moment plaintext touches disk, and only
    /// because the user explicitly asked to send the document somewhere.
    private func exportForSharing() {
        guard let data else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(attachment.filename)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exported = BackupFile(url: url)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct PDFDataView: UIViewRepresentable {
    var data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil { uiView.document = PDFDocument(data: data) }
    }
}

struct ZoomableImage: View {
    var image: UIImage

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
    }
}

/// Add-attachment control: scan with the camera, pick from photos, or take a
/// file from Files. Whatever arrives is read on the device and — where the
/// entry has empty fields — used to fill them in.
struct AttachmentPicker: View {
    var item: VaultItem

    @EnvironmentObject private var store: VaultStore

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isPickingPhotos = false
    @State private var isImportingFile = false
    @State private var isScanning = false
    @State private var isCapturing = false
    @State private var errorMessage: String?
    @State private var progress: String?

    @State private var reviewOutcome: VaultStore.AutoFillOutcome?
    @State private var reviewDocumentName = ""
    @State private var showingReview = false

    private var isCard: Bool { item.category == .card }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if DocumentScannerView.isAvailable {
                    Button {
                        isScanning = true
                    } label: {
                        Label(isCard ? "Scan card" : "Scan document", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Menu {
                    if CameraCaptureView.isAvailable {
                        Button {
                            isCapturing = true
                        } label: {
                            Label("Take a photo", systemImage: "camera")
                        }
                    }
                    Button {
                        isPickingPhotos = true
                    } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        isImportingFile = true
                    } label: {
                        Label("Choose a PDF or file", systemImage: "folder")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }

            if let progress {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text(progress).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
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
        .photosPicker(isPresented: $isPickingPhotos, selection: $photoSelection, maxSelectionCount: 5, matching: .images)
        .onChange(of: photoSelection) { _, selection in
            guard !selection.isEmpty else { return }
            Task { await importPhotos(selection) }
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
        .sheet(isPresented: $showingReview) {
            if let reviewOutcome {
                ImportReviewView(outcome: reviewOutcome, documentName: reviewDocumentName)
            }
        }
        .alert("Attachment", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Scanning

    @MainActor
    private func handleScan(_ pages: [UIImage]) async {
        guard !pages.isEmpty else { return }
        progress = isCard ? "Reading…" : "Building the PDF…"
        defer { progress = nil }

        let text = await TextRecognizer.text(from: pages)

        // On a card entry, work out which of the two things was put in front of
        // the camera. The plastic yields a handful of lines and a checksum-valid
        // number; a statement yields hundreds of lines and a masked one.
        if isCard, looksLikePlastic(text) {
            // A card is read, not filed: storing a photograph of the plastic
            // alongside the numbers would put both in one place for nothing.
            let fields = CardScanner.fields(from: CardScanner.read(text))
            guard !fields.isEmpty else {
                errorMessage = "Couldn't read a card number from that. Try again in better light, with the card flat and filling the frame — or scan the statement instead."
                return
            }
            finish(fields: fields, documentName: "the scanned card")
            return
        }

        progress = "Reading the document…"
        guard let pdf = PDFBuilder.makePDF(from: pages) else {
            errorMessage = "Those pages couldn't be turned into a PDF."
            return
        }

        let name = "Scan \(Date().formatted(date: .abbreviated, time: .omitted)).pdf"
        attach(data: pdf, filename: name, type: UTType.pdf.identifier, text: text, pageCount: pages.count)
        extractAndFill(from: text, documentName: name)
    }

    /// A photo taken here is stored as a photo. It is still read for text, so
    /// a snapshot of a policy page can fill fields in — but it stays an image
    /// rather than being forced into a PDF.
    @MainActor
    private func handleCapture(_ image: UIImage) async {
        progress = "Adding the photo…"
        defer { progress = nil }

        guard let data = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = "That photo couldn't be saved."
            return
        }

        let name = "Photo \(Date().formatted(date: .abbreviated, time: .shortened)).jpg"
        let text = await TextRecognizer.recognize(image) ?? ""
        attach(data: data, filename: name, type: UTType.jpeg.identifier, text: text, pageCount: nil)
        if !text.isEmpty { extractAndFill(from: text, documentName: name) }
    }

    // MARK: - Picking

    @MainActor
    private func importPhotos(_ selection: [PhotosPickerItem]) async {
        progress = "Adding photos…"
        defer { progress = nil; photoSelection = [] }

        for (offset, picked) in selection.enumerated() {
            guard let data = try? await picked.loadTransferable(type: Data.self) else { continue }
            let name = "Photo \(Date().formatted(date: .abbreviated, time: .omitted)) \(offset + 1).jpg"

            var text = ""
            if let image = UIImage(data: data) {
                text = await TextRecognizer.recognize(image) ?? ""
            }
            attach(data: data, filename: name, type: UTType.jpeg.identifier, text: text, pageCount: nil)

            // Only the first image drives the fields; five holiday photos
            // shouldn't each fight over the same policy number.
            if offset == 0, !text.isEmpty { extractAndFill(from: text, documentName: name) }
        }
    }

    @MainActor
    private func importFiles(_ urls: [URL]) async {
        progress = "Reading…"
        defer { progress = nil }

        for (offset, url) in urls.enumerated() {
            let scoped = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if scoped { url.stopAccessingSecurityScopedResource() }

            guard let data else {
                errorMessage = "Could not read \(url.lastPathComponent)."
                continue
            }

            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
            var text = ""
            if type.conforms(to: .pdf) {
                text = await TextRecognizer.text(fromPDF: data)
            } else if type.conforms(to: .image), let image = UIImage(data: data) {
                text = await TextRecognizer.recognize(image) ?? ""
            }

            attach(data: data, filename: url.lastPathComponent, type: type.identifier, text: text, pageCount: nil)
            if offset == 0, !text.isEmpty { extractAndFill(from: text, documentName: url.lastPathComponent) }
        }
    }

    // MARK: - Storing and filling

    private func attach(data: Data, filename: String, type: String, text: String, pageCount: Int?) {
        let current = store.item(id: item.id) ?? item
        do {
            try store.addAttachment(
                data: data,
                filename: filename,
                typeIdentifier: type,
                to: current,
                extractedText: text.isEmpty ? nil : text,
                pageCount: pageCount
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// True when the scan is the card itself rather than a bill about it.
    private func looksLikePlastic(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // A statement runs to hundreds of lines. Anything this short is plastic,
        // and the Luhn check inside CardScanner still has the final say.
        guard lines.count <= 18 else { return false }
        return CardScanner.read(text).number != nil
    }

    private func extractAndFill(from text: String, documentName: String) {
        let candidates = DocumentFieldExtractor.fields(in: text, category: item.category)
        guard !candidates.isEmpty else { return }
        finish(fields: candidates, documentName: documentName)
    }

    private func finish(fields: [ExtractedField], documentName: String) {
        let outcome = store.autoFill(fields, into: item.id)
        guard !outcome.isEmpty else { return }
        reviewOutcome = outcome
        reviewDocumentName = documentName
        showingReview = true
    }
}
