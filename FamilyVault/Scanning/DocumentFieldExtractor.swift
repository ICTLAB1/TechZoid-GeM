import Foundation

/// A value the app believes it found in a document.
struct ExtractedField: Identifiable, Hashable {
    var id = UUID()
    var label: String
    var value: String
    /// 0–1. Anything below `DocumentFieldExtractor.autoFillThreshold` is
    /// offered for review rather than filled in.
    var confidence: Double
    /// The line it came from, so the user can judge it without opening the PDF.
    var evidence: String
}

/// Pulls policy, loan, card and identity details out of recognised text.
///
/// This is heuristic, and honest about it: Indian insurers and banks lay their
/// documents out however they like. The rule that keeps it safe is that a
/// value is only ever written into a field that is *empty*; anything that would
/// overwrite what you already typed is shown to you first.
enum DocumentFieldExtractor {

    /// Below this, a match is proposed but never applied on its own.
    static let autoFillThreshold = 0.75

    static func fields(in text: String, category: ItemCategory) -> [ExtractedField] {
        guard !text.isEmpty else { return [] }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var found: [ExtractedField] = []

        for rule in rules(for: category) {
            guard let hit = firstMatch(rule: rule, lines: lines) else { continue }
            guard !found.contains(where: { $0.label == rule.label }) else { continue }
            found.append(hit)
        }

        return found
    }

    // MARK: - Rules

    private struct Rule {
        var label: String
        /// Words that introduce the value, matched case-insensitively.
        var cues: [String]
        var kind: ValueKind
        var confidence: Double = 0.85
    }

    private enum ValueKind {
        case alphanumeric   // policy / loan / folio numbers
        case money
        case date
        case percentage
        case name
        case freeText
    }

