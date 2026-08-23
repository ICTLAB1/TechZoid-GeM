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
    /// Text read out of the document when it was added — used to fill fields
    /// in, to write the plain-language summary, and to make the contents
    /// searchable. Capped, and encrypted with everything else.
    var extractedText: String?
    /// How many pages the scanner captured, when it came from the camera.
    var pageCount: Int?

    static let maximumExtractedCharacters = 6000

    init(
        id: UUID = UUID(),
        filename: String,
        typeIdentifier: String,
        byteCount: Int,
        addedAt: Date = Date(),
        extractedText: String? = nil,
        pageCount: Int? = nil
    ) {
        self.id = id
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.addedAt = addedAt
        self.extractedText = extractedText
        self.pageCount = pageCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        filename = (try? container.decode(String.self, forKey: .filename)) ?? "Attachment"
        typeIdentifier = (try? container.decode(String.self, forKey: .typeIdentifier)) ?? "public.data"
        byteCount = (try? container.decode(Int.self, forKey: .byteCount)) ?? 0
        addedAt = (try? container.decode(Date.self, forKey: .addedAt)) ?? Date()
        extractedText = try? container.decodeIfPresent(String.self, forKey: .extractedText)
        pageCount = try? container.decodeIfPresent(Int.self, forKey: .pageCount)
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
    var reminderRepeat: ReminderRepeat
    /// The instalment most recently settled, so a paid EMI stops nagging and
    /// the next one takes over.
    var lastPaidDueDate: Date?
    var payments: [PaymentRecord]
    var tags: [String]
    var history: [ItemEvent]
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
        reminderRepeat: ReminderRepeat = .never,
        lastPaidDueDate: Date? = nil,
        payments: [PaymentRecord] = [],
        tags: [String] = [],
        history: [ItemEvent] = [],
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
        self.reminderRepeat = reminderRepeat
        self.lastPaidDueDate = lastPaidDueDate
        self.payments = payments
        self.tags = tags
        self.history = history
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
        reminderRepeat = (try? container.decode(ReminderRepeat.self, forKey: .reminderRepeat)) ?? .never
        lastPaidDueDate = try? container.decodeIfPresent(Date.self, forKey: .lastPaidDueDate)
        payments = (try? container.decode([PaymentRecord].self, forKey: .payments)) ?? []
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        history = (try? container.decode([ItemEvent].self, forKey: .history)) ?? []
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
        haystack.append(contentsOf: attachments.compactMap(\.extractedText))
        haystack.append(contentsOf: tags)
        return haystack.contains {
            $0.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(needle)
        }
    }

    /// How many days an overdue repeating due date keeps showing as overdue
    /// before it rolls on to the next one. An EMI due on the 5th should still
    /// read "overdue" on the 7th, not "due in 28 days".
    private static let overdueGraceDays = 7

    /// The occurrence this entry is currently pointing at. For a one-off that
    /// is simply the date entered; for an EMI or a yearly premium it walks
    /// forward from the first one.
    var nextDueDate: Date? {
        guard let reminderDate else { return nil }
        guard let stride = reminderRepeat.monthStride else { return reminderDate }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let graceFloor = calendar.date(byAdding: .day, value: -Self.overdueGraceDays, to: today) else {
            return reminderDate
        }

        // An instalment that has been paid is settled even if its date has
        // only just passed, so it must not win the grace window back.
        let settled = lastPaidDueDate.map { calendar.startOfDay(for: $0) }

        var step = 0
        while step < 1200 {
            guard let candidate = calendar.date(byAdding: .month, value: stride * step, to: reminderDate) else { break }
            let day = calendar.startOfDay(for: candidate)
            if let settled, day <= settled {
                step += 1
                continue
            }
            if day >= graceFloor { return candidate }
            step += 1
        }
        return reminderDate
    }

    /// Days until the next occurrence, negative once it is overdue.
    var daysUntilReminder: Int? {
        guard let due = nextDueDate else { return nil }
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date())
        let to = calendar.startOfDay(for: due)
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    mutating func touch(on deviceName: String) {
        updatedAt = Date()
        if !deviceName.isEmpty { lastEditedBy = deviceName }
    }

    /// History is capped so a long-lived entry can't grow without bound.
    static let maximumHistoryEntries = 40

    mutating func record(_ event: ItemEvent) {
        history.append(event)
        if history.count > Self.maximumHistoryEntries {
            history.removeFirst(history.count - Self.maximumHistoryEntries)
        }
    }

    /// Payments, newest first.
    var paymentsByRecency: [PaymentRecord] {
        payments.sorted { $0.paidOn > $1.paidOn }
    }

    var recentHistory: [ItemEvent] {
        history.sorted { $0.at > $1.at }
    }
}
