import SwiftUI

/// Who inherits what — and, more to the point, what has nobody named on it.
///
/// A missing nominee is the single most expensive blank in this whole app: it
/// turns a claim into a court matter.
struct NomineesView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        let groups = store.nomineeGroups()

        Group {
            if groups.named.isEmpty && groups.missing.isEmpty {
                EmptyStateView(
                    icon: "person.2.badge.key",
                    title: "Nothing to show yet",
                    message: "Add a policy, investment or account and the nominee picture builds itself."
                )
            } else {
                List {
                    if !groups.missing.isEmpty {
                        Section {
                            ForEach(groups.missing) { item in
                                NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                                    ItemRow(item: item).padding(.horizontal, -16)
                                }
                            }
                        } header: {
                            Label("No nominee named", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } footer: {
                            Text("These would go through succession rather than straight to the person you intended. Worth a phone call to each institution.")
                        }
                    }

                    ForEach(sortedNames(groups.named), id: \.self) { name in
                        Section {
                            ForEach(groups.named[name] ?? []) { item in
                                NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                                    ItemRow(item: item).padding(.horizontal, -16)
                                }
                            }
                        } header: {
                            Label(name, systemImage: "person.fill")
                        } footer: {
                            coverFooter(for: groups.named[name] ?? [])
                        }
                    }
                }
            }
        }
        .navigationTitle("Nominees")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sortedNames(_ named: [String: [VaultItem]]) -> [String] {
        named.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// What this person would actually receive, where the amounts are known.
    @ViewBuilder
    private func coverFooter(for items: [VaultItem]) -> some View {
        let total = items.reduce(Decimal(0)) { running, item in
            let labels = ["Sum assured / cover", "Current value", "Amount invested"]
            for label in labels {
                if let text = item.value(forLabel: label), let amount = MoneyValue.amount(from: text) {
                    return running + amount
                }
            }
            return running
        }
        if total > 0 {
            Text("Roughly \(MoneyValue.formatted(total)) across \(items.count) entr\(items.count == 1 ? "y" : "ies"), from the amounts recorded.")
        }
    }
}
