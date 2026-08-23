import SwiftUI

/// Tags cut across categories, so this is the one place a "tax saving" or
/// "review in April" grouping actually comes together.
struct TagsView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var selected: String?

    var body: some View {
        Group {
            if store.allTags.isEmpty {
                EmptyStateView(
                    icon: "tag",
                    title: "No tags yet",
                    message: "Add a tag to any entry and it becomes a way to group things across categories."
                )
            } else {
                List {
                    Section {
                        FlowLayout(spacing: 8) {
                            ForEach(store.allTags, id: \.self) { tag in
                                Button {
                                    selected = (selected == tag) ? nil : tag
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(tag)
                                        Text("\(store.items(taggedWith: tag).count)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selected == tag ? Theme.accent : Color(.tertiarySystemFill))
                                    .foregroundStyle(selected == tag ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)

                    if let selected {
                        Section(selected) {
                            ForEach(store.items(taggedWith: selected)) { item in
                                NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                                    ItemRow(item: item).padding(.horizontal, -16)
                                }
                            }
                        }
                    } else {
                        Section {
                            Text("Pick a tag to see what's under it.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
    }
}