    private static func rules(for category: ItemCategory) -> [Rule] {
        switch category {
        case .insurance:
            [
                Rule(label: "Policy number", cues: ["policy no", "policy number", "policy #", "certificate no"], kind: .alphanumeric, confidence: 0.9),
                Rule(label: "Insurer", cues: ["insurer", "insurance company", "issued by"], kind: .name, confidence: 0.7),
                Rule(label: "Policy holder", cues: ["policy holder", "policyholder", "proposer", "insured name", "name of the insured"], kind: .name),
                Rule(label: "Sum assured / cover", cues: ["sum assured", "sum insured", "cover amount", "basic sum assured", "coverage"], kind: .money, confidence: 0.88),
                Rule(label: "Premium amount", cues: ["premium amount", "total premium", "instalment premium", "installment premium", "premium payable", "gross premium"], kind: .money, confidence: 0.85),
                Rule(label: "Premium frequency", cues: ["premium frequency", "mode of payment", "payment mode", "premium mode"], kind: .freeText, confidence: 0.8),
                Rule(label: "Start date", cues: ["date of commencement", "commencement date", "policy start", "risk commencement", "period of insurance from"], kind: .date),
                Rule(label: "Maturity date", cues: ["date of maturity", "maturity date", "policy end", "expiry date", "period of insurance to"], kind: .date),
                Rule(label: "Nominee", cues: ["nominee", "name of nominee", "nominee name", "beneficiary"], kind: .name, confidence: 0.88),
                Rule(label: "Agent contact", cues: ["agent mobile", "agent contact", "advisor contact"], kind: .alphanumeric, confidence: 0.7),
                Rule(label: "Claim helpline", cues: ["toll free", "toll-free", "helpline", "customer care", "claim intimation"], kind: .alphanumeric, confidence: 0.75)
            ]

        case .loan:
            [
                Rule(label: "Loan account number", cues: ["loan account", "loan a/c", "account no", "loan number", "agreement no"], kind: .alphanumeric, confidence: 0.9),
                Rule(label: "Lender", cues: ["lender", "bank name", "financed by", "issued by"], kind: .name, confidence: 0.7),
                Rule(label: "Borrower", cues: ["borrower", "applicant name", "name of borrower"], kind: .name),
                Rule(label: "Principal amount", cues: ["loan amount", "sanctioned amount", "principal", "amount financed", "disbursed amount"], kind: .money, confidence: 0.88),
                Rule(label: "Outstanding amount", cues: ["outstanding", "balance principal", "principal outstanding"], kind: .money),
                Rule(label: "Interest rate", cues: ["rate of interest", "interest rate", "roi"], kind: .percentage, confidence: 0.85),
                Rule(label: "EMI amount", cues: ["emi amount", "monthly instalment", "monthly installment", "emi"], kind: .money, confidence: 0.88),
                Rule(label: "Tenure", cues: ["tenure", "loan period", "number of instalments", "no. of emis"], kind: .freeText),
                Rule(label: "Loan end date", cues: ["last emi", "loan end", "maturity date", "final instalment"], kind: .date, confidence: 0.75)
            ]

        case .bankAccount:
            [
                Rule(label: "Account number", cues: ["account no", "a/c no", "ac no", "account number", "account #"], kind: .alphanumeric, confidence: 0.9),
                Rule(label: "IFSC code", cues: ["ifsc", "ifs code"], kind: .alphanumeric, confidence: 0.95),
                Rule(label: "Bank", cues: ["bank name", "issued by", "name of bank"], kind: .name, confidence: 0.7),
                Rule(label: "Branch", cues: ["branch name", "home branch", "branch"], kind: .freeText, confidence: 0.75),
                Rule(label: "Account holder", cues: ["account holder", "name of account holder", "customer name", "account name"], kind: .name),
                Rule(label: "Account type", cues: ["account type", "scheme", "product name"], kind: .freeText, confidence: 0.7),
                Rule(label: "Customer ID", cues: ["customer id", "cif no", "cif", "crn"], kind: .alphanumeric),
                Rule(label: "Registered mobile", cues: ["registered mobile", "mobile no", "mobile number"], kind: .alphanumeric, confidence: 0.75),
                Rule(label: "Nominee", cues: ["nomination", "nominee"], kind: .name, confidence: 0.7)
            ]

        case .investment:
            [
                Rule(label: "Folio / account number", cues: ["folio no", "folio number", "account no", "certificate no"], kind: .alphanumeric, confidence: 0.88),
                Rule(label: "Institution / AMC", cues: ["mutual fund", "amc", "issued by", "bank name"], kind: .name, confidence: 0.7),
                Rule(label: "Amount invested", cues: ["amount invested", "investment amount", "deposit amount", "principal"], kind: .money),
                Rule(label: "Current value", cues: ["current value", "maturity amount", "market value"], kind: .money),
                Rule(label: "Interest / return rate", cues: ["rate of interest", "interest rate"], kind: .percentage),
                Rule(label: "Maturity date", cues: ["maturity date", "date of maturity"], kind: .date),
                Rule(label: "Nominee", cues: ["nominee", "beneficiary"], kind: .name)
            ]

        case .identity, .document:
            [
                Rule(label: "Document number", cues: ["number", "no.", "id no", "licence no", "license no", "passport no"], kind: .alphanumeric, confidence: 0.7),
                Rule(label: "Reference number", cues: ["reference no", "ref no", "certificate no", "registration no"], kind: .alphanumeric, confidence: 0.75),
                Rule(label: "Name on document", cues: ["name"], kind: .name, confidence: 0.65),
                Rule(label: "In the name of", cues: ["name"], kind: .name, confidence: 0.6),
                Rule(label: "Date of birth", cues: ["date of birth", "dob"], kind: .date, confidence: 0.9),
                Rule(label: "Issued on", cues: ["date of issue", "issued on", "issue date"], kind: .date),
                Rule(label: "Valid until", cues: ["valid until", "valid upto", "date of expiry", "expiry", "valid till"], kind: .date, confidence: 0.88),
                Rule(label: "Issuing authority", cues: ["issuing authority", "issued by", "authority"], kind: .name, confidence: 0.7)
            ]

        case .card:
            // A card *statement* is a different document from the card itself.
            // It never prints the full number, the CVV or the PIN — but it does
            // carry the things that are tedious to type and easy to forget.
            [
                Rule(label: "Issuer", cues: ["issued by", "bank name", "statement from"], kind: .name, confidence: 0.7),
                Rule(label: "Name on card", cues: ["name on card", "card member", "cardmember", "customer name"], kind: .name, confidence: 0.8),
                Rule(label: "Card number", cues: ["card no", "card number", "credit card number", "account number"], kind: .alphanumeric, confidence: 0.8),
                Rule(label: "Credit limit", cues: ["total credit limit", "credit limit", "sanctioned limit"], kind: .money, confidence: 0.9),
                Rule(label: "Statement date", cues: ["statement date", "statement generated on", "bill date"], kind: .date, confidence: 0.88),
                Rule(label: "Payment due date", cues: ["payment due date", "due date", "pay by"], kind: .date, confidence: 0.9),
                Rule(label: "Customer care", cues: ["customer care", "toll free", "toll-free", "helpline", "contact us"], kind: .alphanumeric, confidence: 0.75),
                Rule(label: "Linked bank account", cues: ["auto debit", "linked account", "debit account"], kind: .alphanumeric, confidence: 0.6)
            ]

        default:
            []
        }
    }

