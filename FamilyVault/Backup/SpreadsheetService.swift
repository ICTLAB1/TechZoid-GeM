import Foundation

/// CSV in and out.
///
/// Getting started is the hardest part of a vault like this — most people
/// already have the details in a spreadsheet somewhere, and retyping forty
/// policies by thumb is why apps like this get abandoned in week one.
///
/// Export is the mirror of that, and is *plaintext by construction*, so the
/// UI treats it with the same warning as the emergency sheet.
enum SpreadsheetService {

    enum Failure: LocalizedError {
        case empty
        case noHeaderRow

        var errorDescription: String? {
            switch self {
            case .empty: "That file has no rows in it."
            case .noHeaderRow: "The first row needs to be column names, e.g. Bank, Account number, IFSC."
            }
        }
    }

    // MARK: - Parsing

    /// A minimal but correct RFC 4180 reader: quoted fields, escaped quotes,
    /// and newlines inside quotes all behave.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.startIndex

        while iterator < text.endIndex {
            let character = text[iterator]

            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: iterator)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        iterator = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(character)
                }
            }
            iterator = text.index(after: iterator)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    struct ImportPreview {
        var headers: [String]
        var rows: [[String]]

        var rowCount: Int { rows.count }
    }

    static func preview(from url: URL) throws -> ImportPreview {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        let rows = parse(text)
        guard let header = rows.first else { throw Failure.empty }
        let headers = header.map { $0.trimmingCharacters(in: .whitespaces) }
        guard headers.contains(where: { !$0.isEmpty }) else { throw Failure.noHeaderRow }

        return ImportPreview(headers: headers, rows: Array(rows.dropFirst()))
    }

    /// Turns rows into entries for one category. Columns whose names match the
    /// category's template keep that field's kind — so a column called "Card
    /// number" arrives already marked secret rather than sitting in the clear.
    static func items(from preview: ImportPreview, category: ItemCategory, holder: String) -> [VaultItem] {
        let template = CategoryTemplates.fields(for: category)
        let kinds = Dictionary(
            template.map { ($0.label.lowercased(), $0.kind) },
            uniquingKeysWith: { first, _ in first }
        )

        return preview.rows.compactMap { row in
            var fields: [ItemField] = []
            for (index, header) in preview.headers.enumerated() {
                guard !header.isEmpty, index < row.count else { continue }
                let value = row[index].trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { continue }
                fields.append(ItemField(label: header, value: value, kind: kinds[header.lowercased()] ?? inferredKind(for: header)))
            }
            guard !fields.isEmpty else { return nil }

            // No repeat is set: dates aren't imported, and a monthly cadence
            // with no due date would be a schedule the user never asked for.
            var item = VaultItem(
                category: category,
                holder: holder,
                fields: fields,
                reminderRepeat: .never
            )
            item.title = fields.first(where: { $0.kind != .secret })?.value ?? "Imported \(category.singular)"

            let institution = CategoryTemplates.institutionField(for: category).lowercased()
            if let match = fields.first(where: { $0.label.lowercased() == institution }) {
                item.subtitle = match.value
            }
            return item
        }
    }

    /// Columns we didn't recognise still shouldn't leave a password in plain
    /// view, so anything that smells sensitive is marked secret.
    private static func inferredKind(for header: String) -> FieldKind {
        let lowered = header.lowercased()
        let secretHints = ["password", "pin", "cvv", "otp", "secret", "number", "account", "policy", "folio", "aadhaar", "pan"]
        if secretHints.contains(where: { lowered.contains($0) }) { return .secret }
        if lowered.contains("mobile") || lowered.contains("phone") || lowered.contains("contact") { return .phone }
        if lowered.contains("email") { return .email }
        if lowered.contains("amount") || lowered.contains("premium") || lowered.contains("value") || lowered.contains("limit") { return .money }
        if lowered.contains("date") { return .date }
        return .text
    }

    // MARK: - Export

    static func csv(for items: [VaultItem], maskSecrets: Bool) -> String {
        var columns = ["Category", "Name", "Belongs to", "Institution", "Tags", "Next due"]
        var extra: [String] = []

        for item in items {
            for field in item.filledFields where !columns.contains(field.label) && !extra.contains(field.label) {
                extra.append(field.label)
            }
        }
        columns.append(contentsOf: extra)

        var lines = [columns.map(escape).joined(separator: ",")]

        for item in items {
            var row: [String] = [
                item.category.title,
                item.displayTitle,
                item.holder,
                item.subtitle,
                item.tags.joined(separator: " "),
                item.nextDueDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
            ]
            for label in extra {
                guard let field = item.filledFields.first(where: { $0.label == label }) else {
                    row.append("")
                    continue
                }
                row.append(field.kind.isSecret && maskSecrets ? mask(field.value) : field.value)
            }
            lines.append(row.map(escape).joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    static func write(csv: String, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(csv.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func mask(_ value: String) -> String {
        guard value.count > 4 else { return String(repeating: "\u{2022}", count: max(value.count, 4)) }
        return String(repeating: "\u{2022}", count: 4) + value.suffix(4)
    }
}
