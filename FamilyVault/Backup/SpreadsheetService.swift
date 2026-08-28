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

    /// Column names used by the password managers people actually export from,
    /// mapped onto this app's own field labels.
    ///
    /// Google Password Manager writes `name,url,username,password,note`;
    /// Apple's Passwords app writes `Title,URL,Username,Password,Notes,OTPAuth`.
    /// Imported as-is those become fields literally called "url" and "note",
    /// sitting alongside the Login template's own "Website / app" and
    /// "Username" rather than filling them. Renaming the columns on the way in
    /// means one export lands as proper login entries.
    private static let passwordExportAliases: [String: String] = [
        // `name`/`title` is handled separately — see `normalisedForPasswordImport`.
        // Both exports carry a display name *and* a URL, and mapping both to
        // "Website / app" gave every entry that field twice.
        "url": "Website / app",
        "username": "Username",
        "login": "Username",
        "login_username": "Username",
        "password": "Password",
        "otpauth": "Two-factor backup codes",
        "totp": "Two-factor backup codes"
    ]

    /// Whether these columns look like a password-manager export.
    ///
    /// Deliberately strict: a password column on its own is not enough, since
    /// plenty of the app's own exports have one. It takes a username *and* a
    /// password, which together only really describe a credential list.
    static func looksLikePasswordExport(_ headers: [String]) -> Bool {
        let lowered = Set(headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        let hasPassword = lowered.contains("password")
        let hasUser = !lowered.isDisjoint(with: ["username", "login", "login_username"])
        return hasPassword && hasUser
    }

    /// Renames a password export's columns onto the Login template's labels.
    ///
    /// A "note"/"notes" column is dropped from the headers and carried
    /// separately, because a note belongs in the entry's notes rather than as
    /// a field sitting in the middle of the credentials.
    struct PasswordImportPlan {
        var preview: ImportPreview
        /// Becomes the entry's notes.
        var noteColumn: Int?
        /// Becomes the entry's name — "Netflix" rather than the URL.
        var titleColumn: Int?
    }

    static func normalisedForPasswordImport(_ preview: ImportPreview) -> PasswordImportPlan {
        let keys = preview.headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        // Only lift the display name out as the title when there is a URL
        // column to hold the address. With no URL, the name is all there is,
        // so it stays as the "Website / app" field.
        let hasURL = keys.contains("url")

        var headers: [String] = []
        var noteColumn: Int?
        var titleColumn: Int?

        for (index, key) in keys.enumerated() {
            if key == "note" || key == "notes" {
                noteColumn = index
                headers.append("")          // an empty header is skipped on import
                continue
            }
            if key == "name" || key == "title" {
                if hasURL {
                    titleColumn = index
                    headers.append("")
                } else {
                    headers.append("Website / app")
                }
                continue
            }
            headers.append(passwordExportAliases[key] ?? preview.headers[index])
        }

        return PasswordImportPlan(
            preview: ImportPreview(headers: headers, rows: preview.rows),
            noteColumn: noteColumn,
            titleColumn: titleColumn
        )
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
    static func items(
        from preview: ImportPreview,
        category: ItemCategory,
        holder: String,
        noteColumn: Int? = nil,
        titleColumn: Int? = nil
    ) -> [VaultItem] {
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
            // A note column travels into the entry's notes rather than sitting
            // among the credentials as a field.
            if let noteColumn, noteColumn < row.count {
                let note = row[noteColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty { item.notes = note }
            }

            // Prefer the site or app this credential belongs to: on a password
            // export the first non-secret column is the name of the thing,
            // which is exactly what the entry should be called.
            let namedTitle = titleColumn.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil }
            let preferredTitle = CategoryTemplates.subtitleField(for: category).lowercased()
            item.title = (namedTitle?.isEmpty == false ? namedTitle : nil)
                ?? fields.first(where: { $0.label.lowercased() == preferredTitle && $0.kind != .secret })?.value
                ?? fields.first(where: { $0.kind != .secret })?.value
                ?? "Imported \(category.singular)"

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

    /// One row per payment recorded against any entry, newest first within
    /// each entry.
    static func paymentsCSV(for items: [VaultItem]) -> String {
        let columns = ["Entry", "Category", "Amount", "Paid on", "Due date", "Note", "Recorded by"]
        var lines = [columns.map(escape).joined(separator: ",")]

        for item in items {
            for payment in item.paymentsByRecency {
                let row = [
                    item.displayTitle,
                    item.category.title,
                    payment.amount,
                    payment.paidOn.formatted(date: .abbreviated, time: .omitted),
                    payment.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "",
                    payment.note,
                    payment.recordedBy
                ]
                lines.append(row.map(escape).joined(separator: ","))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// One row per activity entry — the same feed the "recent activity" screen
    /// shows, as a spreadsheet.
    static func activityCSV(for entries: [ActivityEntry]) -> String {
        let columns = ["Entry", "Category", "Event", "Summary", "When", "Device"]
        var lines = [columns.map(escape).joined(separator: ",")]

        for entry in entries {
            let row = [
                entry.item.displayTitle,
                entry.item.category.title,
                entry.event.kind.verb,
                entry.event.detail,
                entry.event.at.formatted(date: .abbreviated, time: .shortened),
                entry.event.deviceName
            ]
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
