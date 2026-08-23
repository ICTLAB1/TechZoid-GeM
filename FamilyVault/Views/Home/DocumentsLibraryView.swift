import SwiftUI

/// Every document in the vault in one place — policy bonds, statements,
/// certificates, the rent agreement — each one shareable in two taps.
struct DocumentsLibraryView: View {
    @EnvironmentObject private var store: VaultStore

    @State private var query = ""
    @State private var categoryFilter: ItemCategory?
    @State private var viewing: ItemAttachment?
    @State private var sharing: BackupFile?
    @State private var shareError: String?
    @State private var isAddingStandalone = false

    var body: some View {
        Group {
            if store.attachmentCount == 0 {
                EmptyStateView(
                    icon: "doc.on.doc",
                    title: "No documents yet",
                    message: "Scan or attach a policy bond, a statement, a certificate — anything worth keeping. They're encrypted like everything else, and you can send one on at any time.",
                    actionTitle: "Add a document",
                    action: { isAddingStandalone = true }
                )
            } else {
                List {
                    if !usedCategories.isEmpty {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    chip(title: "All", active: categoryFilter == nil) { categoryFilter = nil }
                                    ForEach(usedCategories) { category in
                                        chip(title: category.title, active: categoryFilter == category) {
                                            categoryFilter = (categoryFilter == category) ? nil : category
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                        .listRowBackground(Color.clear)
                    }

                    if documents.isEmpty {
                        Section {
                            Text("Nothing matches.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            ForEach(documents, id: \.attachment.id) { entry in
                                DocumentRow(entry: entry) { viewing = entry.attachment }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            share(entry.attachment)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        .tint(Theme.accent)
                                    }
                            }
                        } footer: {
                            Text("\(store.attachmentCount) document\(store.attachmentCount == 1 ? "" : "s"), encrypted on both phones. Swipe a row to send one on.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "File name, insurer, anything inside")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAddingStandalone = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a personal document")
            }
        }
        .sheet(item: $viewing) { attachment in
            AttachmentViewer(attachment: attachment)
        }
        .sheet(item: $sharing) { file in
            ShareSheet(activityItems: [file.url])
        }
        .sheet(isPresented: $isAddingStandalone) {
            ItemEditorView(item: CategoryTemplates.newItem(category: .document), isNew: true)
        }
        .alert("Share", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
    }

    private var usedCategories: [ItemCategory] {
        let present = Set(store.allDocuments().map(\.item.category))
        return ItemCategory.allCases.filter { present.contains($0) }
    }

    /// Searches file names *and* the text read out of each document, which is
    /// how you find "the policy that mentions cashless" without remembering
    /// what the file was called.
    private var documents: [(item: VaultItem, attachment: ItemAttachment)] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.allDocuments().filter { entry in
            if let categoryFilter, entry.item.category != categoryFilter { return false }
            guard !trimmed.isEmpty else { return true }
            if entry.attachment.filename.lowercased().contains(trimmed) { return true }
            if entry.item.displayTitle.lowercased().contains(trimmed) { return true }
            if entry.item.subtitle.lowercased().contains(trimmed) { return true }
            return entry.attachment.extractedText?.lowercased().contains(trimmed) ?? false
        }
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(active ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Theme.accent : Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Decrypts to a temporary file purely so the share sheet has something to
    /// hand over — the only moment a document exists in the clear, and only
    /// because you asked to send it somewhere.
    private func share(_ attachment: ItemAttachment) {
        do {
            let data = try store.attachmentData(attachment)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(attachment.filename)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            sharing = BackupFile(url: url)
        } catch {
            shareError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct DocumentRow: View {
    var entry: (item: VaultItem, attachment: ItemAttachment)
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                CategoryBadge(category: entry.item.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.attachment.filename)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts = [entry.item.displayTitle]
        if let pages = entry.attachment.pageCount, pages > 1 { parts.append("\(pages) pages") }
        parts.append(entry.attachment.sizeDescription)
        parts.append(entry.attachment.addedAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}
