import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Scan anything, and let the app work out what it is.
///
/// The other way round from the rest of the app: instead of choosing a category
/// and then filling a form, you put a document in front of the camera and the
/// entry — the right kind, with its fields already filled — comes out the other
/// end. What the document is gets decided by `DocumentClassifier`; what it says
/// by `DocumentFieldExtractor`.
///
/// The one thing it will not do is guess quietly. A document it cannot place
/// confidently stops and asks rather than filing a policy under "Bank account".
struct QuickScanView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    /// False when this is a tab root rather than a sheet — a tab has nothing
    /// to dismiss, and a "Close" button on it would go nowhere.
    var showsDismissButton: Bool = true

    /// Opens the finished entry. Called after this sheet closes.
    var onOpenEntry: (VaultItem) -> Void

    @State private var isScanning = false
    @State private var isCapturing = false
    @State private var isImportingFile = false
    @State private var isPickingPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []

    @State private var progress: String?
    @State private var errorMessage: String?

    /// Captured, but the classifier wasn't sure enough to file it unasked.
    @State private var pending: CapturedDocument?
    @State private var suggestion: DocumentClassifier.Verdict?

    @State private var outcome: Outcome?

    struct Outcome {
        var item: VaultItem
        var category: ItemCategory
        var filled: [String]
        var uncertain: [String]
        var attachedAs: String?
        /// The plastic card path: read, used, and deliberately not filed.
        var cardImageDiscarded: Bool
    }

    var body: some View {
        NavigationStack {
            Form {
                if let outcome {
                    outcomeSections(outcome)
                } else if let pending {
                    categoryChoiceSections(for: pending)
                } else {
                    captureSections
                }
            }
            .navigationTitle(outcome == nil ? "Scan anything" : "Done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(outcome == nil ? "Cancel" : "Close") { dismiss() }
                    }
                }
            }
            .alert("Scan", isPresented: alertBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Choosing what to scan

    @ViewBuilder
    private var captureSections: some View {
        Section {
            if DocumentScannerView.isAvailable {
                Button {
                    isScanning = true
                } label: {
                    Label("Scan with the camera", systemImage: "doc.viewfinder")
                }
                .fullScreenCover(isPresented: $isScanning) {
                    DocumentScannerView(
                        onFinish: { pages in
                            isScanning = false
                            Task { await intake { try await DocumentIntake.scanned(pages) } }
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
                            Task { await intake { try await DocumentIntake.captured(image) } }
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
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await intake { try await DocumentIntake.imported(url) } }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }

            Button {
                isPickingPhotos = true
            } label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            .photosPicker(isPresented: $isPickingPhotos, selection: $photoSelection, maxSelectionCount: 1, matching: .images)
            .onChange(of: photoSelection) { _, selection in
                guard let picked = selection.first else { return }
                Task {
                    photoSelection = []
                    guard let document = await DocumentIntake.picked(picked, index: 0) else {
                        errorMessage = "That photo couldn't be read."
                        return
                    }
                    await handle(document)
                }
            }
        } header: {
            Text("Put a document in")
        } footer: {
            Text("Vault reads it on this iPhone, works out whether it's a policy, a card statement, a passbook, a deed or an ID, then creates the entry with every field it can find already filled. Nothing is sent anywhere to be read.")
        }

        if let progress {
            Section {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(progress).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - When it isn't sure

    @ViewBuilder
    private func categoryChoiceSections(for document: CapturedDocument) -> some View {
        Section {
            Text(suggestionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("What is this?")
        }

        Section {
            ForEach(ItemCategory.allCases) { category in
                Button {
                    Task { await create(category: category, from: document) }
                } label: {
                    HStack(spacing: 12) {
                        CategoryBadge(category: category, size: 26)
                        Text(category.singular)
                        Spacer()
                        if suggestion?.category == category {
                            Text("likely").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Text("Pick one and the fields get filled from what the document says.")
        }
    }

    private var suggestionText: String {
        guard let suggestion else {
            return "The words on this one don't match any kind of document clearly enough to choose for you."
        }
        return "It looks most like a \(suggestion.category.singular.lowercased()), but not clearly enough to file it without asking."
    }

    // MARK: - What came out

    @ViewBuilder
    private func outcomeSections(_ outcome: Outcome) -> some View {
        Section {
            HStack(spacing: 12) {
                CategoryBadge(category: outcome.category, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.item.title.isEmpty ? outcome.category.singular : outcome.item.title)
                        .font(.headline)
                    if !outcome.item.subtitle.isEmpty {
                        Text(outcome.item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Created a \(outcome.category.singular.lowercased()) entry")
        }

        if !outcome.filled.isEmpty {
            Section {
                ForEach(outcome.filled, id: \.self) { label in
                    Label(label, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Filled in — \(outcome.filled.count)")
            }
        }

        if !outcome.uncertain.isEmpty {
            Section {
                ForEach(outcome.uncertain, id: \.self) { label in
                    Label(label, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Filled in, but read less clearly")
            } footer: {
                Text("Worth checking these against the document before you rely on them.")
            }
        }

        Section {
            if let attachedAs = outcome.attachedAs {
                Label(attachedAs, systemImage: "paperclip")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if outcome.cardImageDiscarded {
                Label(
                    "The card was read and the picture discarded — the number and the image are never kept together.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }

        Section {
            Button {
                let item = outcome.item
                if showsDismissButton { dismiss() }
                onOpenEntry(item)
                // A tab stays put, so clear the result — otherwise coming back
                // to Scan shows the last scan's summary as though it were new.
                if !showsDismissButton { self.outcome = nil }
            } label: {
                Text("Open the entry").fontWeight(.semibold)
            }

            Button("Scan another") {
                self.outcome = nil
                pending = nil
                suggestion = nil
            }
        } footer: {
            if outcome.filled.isEmpty && outcome.uncertain.isEmpty {
                if outcome.cardImageDiscarded {
                    Text("The card was recognised but its embossed digits couldn't be read — that happens in low light or at an angle. Open the entry to type them, or scan again with the card flat and filling the frame.")
                } else {
                    Text("Nothing could be read off this one, so the entry is empty apart from the document itself. Open it and fill in what you need.")
                }
            }
        }
    }

    // MARK: - Work

    /// Runs one capture, turning a thrown intake failure into a message.
    private func intake(_ capture: () async throws -> CapturedDocument) async {
        progress = "Reading the document…"
        defer { progress = nil }
        do {
            let document = try await capture()
            await handle(document)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handle(_ document: CapturedDocument) async {
        progress = "Working out what this is…"
        defer { progress = nil }

        // The plastic card is its own thing: short, no prose, a Luhn-valid
        // number. Nothing else reads like that, so it settles the category on
        // its own without going near the classifier.
        if DocumentIntake.plasticCardFields(in: document.text) != nil {
            await create(category: .card, from: document)
            return
        }

        let verdict = DocumentClassifier.classify(document.text)
        if let verdict, verdict.isConfident {
            await create(category: verdict.category, from: document)
        } else {
            suggestion = verdict
            pending = document
        }
    }

    private func create(category: ItemCategory, from document: CapturedDocument) async {
        progress = "Filling in the details…"
        defer { progress = nil }

        var item = CategoryTemplates.newItem(category: category)

        // A picture of the plastic is never filed, even when the number itself
        // couldn't be read — recognisable as a card is enough to withhold it.
        let isCardFace = category == .card && DocumentIntake.isPlasticCardFace(document.text)
        let plastic = category == .card ? DocumentIntake.plasticCardFields(in: document.text) : nil
        let candidates = plastic ?? DocumentFieldExtractor.fields(in: document.text, category: category)
        let result = DocumentIntake.fill(&item, from: candidates)

        if item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            item.title = item.subtitle.isEmpty
                ? "\(category.singular) · \(Date().formatted(date: .abbreviated, time: .omitted))"
                : item.subtitle
        }

        store.save(item)

        var attachedAs: String?
        if !isCardFace {
            do {
                try store.addAttachment(
                    data: document.data,
                    filename: document.filename,
                    typeIdentifier: document.typeIdentifier,
                    to: item,
                    extractedText: document.text.isEmpty ? nil : document.text,
                    pageCount: document.pageCount
                )
                attachedAs = "Attached \(document.filename)"
            } catch {
                // The entry and its fields are already saved; only the file
                // failed to file, and saying so beats a silent half-success.
                errorMessage = "The entry was created, but the document couldn't be attached: "
                    + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }

        pending = nil
        suggestion = nil
        outcome = Outcome(
            item: store.item(id: item.id) ?? item,
            category: category,
            filled: result.filled,
            uncertain: result.uncertain,
            attachedAs: attachedAs,
            cardImageDiscarded: isCardFace
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
