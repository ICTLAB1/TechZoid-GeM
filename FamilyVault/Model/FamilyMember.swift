import Foundation

/// One person the vault's entries can belong to — you, your wife, either of
/// your kids, anyone else you name. Kept as its own small synced record
/// (mirroring `VaultDevice`) so the same roster of names shows up on both
/// phones, rather than each phone accumulating its own guesses from whatever
/// text happens to get typed into "Belongs to."
struct FamilyMember: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var addedAt: Date

    static func new(name: String) -> FamilyMember {
        FamilyMember(id: UUID().uuidString, name: name, addedAt: Date())
    }
}
