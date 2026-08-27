import Foundation

/// A plain-language reading of what a policy, loan or investment actually
/// gives you — assembled from the fields on the entry plus anything the
/// document itself said.
///
/// Written for the person who has to act on it, not the person who bought it:
/// the spouse holding the phone at the worst possible moment.
struct BenefitSummary {

    struct Line: Identifiable, Hashable {
        var id = UUID()
        var icon: String
        var text: String
        /// True when this came out of the document rather than a typed field.
        var fromDocument: Bool = false
    }

    var headline: String
    var lines: [Line]
    var caveat: String?

    var isEmpty: Bool { lines.isEmpty }

    static func build(for item: VaultItem) -> BenefitSummary? {
        switch item.category {
        case .insurance: insurance(item)
        case .loan: loan(item)
        case .investment: investment(item)
        default: nil
        }
    }

    // MARK: - Insurance

    private static func insurance(_ item: VaultItem) -> BenefitSummary? {
        var lines: [Line] = []

        let insurer = item.value(forLabel: "Insurer") ?? item.subtitle
        let cover = amount(item, "Sum assured / cover")
        let nominee = item.value(forLabel: "Nominee")
        let holder = item.value(forLabel: "Policy holder") ?? item.holder

        var headline = "This policy"
        if let cover {
            headline = "Pays \(MoneyValue.formatted(cover))"
            if let nominee { headline += " to \(nominee)" }
        }

        if let cover, let nominee {
            lines.append(Line(icon: "shield.lefthalf.filled",
                              text: "\(nominee) receives \(MoneyValue.formatted(cover)) on a valid claim."))
        } else if let cover {
            lines.append(Line(icon: "shield.lefthalf.filled",
                              text: "Cover of \(MoneyValue.formatted(cover)). No nominee is recorded — worth fixing with \(insurer.isEmpty ? "the insurer" : insurer)."))
        }

        if let covered = item.value(forLabel: "Persons covered") {
            lines.append(Line(icon: "person.2.fill", text: "Covers \(covered)."))
        } else if !holder.isEmpty {
            lines.append(Line(icon: "person.fill", text: "Held by \(holder)."))
        }

        if let premium = amount(item, "Premium amount") {
            let frequency = (item.value(forLabel: "Premium frequency") ?? "yearly").lowercased()
            var text = "Costs \(MoneyValue.formatted(premium)) \(frequency)"
            if let annual = annualised(premium: premium, frequency: frequency), annual != premium {
                text += " — \(MoneyValue.formatted(annual)) a year"
            }
            lines.append(Line(icon: "indianrupeesign.circle.fill", text: text + "."))
        }

        if let due = item.nextDueDate {
            let days = item.daysUntilReminder ?? 0
            let when = days < 0 ? "was due \(due.formatted(date: .abbreviated, time: .omitted)) — overdue"
                                : "due \(due.formatted(date: .abbreviated, time: .omitted))"
            lines.append(Line(icon: "bell.fill", text: "Next premium \(when)."))
        }

        if let maturity = item.value(forLabel: "Maturity date") {
            lines.append(Line(icon: "calendar", text: "Matures \(maturity)."))
        }

        if let helpline = item.value(forLabel: "Claim helpline") {
            lines.append(Line(icon: "phone.fill", text: "To claim, call \(helpline)\(insurer.isEmpty ? "" : " at \(insurer)")."))
        } else if let agent = item.value(forLabel: "Agent / advisor") {
            lines.append(Line(icon: "phone.fill", text: "Agent: \(agent)."))
        }

        lines.append(contentsOf: documentBenefits(item))

        guard !lines.isEmpty else { return nil }
        return BenefitSummary(
            headline: headline,
            lines: lines,
            caveat: "Put together from what's recorded here and read out of the attached documents. The policy wording is what actually decides a claim."
        )
    }

    // MARK: - Loan

    private static func loan(_ item: VaultItem) -> BenefitSummary? {
        var lines: [Line] = []
        let lender = item.value(forLabel: "Lender") ?? item.subtitle

        let outstanding = amount(item, "Outstanding amount") ?? amount(item, "Principal amount")
        var headline = "This loan"
        if let outstanding { headline = "\(MoneyValue.formatted(outstanding)) still owed" }

        if let outstanding {
            lines.append(Line(icon: "indianrupeesign.circle.fill",
                              text: "\(MoneyValue.formatted(outstanding)) outstanding\(lender.isEmpty ? "" : " to \(lender)")."))
        }
        if let emi = amount(item, "EMI amount") {
            var text = "EMI of \(MoneyValue.formatted(emi))"
            if let rate = item.value(forLabel: "Interest rate") { text += " at \(rate)" }
            if let account = item.value(forLabel: "Debit account") { text += ", debited from \(account)" }
            lines.append(Line(icon: "calendar", text: text + "."))
        }
        if let due = item.nextDueDate {
            let days = item.daysUntilReminder ?? 0
            lines.append(Line(icon: "bell.fill",
                              text: days < 0
                                ? "Next EMI was due \(due.formatted(date: .abbreviated, time: .omitted)) — overdue."
                                : "Next EMI due \(due.formatted(date: .abbreviated, time: .omitted))."))
        }
        if let tenure = item.value(forLabel: "Tenure") {
            lines.append(Line(icon: "clock", text: "Tenure \(tenure)."))
        }
        if let end = item.value(forLabel: "Loan end date") {
            lines.append(Line(icon: "checkmark.circle", text: "Clear on \(end)."))
        }
        if let paid = item.payments.first?.paidOn {
            lines.append(Line(icon: "arrow.counterclockwise",
                              text: "\(item.payments.count) payment\(item.payments.count == 1 ? "" : "s") recorded, most recently \(paid.formatted(date: .abbreviated, time: .omitted))."))
        }

        guard !lines.isEmpty else { return nil }
        return BenefitSummary(headline: headline, lines: lines, caveat: nil)
    }

