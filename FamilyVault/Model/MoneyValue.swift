import Foundation

/// Money fields are stored as whatever the user typed. This turns that text
/// into a number when it can, and back into something readable when it can't
/// be left as-is — which is what makes the totals on the summary screen work
/// without forcing a rigid input format.
enum MoneyValue {

    static func amount(from text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: "\u{20B9}", with: "")   // ₹
            .replacingOccurrences(of: "Rs.", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Rs", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "INR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }

        // Accept shorthand people actually write: "5L", "1.2 Cr", "50k".
        let lowered = cleaned.lowercased()
        for (suffix, multiplier) in [("cr", Decimal(10_000_000)), ("l", Decimal(100_000)), ("k", Decimal(1_000))] {
            if lowered.hasSuffix(suffix) {
                let number = String(lowered.dropLast(suffix.count))
                if let base = Decimal(string: number) { return base * multiplier }
            }
        }
        return Decimal(string: cleaned)
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func formatted(_ amount: Decimal) -> String {
        currencyFormatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    /// Tiles have no room for ₹1,25,00,000 — show ₹1.25 Cr instead.
    static func compact(_ amount: Decimal) -> String {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        let absolute = abs(value)
        switch absolute {
        case 10_000_000...:
            return "\u{20B9}\(trim(value / 10_000_000)) Cr"
        case 100_000...:
            return "\u{20B9}\(trim(value / 100_000)) L"
        case 1_000...:
            return "\u{20B9}\(trim(value / 1_000))K"
        default:
            return formatted(amount)
        }
    }

    private static func trim(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%.2f", rounded).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    /// Displayed value for a money field: formatted when it parses, untouched
    /// when the user wrote something the parser shouldn't second-guess.
    static func display(_ text: String) -> String {
        guard let amount = amount(from: text) else { return text }
        return formatted(amount)
    }
}
