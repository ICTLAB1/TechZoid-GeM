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

/// Add-attachment control: camera roll, or any file from Files.
struct AttachmentPicker: View {
    var item: VaultItem
    @EnvironmentObject private var store: VaultStore

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isImportingFile = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 5, matching: .images) {
                Label("Photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)

            Button {
                isImportingFile = true
            } label: {
                Label("Files", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            if isWorking { ProgressView().controlSize(.small) }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
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
        .alert("Attachment", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func importPhotos(_ selection: [PhotosPickerItem]) async {
        isWorking = true
        defer { isWorking = false; photoSelection = [] }

        for (offset, picked) in selection.enumerated() {
            guard let data = try? await picked.loadTransferable(type: Data.self) else { continue }
            let name = "Photo \(Date().formatted(date: .abbreviated, time: .omitted)) \(offset + 1).jpg"
            add(data: data, filename: name, type: UTType.jpeg.identifier)
        }
    }

    private func importFiles(_ urls: [URL]) async {
        isWorking = true
        defer { isWorking = false }

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "Could not read \(url.lastPathComponent)."
                continue
            }
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
            add(data: data, filename: url.lastPathComponent, type: type.identifier)
        }
    }

    private func add(data: Data, filename: String, type: String) {
        // Re-read the item: earlier files in this batch already changed it.
        let current = store.item(id: item.id) ?? item
        do {
            try store.addAttachment(data: data, filename: filename, typeIdentifier: type, to: current)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