    // MARK: - Investment

    private static func investment(_ item: VaultItem) -> BenefitSummary? {
        var lines: [Line] = []
        let invested = amount(item, "Amount invested")
        let current = amount(item, "Current value")

        var headline = "This investment"
        if let current { headline = "Worth \(MoneyValue.formatted(current)) today" }
        else if let invested { headline = "\(MoneyValue.formatted(invested)) invested" }

        if let invested, let current {
            let gain = current - invested
            lines.append(Line(icon: "chart.line.uptrend.xyaxis",
                              text: gain >= 0
                                ? "Up \(MoneyValue.formatted(gain)) on \(MoneyValue.formatted(invested)) put in."
                                : "Down \(MoneyValue.formatted(-gain)) on \(MoneyValue.formatted(invested)) put in."))
        } else if let invested {
            lines.append(Line(icon: "chart.line.uptrend.xyaxis", text: "\(MoneyValue.formatted(invested)) invested."))
        }
        if let rate = item.value(forLabel: "Interest / return rate") {
            lines.append(Line(icon: "percent", text: "Returns \(rate)."))
        }
        if let maturity = item.value(forLabel: "Maturity date") {
            lines.append(Line(icon: "calendar", text: "Matures \(maturity)."))
        }
        if let nominee = item.value(forLabel: "Nominee") {
            lines.append(Line(icon: "person.2.fill", text: "Goes to \(nominee)."))
        }

        guard !lines.isEmpty else { return nil }
        return BenefitSummary(headline: headline, lines: lines, caveat: nil)
    }

    // MARK: - Reading benefits out of the document itself

    /// Insurance documents name their benefits in fairly standard language.
    /// Anything found here is marked as coming from the document, so it is
    /// never mistaken for something that was checked and typed in.
    private static func documentBenefits(_ item: VaultItem) -> [Line] {
        let text = item.attachments.compactMap(\.extractedText).joined(separator: "\n").lowercased()
        guard !text.isEmpty else { return [] }

        let benefits: [(needle: String, phrase: String)] = [
            ("accidental death", "Includes an accidental death benefit."),
            ("critical illness", "Includes a critical illness benefit."),
            ("waiver of premium", "Includes waiver of premium."),
            ("maturity benefit", "Pays a maturity benefit if the policy runs its full term."),
            ("death benefit", "Pays a death benefit."),
            ("cashless", "Cashless treatment is available at network hospitals."),
            ("no claim bonus", "Carries a no-claim bonus."),
            ("pre-existing", "Has a pre-existing condition clause — check the waiting period."),
            ("waiting period", "Has a waiting period before some claims can be made."),
            ("room rent", "Caps room rent — worth knowing before admission."),
            ("co-payment", "Has a co-payment: part of every claim is yours to pay."),
            ("grace period", "Has a grace period for late premiums."),
            ("free look", "Has a free-look period for cancelling.")
        ]

        return benefits
            .filter { text.contains($0.needle) }
            .prefix(6)
            .map { Line(icon: "doc.text.magnifyingglass", text: $0.phrase, fromDocument: true) }
    }

    // MARK: - Helpers

    private static func amount(_ item: VaultItem, _ label: String) -> Decimal? {
        guard let text = item.value(forLabel: label) else { return nil }
        return MoneyValue.amount(from: text)
    }

    private static func annualised(premium: Decimal, frequency: String) -> Decimal? {
        if frequency.contains("month") { return premium * 12 }
        if frequency.contains("quarter") { return premium * 4 }
        if frequency.contains("half") || frequency.contains("semi") { return premium * 2 }
        return nil
    }

    /// Plain text, for sharing the summary out of the app.
    func plainText(title: String) -> String {
        var out = "\(title)\n\(headline)\n\n"
        out += lines.map { "• \($0.text)" }.joined(separator: "\n")
        if let caveat { out += "\n\n\(caveat)" }
        return out
    }
}
