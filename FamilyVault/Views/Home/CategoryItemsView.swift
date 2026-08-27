import SwiftUI

struct CategoryItemsView: View {
    var category: ItemCategory

    @EnvironmentObject private var store: VaultStore
    @State private var isAdding = false
    @State private var justCreatedItem: VaultItem?
    @State private var pendingDeletion: VaultItem?
    @State private var sort: ItemSort = .name
    @State private var holderFilter: String?
    @State private var query = ""

    var body: some View {
        List {
            if !filterHolders.isEmpty && query.isEmpty {
                Section {
                    HolderFilterBar(selection: $holderFilter, holders: filterHolders)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listRowBackground(Color.clear)
            }

            if items.isEmpty {
                Group {
                    if query.isEmpty {
                        EmptyStateView(
                            icon: category.icon,
                            title: "No \(category.title.lowercased()) yet",
                            message: "Add your first \(category.singular.lowercased()) and it will appear on both phones.",
                            actionTitle: "Add \(category.singular)",
                            action: { isAdding = true }
                        )
                    } else {
                        EmptyStateView(
                            icon: "questionmark.folder",
                            title: "Nothing matches",
                            message: "No \(category.title.lowercased()) match “\(query)”."
                        )
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                        ItemRow(item: item)
                            .padding(.horizontal, -16)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            store.toggleFavourite(item)
                        } label: {
                            Label(item.isFavourite ? "Unpin" : "Pin", systemImage: item.isFavourite ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search \(category.title.lowercased())")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(ItemSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add \(category.singular)")
            }
        }
        .sheet(isPresented: $isAdding) {
            ItemEditorView(item: newItem(), isNew: true, onSaved: { justCreatedItem = $0 })
        }
        .sheet(item: $justCreatedItem) { item in
            NavigationStack { ItemDetailView(itemID: item.id) }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.displayTitle ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion { store.delete(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("It moves to Recently Deleted on both phones, and is destroyed for good after \(VaultStore.trashRetentionDays) days.")
        }
    }

    /// Named family members first (so a newly added person is filterable
    /// before they have any entries yet), plus any older free-typed names
    /// still in use that aren't part of the roster.
    private var filterHolders: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for name in store.familyMembers.map(\.name) + store.holders {
            let key = name.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(name)
        }
        return ordered
    }

    private var items: [VaultItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return store.sorted(store.search(trimmed, in: category), by: sort)
        }
        return store.items(in: category, sortedBy: sort, holder: holderFilter)
    }

    /// A new entry inherits the filter you are looking at, which is usually the
    /// person you're adding it for.
    private func newItem() -> VaultItem {
        var item = CategoryTemplates.newItem(category: category)
        if let holderFilter { item.holder = holderFilter }
        return item
    }
}

struct HolderFilterBar: View {
    @Binding var selection: String?
    var holders: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Everyone", isSelected: selection == nil) { selection = nil }
                ForEach(holders, id: \.self) { holder in
                    chip(title: holder, isSelected: selection == holder) {
                        selection = (selection == holder) ? nil : holder
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.accent : Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