    // MARK: - Matching

    private static func firstMatch(rule: Rule, lines: [String]) -> ExtractedField? {
        for (index, line) in lines.enumerated() {
            let lowered = line.lowercased()
            guard let cue = rule.cues.first(where: { lowered.contains($0) }) else { continue }

            // Value on the same line, after the cue and any separator…
            if let tail = trailing(of: line, after: cue), let value = value(from: tail, kind: rule.kind) {
                return field(rule: rule, value: value, confidence: rule.confidence, evidence: line)
            }
            // …or on the line below, which is how tables usually come out of OCR.
            if index + 1 < lines.count, let value = value(from: lines[index + 1], kind: rule.kind) {
                return field(
                    rule: rule,
                    value: value,
                    confidence: max(rule.confidence - 0.15, 0.4),
                    evidence: "\(line) → \(lines[index + 1])"
                )
            }
        }
        return nil
    }

    /// Statements print numbers half-hidden — `XXXXXXXX3417`, `**** 3417`.
    /// That is a genuine reading of the document, but it is not the number, so
    /// it is knocked down below the auto-fill line and shows up for review with
    /// the reason attached rather than quietly becoming your card number.
    private static func field(rule: Rule, value: String, confidence: Double, evidence: String) -> ExtractedField {
        guard isMasked(value) else {
            return ExtractedField(label: rule.label, value: value, confidence: confidence, evidence: evidence)
        }
        return ExtractedField(
            label: rule.label,
            value: value,
            confidence: min(confidence, 0.45),
            evidence: "\(evidence)  ·  partly hidden on the statement"
        )
    }

    private static func isMasked(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.contains("****") || lowered.contains("••••") { return true }
        // Three or more consecutive x's is masking, not a real identifier.
        return lowered.range(of: "x{3,}", options: .regularExpression) != nil
    }

    private static func trailing(of line: String, after cue: String) -> String? {
        guard let range = line.range(of: cue, options: .caseInsensitive) else { return nil }
        var tail = String(line[range.upperBound...])
        tail = tail.trimmingCharacters(in: CharacterSet(charactersIn: " :\t-–—=.#"))
        return tail.isEmpty ? nil : tail
    }

    private static func value(from text: String, kind: ValueKind) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        switch kind {
        case .alphanumeric:
            // At least six characters of number-ish identifier.
            guard let match = firstMatch(in: trimmed, pattern: "[A-Z0-9][A-Z0-9\\-/ ]{5,29}[A-Z0-9]") else { return nil }
            let cleaned = match.trimmingCharacters(in: .whitespaces)
            return cleaned.contains(where: \.isNumber) ? cleaned : nil

        case .money:
            guard let match = firstMatch(in: trimmed, pattern: "(?:₹|rs\\.?|inr)?\\s?[0-9][0-9,]{2,}(?:\\.[0-9]{1,2})?") else { return nil }
            let digits = match.filter { $0.isNumber || $0 == "." }
            guard let amount = Decimal(string: digits), amount > 0 else { return nil }
            return digits.hasSuffix(".00") ? String(digits.dropLast(3)) : digits

        case .percentage:
            guard let match = firstMatch(in: trimmed, pattern: "[0-9]{1,2}(?:\\.[0-9]{1,2})?\\s?%?") else { return nil }
            let cleaned = match.trimmingCharacters(in: .whitespaces)
            return cleaned.hasSuffix("%") ? cleaned : cleaned + "%"

        case .date:
            let patterns = [
                "[0-9]{1,2}[/\\-\\.][0-9]{1,2}[/\\-\\.][0-9]{2,4}",
                "[0-9]{1,2}\\s+[A-Za-z]{3,9}\\s+[0-9]{4}",
                "[A-Za-z]{3,9}\\s+[0-9]{1,2},?\\s+[0-9]{4}"
            ]
            for pattern in patterns {
                if let match = firstMatch(in: trimmed, pattern: pattern) { return match }
            }
            return nil

        case .name:
            // Two to five words, letters only — enough to be a name and not a sentence.
            let words = trimmed.split(separator: " ").prefix(6)
            let letters = words.filter { $0.allSatisfy { $0.isLetter || $0 == "." } }
            guard letters.count >= 2, letters.count <= 5 else { return nil }
            return letters.joined(separator: " ")

        case .freeText:
            let value = String(trimmed.prefix(60))
            return value.count >= 2 ? value : nil
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text)
        else { return nil }
        return String(text[matchRange])
    }
}
