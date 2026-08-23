import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Search your vault",
                        message: "Find anything by bank, insurer, policy number, nominee — even the last four digits of a card."
                    )
                } else if results.isEmpty {
                    EmptyStateView(
                        icon: "questionmark.folder",
                        title: "Nothing found",
                        message: "No entry matches “\(query)”."
                    )
                } else {
                    List(results) { item in
                        NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                            ItemRow(item: item).padding(.horizontal, -16)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Bank, policy, card, nominee…")
        }
    }

    private var results: [VaultItem] { store.search(query) }
}
