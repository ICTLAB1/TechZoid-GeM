import Foundation
import SwiftUI

/// The money view of the vault: what you're covered for, what you own, what
/// you owe, and what leaves the account every month.
struct VaultSummary {
    var insuranceCover: Decimal = 0
    var annualPremium: Decimal = 0
    var invested: Decimal = 0
    var currentValue: Decimal = 0
    var loanOutstanding: Decimal = 0
    var monthlyEMI: Decimal = 0
    var creditLimit: Decimal = 0

    var policyCount = 0
    var investmentCount = 0
    var loanCount = 0
    var cardCount = 0
    var accountCount = 0

    var isEmpty: Bool {
        insuranceCover == 0 && invested == 0 && currentValue == 0
            && loanOutstanding == 0 && monthlyEMI == 0 && creditLimit == 0
    }

    static func build(from items: [VaultItem]) -> VaultSummary {
        var summary = VaultSummary()

        for item in items {
            switch item.category {
            case .insurance:
                summary.policyCount += 1
                summary.insuranceCover += amount(item, "Sum assured / cover")
                summary.annualPremium += annualisedPremium(item)

            case .investment:
                summary.investmentCount += 1
                let put = amount(item, "Amount invested")
                let now = amount(item, "Current value")
                summary.invested += put
                summary.currentValue += (now > 0 ? now : put)

            case .loan:
                summary.loanCount += 1
                let outstanding = amount(item, "Outstanding amount")
                summary.loanOutstanding += (outstanding > 0 ? outstanding : amount(item, "Principal amount"))
                summary.monthlyEMI += amount(item, "EMI amount")

            case .card:
                summary.cardCount += 1
                summary.creditLimit += amount(item, "Credit limit")

            case .bankAccount:
                summary.accountCount += 1

            default:
                break
            }
        }
        return summary
    }

    var investmentGain: Decimal { currentValue - invested }

    private static func amount(_ item: VaultItem, _ label: String) -> Decimal {
        guard let text = item.value(forLabel: label), let value = MoneyValue.amount(from: text) else { return 0 }
        return value
    }

    /// A ₹5,000 monthly premium and a ₹60,000 yearly one are the same outgo —
    /// normalise both to a year so the total means something.
    private static func annualisedPremium(_ item: VaultItem) -> Decimal {
        let premium = amount(item, "Premium amount")
        guard premium > 0 else { return 0 }
        let frequency = (item.value(forLabel: "Premium frequency") ?? "").lowercased()

        if frequency.contains("month") { return premium * 12 }
        if frequency.contains("quarter") { return premium * 4 }
        if frequency.contains("half") || frequency.contains("semi") { return premium * 2 }
        if frequency.contains("single") || frequency.contains("one") { return 0 }
        return premium   // yearly, or unstated
    }
}

/// A month's worth of the summary tiles, kept locally so a chart can show how
/// things have moved over time. Derived from the items rather than something
/// the user typed, so it never needs to go up to CloudKit — each phone can
/// (re)build its own history from the vault it already has.
struct NetWorthSnapshot: Codable, Identifiable {
    var id: UUID = UUID()
    var month: Date       // normalized to the first of the month, for stable sorting/grouping
    var cover: Decimal
    var invested: Decimal   // use VaultSummary.currentValue
    var outstanding: Decimal
    var netWorth: Decimal   // invested - outstanding
}

// MARK: - Health check

enum FindingSeverity: Int, Comparable {
    case critical = 0
    case warning = 1
    case suggestion = 2

    static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .critical: "Needs attention"
        case .warning: "Worth checking"
        case .suggestion: "Could be better"
        }
    }

    var tint: Color {
        switch self {
        case .critical: .red
        case .warning: .orange
        case .suggestion: .secondary
        }
    }

    var icon: String {
        switch self {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .suggestion: "lightbulb.fill"
        }
    }
}

struct HealthFinding: Identifiable {
    var id = UUID()
    var itemID: UUID?
    var severity: FindingSeverity
    var title: String
    var detail: String
}

/// Reads the whole vault and points out the things that quietly rot: a lapsed
/// policy, an expired card, a policy with no nominee, a password used twice.
enum VaultHealth {

    static func findings(for items: [VaultItem]) -> [HealthFinding] {
        var findings: [HealthFinding] = []

        for item in items {
            findings.append(contentsOf: reminderFindings(item))
            findings.append(contentsOf: nomineeFindings(item))
            findings.append(contentsOf: expiryFindings(item))
            findings.append(contentsOf: passwordFindings(item))
        }

        findings.append(contentsOf: reusedPasswordFindings(items))
        findings.append(contentsOf: duplicateEntryFindings(items))

        return findings.sorted { lhs, rhs in
            lhs.severity == rhs.severity ? lhs.title < rhs.title : lhs.severity < rhs.severity
        }
    }

    private static func reminderFindings(_ item: VaultItem) -> [HealthFinding] {
        guard let days = item.daysUntilReminder else {
            if item.category == .insurance || item.category == .loan {
                return [HealthFinding(
                    itemID: item.id,
                    severity: .suggestion,
                    title: item.displayTitle,
                    detail: "No \(item.category.reminderLabel.lowercased()) set — you won't be reminded about this one."
                )]
            }
            return []
        }

        if days < 0 {
            return [HealthFinding(
                itemID: item.id,
                severity: .critical,
                title: item.displayTitle,
                detail: "\(item.category.reminderLabel) passed \(abs(days)) day\(abs(days) == 1 ? "" : "s") ago."
            )]
        }
        if days <= 30 {
            return [HealthFinding(
                itemID: item.id,
                severity: .warning,
                title: item.displayTitle,
                detail: days == 0 ? "\(item.category.reminderLabel) is today." : "\(item.category.reminderLabel) in \(days) day\(days == 1 ? "" : "s")."
            )]
        }
        return []
    }

