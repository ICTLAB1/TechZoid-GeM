import SwiftUI

/// Every number in the vault on one screen, tappable.
///
/// The moment you need a claim helpline is the moment you least want to be
/// hunting through entries for it.
struct ContactsView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var query = ""

    var body: some View {
        Group {
            if cards.isEmpty {
                EmptyStateView(
                    icon: "phone.badge.plus",
                    title: query.isEmpty ? "No numbers saved yet" : "Nothing matches",
                    message: query.isEmpty
                        ? "Fill in the helpline, customer care or agent fields on an entry and they'll gather here."
                        : "No contact matches “\(query)”."
                )
            } else {
                List {
                    ForEach(grouped, id: \.category) { group in
                        Section {
                            ForEach(group.cards) { card in
                                ContactRow(card: card)
                            }
                        } header: {
                            Label(group.category.title, systemImage: group.category.icon)
                        }
                    }
                }
            }
        }
        .navigationTitle("Important numbers")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Insurer, bank, agent…")
    }

    private var cards: [ContactCard] {
        let all = store.contactCards()
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.belongsTo.lowercased().contains(trimmed)
                || $0.label.lowercased().contains(trimmed)
                || $0.number.contains(trimmed)
        }
    }

    private struct ContactGroup {
        var category: ItemCategory
        var cards: [ContactCard]
    }

    private var grouped: [ContactGroup] {
        let all = cards
        return ItemCategory.allCases.compactMap { category in
            let matching = all.filter { $0.category == category }
            return matching.isEmpty ? nil : ContactGroup(category: category, cards: matching)
        }
    }
}

struct ContactRow: View {
    var card: ContactCard
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.belongsTo.isEmpty ? card.label : card.belongsTo)
                        .font(.body)
                    Text("\(card.label) · \(card.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let item = store.item(id: card.itemID) {
                    NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .fixedSize()
                }
            }
            FieldActionBar(actions: [.call(card.number), .message(card.number), .whatsApp(card.number)])
        }
        .padding(.vertical, 4)
    }
}
