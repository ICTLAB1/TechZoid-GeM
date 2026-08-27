import SwiftUI

/// The roster of names "Belongs to" picks from — kept in sync between both
/// phones so an entry can be tagged to you, your wife, or either of your
/// kids consistently, not just whatever text happens to get typed in.
struct FamilyMembersView: View {
    @EnvironmentObject private var store: VaultStore

    @State private var isAdding = false
    @State private var newName = ""
    @State private var renaming: FamilyMember?
    @State private var renameText = ""
    @State private var pendingRemoval: FamilyMember?

    var body: some View {
        List {
            Section {
                if store.familyMembers.isEmpty {
                    Text("Add everyone whose accounts or documents live in this vault — yourself, your wife, your kids.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.familyMembers) { member in
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text(member.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            renameText = member.name
                            renaming = member
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingRemoval = member
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Family members")
            } footer: {
                Text("Entries already tagged to a name that's removed here keep that text — nothing gets deleted, it just stops appearing as a suggestion.")
            }

            Section {
                Button {
                    newName = ""
                    isAdding = true
                } label: {
                    Label("Add a family member", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle("Family Members")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Add a family member", isPresented: $isAdding) {
            TextField("Name", text: $newName)
            Button("Add") { store.addFamilyMember(named: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their name — not an account. Used only to tag entries as theirs.")
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let renaming { store.renameFamilyMember(renaming, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval { store.removeFamilyMember(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Existing entries keep the name they were tagged with — this only removes it from the picker.")
        }
    }
}
