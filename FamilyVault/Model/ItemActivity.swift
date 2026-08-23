import Foundation

/// One thing that happened to an entry.
///
/// In a vault two people share, "who changed this and when" is a real
/// question. History records the *shape* of a change — which fields moved —
/// never the values, so the log itself never becomes a second copy of the
/// secrets.
struct ItemEvent: Codable, Identifiable, Hashable {

    enum Kind: String, Codable {
        case created
        case edited
        case payment
        case attachmentAdded
        case attachmentRemoved
        case deleted
        case restored

        var icon: String {
            switch self {
            case .created: "plus.circle.fill"
            case .edited: "pencil.circle.fill"
            case .payment: "indianrupeesign.circle.fill"
            case .attachmentAdded: "paperclip.circle.fill"
            case .attachmentRemoved: "paperclip"
            case .deleted: "trash.circle.fill"
            case .restored: "arrow.uturn.backward.circle.fill"
            }
        }

        var verb: String {
            switch self {
            case .created: "Added"
            case .edited: "Edited"
            case .payment: "Payment recorded"
            case .attachmentAdded: "Document added"
            case .attachmentRemoved: "Document removed"
            case .deleted: "Deleted"
            case .restored: "Restored"
            }
        }
    }

    var id: UUID
    var kind: Kind
    var at: Date
    var deviceName: String
    /// Human summary — "Password, EMI amount" or "₹45,000 for 5 Sep".
    var detail: String

    init(id: UUID = UUID(), kind: Kind, at: Date = Date(), deviceName: String = "", detail: String = "") {
        self.id = id
        self.kind = kind
        self.at = at
        self.deviceName = deviceName
        self.detail = detail
    }

    var summary: String {
        detail.isEmpty ? kind.verb : "\(kind.verb): \(detail)"
    }
}

/// An EMI or premium actually paid.
struct PaymentRecord: Codable, Identifiable, Hashable {
    var id: UUID
    /// The instalment this settles — the due date it was against.
    var dueDate: Date?
    var paidOn: Date
    var amount: String
    var note: String
    var recordedBy: String

    init(
        id: UUID = UUID(),
        dueDate: Date? = nil,
        paidOn: Date = Date(),
        amount: String = "",
        note: String = "",
        recordedBy: String = ""
    ) {
        self.id = id
        self.dueDate = dueDate
        self.paidOn = paidOn
        self.amount = amount
        self.note = note
        self.recordedBy = recordedBy
    }

    var displayAmount: String? {
        amount.trimmingCharacters(in: .whitespaces).isEmpty ? nil : MoneyValue.display(amount)
    }
}