    private static func nomineeFindings(_ item: VaultItem) -> [HealthFinding] {
        let needsNominee: Set<ItemCategory> = [.insurance, .investment, .bankAccount]
        guard needsNominee.contains(item.category) else { return [] }
        guard item.value(forLabel: "Nominee") == nil else { return [] }
        return [HealthFinding(
            itemID: item.id,
            severity: .warning,
            title: item.displayTitle,
            detail: "No nominee recorded. This is the field families most often wish had been filled in."
        )]
    }

    private static func expiryFindings(_ item: VaultItem) -> [HealthFinding] {
        var findings: [HealthFinding] = []

        if item.category == .card, let expiry = item.value(forLabel: "Expiry (MM/YY)"),
           let date = cardExpiryDate(expiry) {
            if date < Date() {
                findings.append(HealthFinding(
                    itemID: item.id, severity: .critical, title: item.displayTitle,
                    detail: "The card expired in \(expiry). Replace it or remove the entry."
                ))
            } else if let months = Calendar.current.dateComponents([.month], from: Date(), to: date).month, months <= 2 {
                findings.append(HealthFinding(
                    itemID: item.id, severity: .warning, title: item.displayTitle,
                    detail: "The card expires in \(expiry) — a replacement is probably on its way."
                ))
            }
        }

        if item.category == .identity, let validUntil = item.value(forLabel: "Valid until"),
           let date = looseDate(validUntil), date < Date() {
            findings.append(HealthFinding(
                itemID: item.id, severity: .critical, title: item.displayTitle,
                detail: "Expired on \(validUntil)."
            ))
        }

        return findings
    }

    private static func passwordFindings(_ item: VaultItem) -> [HealthFinding] {
        guard item.category == .login, let password = item.value(forLabel: "Password") else { return [] }
        let strength = KeyDerivation.strength(of: password)
        guard !strength.isAcceptable else { return [] }
        return [HealthFinding(
            itemID: item.id,
            severity: .warning,
            title: item.displayTitle,
            detail: "The saved password is weak (\(strength.label.lowercased())). Tap the dice in the editor to generate a strong one."
        )]
    }

    private static func reusedPasswordFindings(_ items: [VaultItem]) -> [HealthFinding] {
        var byPassword: [String: [VaultItem]] = [:]
        for item in items {
            guard let password = item.value(forLabel: "Password") else { continue }
            byPassword[password, default: []].append(item)
        }

        return byPassword.compactMap { _, sharing in
            guard sharing.count > 1 else { return nil }
            let names = sharing.map(\.displayTitle).sorted().joined(separator: ", ")
            return HealthFinding(
                itemID: sharing.first?.id,
                severity: .critical,
                title: "One password, \(sharing.count) logins",
                detail: "The same password is saved for: \(names). If one leaks, all of them are open."
            )
        }
    }

    /// The same account, policy or card number recorded on two entries in the
    /// same category — almost always the same real-world thing added twice,
    /// most often from two different scanned documents.
    private static func duplicateEntryFindings(_ items: [VaultItem]) -> [HealthFinding] {
        var byKey: [String: [VaultItem]] = [:]

        for item in items {
            guard let label = CategoryTemplates.identifyingField(for: item.category),
                  let raw = item.value(forLabel: label) else { continue }
            let normalized = raw
                .folding(options: .diacriticInsensitive, locale: .current)
                .uppercased()
                .filter { !$0.isWhitespace }
            guard !normalized.isEmpty else { continue }
            let key = "\(item.category.rawValue)|\(normalized)"
            byKey[key, default: []].append(item)
        }

        return byKey.values.compactMap { sharing -> HealthFinding? in
            guard sharing.count > 1, let category = sharing.first?.category,
                  let label = CategoryTemplates.identifyingField(for: category)
            else { return nil }
            let names = sharing.map(\.displayTitle).sorted().joined(separator: ", ")
            return HealthFinding(
                itemID: sharing.first?.id,
                severity: .warning,
                title: "Possible duplicate \(category.singular.lowercased())",
                detail: "The same \(label.lowercased()) is recorded on: \(names). Worth checking these aren't the same \(category.singular.lowercased()) added twice."
            )
        }
    }

    // MARK: - Loose date parsing

    /// Accepts "09/28", "09/2028", "9-28".
    static func cardExpiryDate(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { "/-. ".contains($0) }).map(String.init)
        guard parts.count >= 2, let month = Int(parts[0]), var year = Int(parts[1]), (1...12).contains(month) else { return nil }
        if year < 100 { year += 2000 }

        var components = DateComponents()
        components.year = year
        components.month = month
        guard let start = Calendar.current.date(from: components),
              let range = Calendar.current.range(of: .day, in: .month, for: start) else { return nil }
        components.day = range.count   // cards are valid through the last day of the month
        return Calendar.current.date(from: components)
    }

    /// Best-effort parse of the free-text date fields in the templates.
    static func looseDate(_ text: String) -> Date? {
        let formats = ["dd/MM/yyyy", "dd-MM-yyyy", "yyyy-MM-dd", "dd MMM yyyy", "MMM yyyy", "MM/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespaces)) { return date }
        }
        return nil
    }
}
