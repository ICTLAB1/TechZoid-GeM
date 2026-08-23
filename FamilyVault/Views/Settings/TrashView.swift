import SwiftUI

/// Deleting is reversible for a month. Anything here still syncs, so restoring
/// on one phone restores on both.
struct TrashView: View {
    @EnvironmentObject private var store: VaultStore

    @State private var confirmingEmpty = false
    @State private var pendingPurge: VaultItem?

    var body: some View {
        Group {
            if store.deletedItems.isEmpty {
                EmptyStateView(
                    icon: "trash",
                    title: "Nothing deleted",
                    message: "Entries you delete stay here for \(VaultStore.trashRetentionDays) days before they're destroyed for good."
                )
            } else {
                List {
                    Section {
                        ForEach(store.deletedItems) { item in
                            HStack(spacing: 12) {
                                CategoryBadge(category: item.category)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayTitle)
                                    Text(remainingText(for: item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingPurge = item
                                } label: {
                                    Label("Delete now", systemImage: "trash.slash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    store.restore(item)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                        }
                    } footer: {
                        Text("Swipe right to restore, left to destroy immediately.")
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmingEmpty = true
                        } label: {
                            Label("Empty Recently Deleted", systemImage: "trash.slash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Empty Recently Deleted?", isPresented: $confirmingEmpty, titleVisibility: .visible) {
            Button("Destroy \(store.deletedItems.count) entr\(store.deletedItems.count == 1 ? "y" : "ies")", role: .destructive) {
                store.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone, on either phone.")
        }
        .confirmationDialog(
            "Destroy “\(pendingPurge?.displayTitle ?? "")”?",
            isPresented: Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete now", role: .destructive) {
                if let pendingPurge { store.deleteForever(pendingPurge) }
                pendingPurge = nil
            }
            Button("Cancel", role: .cancel) { pendingPurge = nil }
        } message: {
            Text("This cannot be undone, on either phone.")
        }
    }

    private func remainingText(for item: VaultItem) -> String {
        guard let deletedAt = item.deletedAt else { return "Deleted" }
        let expiry = Calendar.current.date(byAdding: .day, value: VaultStore.trashRetentionDays, to: deletedAt) ?? deletedAt
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        if days <= 0 { return "Being destroyed" }
        return "Deleted \(deletedAt.formatted(date: .abbreviated, time: .omitted)) · \(days) day\(days == 1 ? "" : "s") left"
    }
}
