import Foundation
import UniformTypeIdentifiers

enum FieldKind: String, Codable, Hashable {
    case text
    case secret        // masked until revealed: account numbers, CVV, PINs, passwords
    case number
    case money
    case date
    case phone
    case email
    case url
    case multiline

    var isSecret: Bool { self == .secret }
}

struct ItemField: Codable, Identifiable, Hashable {
    var id: UUID
    var label: String
    var value: String
    var kind: FieldKind

    init(id: UUID = UUID(), label: String, value: String = "", kind: FieldKind = .text) {
        self.id = id
        self.label = label
        self.value = value
        self.kind = kind
    }

    var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// A scanned policy, a photo of a card, a PDF statement. The bytes live in a
/// separate encrypted file (and a separate CloudKit asset) so opening an item
/// doesn't mean decrypting megabytes of scans.
struct ItemAttachment: Codable, Identifiable, Hashable {
    var id: UUID
    var filename: String
    var typeIdentifier: String
    var byteCount: Int
    var addedAt: Date

    init(id: UUID = UUID(), filename: String, typeIdentifier: String, byteCount: Int, addedAt: Date = Date()) {
        self.id = id
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.addedAt = addedAt
    }

    private var contentType: UTType? { UTType(typeIdentifier) }
    var isImage: Bool { contentType?.conforms(to: .image) ?? false }
    var isPDF: Bool { contentType?.conforms(to: .pdf) ?? false }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var icon: String {
        if isImage { return "photo" }
        if isPDF { return "doc.richtext" }
        return "doc"
    }
}

/// One record in the vault. Everything here — including the title — is
/// encrypted before it touches disk or iCloud.
struct VaultItem: Codable, Identifiable, Hashable {
    var id: UUID
    var category: ItemCategory
    var title: String
    var subtitle: String
    /// Whose account/policy this is: your name, your wife's, or "Joint".
    var holder: String
    var fields: [ItemField]
    var notes: String
    var attachments: [ItemAttachment]
    var reminderDate: Date?
    var reminderLeadDays: Int
    var isFavourite: Bool
    var createdAt: Date
    var updatedAt: Date
    /// Name of the iPhone that last saved this, so "who changed this?" has an answer.
    var lastEditedBy: String
    var isDeleted: Bool
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        category: ItemCategory,
        title: String = "",
        subtitle: String = "",
        holder: String = "",
        fields: [ItemField] = [],
        notes: String = "",
        attachments: [ItemAttachment] = [],
        reminderDate: Date? = nil,
        reminderLeadDays: Int = 7,
        isFavourite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastEditedBy: String = "",
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.holder = holder
        self.fields = fields
        self.notes = notes
        self.attachments = attachments
        self.reminderDate = reminderDate
        self.reminderLeadDays = reminderLeadDays
        self.isFavourite = isFavourite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEditedBy = lastEditedBy
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }

    /// Decoded leniently so a record written by a newer or older build of the
    /// app on the other phone still opens instead of failing the whole sync.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        category = (try? container.decode(ItemCategory.self, forKey: .category)) ?? .note
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        subtitle = (try? container.decode(String.self, forKey: .subtitle)) ?? ""
        holder = (try? container.decode(String.self, forKey: .holder)) ?? ""
        fields = (try? container.decode([ItemField].self, forKey: .fields)) ?? []
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        attachments = (try? container.decode([ItemAttachment].self, forKey: .attachments)) ?? []
        reminderDate = try? container.decodeIfPresent(Date.self, forKey: .reminderDate)
        reminderLeadDays = (try? container.decode(Int.self, forKey: .reminderLeadDays)) ?? 7
        isFavourite = (try? container.decode(Bool.self, forKey: .isFavourite)) ?? false
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? Date()
        lastEditedBy = (try? container.decode(String.self, forKey: .lastEditedBy)) ?? ""
        isDeleted = (try? container.decode(Bool.self, forKey: .isDeleted)) ?? false
        deletedAt = try? container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled \(category.singular)" : title
    }

    var filledFields: [ItemField] { fields.filter { !$0.isEmpty } }

    func value(forLabel label: String) -> String? {
        fields.first { $0.label.caseInsensitiveCompare(label) == .orderedSame && !$0.isEmpty }?.value
    }

    /// Matched against the search box. Secret values are searchable too — the
    /// whole database is already decrypted in memory once the vault is open.
    func matches(_ query: String) -> Bool {
        let needle = query.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        guard !needle.isEmpty else { return true }
        var haystack = [title, subtitle, holder, notes, category.title, category.singular]
        haystack.append(contentsOf: fields.map(\.label))
        haystack.append(contentsOf: fields.map(\.value))
        haystack.append(contentsOf: attachments.map(\.filename))
        return haystack.contains {
            $0.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(needle)
        }
    }

    /// Days until the reminder fires, negative once it is overdue.
    var daysUntilReminder: Int? {
        guard let reminderDate else { return nil }
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date())
        let to = calendar.startOfDay(for: reminderDate)
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    mutating func touch(on deviceName: String) {
        updatedAt = Date()
        if !deviceName.isEmpty { lastEditedBy = deviceName }
    }
}
