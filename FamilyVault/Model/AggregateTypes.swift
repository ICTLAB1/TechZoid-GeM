import Foundation

/// One line in the vault-wide activity feed.
struct ActivityEntry: Identifiable {
    var item: VaultItem
    var event: ItemEvent

    var id: UUID { event.id }
}

/// A phone number lifted out of an entry for the contacts screen.
struct ContactCard: Identifiable {
    var id = UUID()
    var itemID: UUID
    var category: ItemCategory
    /// "Claim helpline", "Agent contact", "Customer care".
    var label: String
    var number: String
    /// "LIC · Jeevan Anand"
    var belongsTo: String

    /// Digits only — what `tel:` and `sms:` need.
    var dialable: String {
        number.filter { $0.isNumber || $0 == "+" }
    }
}

/// A month's worth of things falling due.
struct DueMonth: Identifiable {
    var month: Date
    var items: [VaultItem]

    var id: Date { month }

    var title: String {
        month.formatted(.dateTime.month(.wide).year())
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
    }
}
