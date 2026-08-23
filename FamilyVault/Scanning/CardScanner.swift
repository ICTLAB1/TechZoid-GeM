import Foundation

/// Reads a payment card from the text Vision found on it.
///
/// The Luhn check is what makes this trustworthy: OCR routinely turns 8 into 3
/// on embossed plastic, and a wrong card number saved silently is worse than
/// no card number at all. A candidate that fails Luhn is discarded rather than
/// offered.
enum CardScanner {

    struct Result {
        var number: String?
        var expiry: String?
        var nameOnCard: String?
        var network: String?

        var isEmpty: Bool { number == nil && expiry == nil && nameOnCard == nil }
    }

    static func read(_ text: String) -> Result {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var result = Result()
        result.number = cardNumber(in: lines)
        result.expiry = expiry(in: lines)
        result.nameOnCard = nameOnCard(in: lines, excluding: result.number)
        if let number = result.number { result.network = network(for: number) }
        return result
    }

    // MARK: - Number

    private static func cardNumber(in lines: [String]) -> String? {
        for line in lines {
            let digits = line.filter(\.isNumber)
            guard (13...19).contains(digits.count) else { continue }
            // The line has to look like a card number, not a paragraph with digits in it.
            let nonDigits = line.filter { !$0.isNumber && !$0.isWhitespace && $0 != "-" }
            guard nonDigits.isEmpty else { continue }
            guard passesLuhn(digits) else { continue }
            return grouped(digits)
        }
        return nil
    }

    /// The checksum every card number satisfies.
    static func passesLuhn(_ digits: String) -> Bool {
        let values = digits.compactMap { $0.wholeNumberValue }
        guard values.count >= 13 else { return false }

        var sum = 0
        for (offset, digit) in values.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    private static func grouped(_ digits: String) -> String {
        var out = ""
        for (index, character) in digits.enumerated() {
            if index > 0, index % 4 == 0 { out.append(" ") }
            out.append(character)
        }
        return out
    }

    static func network(for number: String) -> String? {
        let digits = number.filter(\.isNumber)
        guard let first = digits.first else { return nil }
        let twoDigit = Int(digits.prefix(2)) ?? 0
        let fourDigit = Int(digits.prefix(4)) ?? 0

        if first == "4" { return "Visa" }
        if (51...55).contains(twoDigit) || (2221...2720).contains(fourDigit) { return "Mastercard" }
        if twoDigit == 34 || twoDigit == 37 { return "American Express" }
        if (60...65).contains(twoDigit) && digits.count == 16 { return "RuPay or Discover" }
        return nil
    }

    // MARK: - Expiry

    private static func expiry(in lines: [String]) -> String? {
        // Skip anything labelled as the *from* date — cards carry both.
        for line in lines {
            let lowered = line.lowercased()
            if lowered.contains("valid from") || lowered.contains("member since") { continue }
            guard let match = firstMatch(in: line, pattern: "(0[1-9]|1[0-2])\\s?/\\s?([0-9]{2}|[0-9]{4})") else { continue }
            let cleaned = match.replacingOccurrences(of: " ", with: "")
            let parts = cleaned.split(separator: "/")
            guard parts.count == 2 else { continue }
            let year = parts[1].count == 4 ? String(parts[1].suffix(2)) : String(parts[1])
            return "\(parts[0])/\(year)"
        }
        return nil
    }

    // MARK: - Name

    private static func nameOnCard(in lines: [String], excluding number: String?) -> String? {
        for line in lines.reversed() {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            guard cleaned.count >= 5, cleaned.count <= 30 else { continue }
            guard cleaned.allSatisfy({ $0.isLetter || $0 == " " || $0 == "." }) else { continue }

            let words = cleaned.split(separator: " ")
            guard words.count >= 2, words.count <= 4 else { continue }

            // Names are embossed in capitals; bank slogans rarely are.
            let uppercaseRatio = Double(cleaned.filter(\.isUppercase).count) / Double(max(cleaned.filter(\.isLetter).count, 1))
            guard uppercaseRatio > 0.8 else { continue }

            let lowered = cleaned.lowercased()
            let notNames = ["valid", "thru", "bank", "card", "credit", "debit", "platinum", "gold", "signature", "member", "since", "authorized", "signature panel"]
            guard !notNames.contains(where: { lowered.contains($0) }) else { continue }

            return cleaned
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text)
        else { return nil }
        return String(text[matchRange])
    }

    /// As `ExtractedField`s, so the review sheet handles cards like anything else.
    static func fields(from result: Result) -> [ExtractedField] {
        var fields: [ExtractedField] = []
        if let number = result.number {
            fields.append(ExtractedField(label: "Card number", value: number, confidence: 0.95, evidence: "Checksum verified"))
        }
        if let expiry = result.expiry {
            fields.append(ExtractedField(label: "Expiry (MM/YY)", value: expiry, confidence: 0.9, evidence: "Read from the card"))
        }
        if let name = result.nameOnCard {
            fields.append(ExtractedField(label: "Name on card", value: name, confidence: 0.75, evidence: "Read from the card"))
        }
        if let network = result.network {
            fields.append(ExtractedField(label: "Card type", value: network, confidence: 0.9, evidence: "From the number's prefix"))
        }
        return fields
    }
}
