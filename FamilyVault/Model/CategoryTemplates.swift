import Foundation

/// Starter field sets, so adding a policy or a card is filling a form rather
/// than inventing one. Every field stays editable, and extra fields can be
/// added to any item.
enum CategoryTemplates {

    static func fields(for category: ItemCategory) -> [ItemField] {
        switch category {
        case .bankAccount:
            [
                ItemField(label: "Bank", kind: .text),
                ItemField(label: "Account holder", kind: .text),
                ItemField(label: "Account number", kind: .secret),
                ItemField(label: "Account type", kind: .text),
                ItemField(label: "IFSC code", kind: .text),
                ItemField(label: "Branch", kind: .text),
                ItemField(label: "Customer ID", kind: .secret),
                ItemField(label: "Net banking username", kind: .secret),
                ItemField(label: "Net banking password", kind: .secret),
                ItemField(label: "Registered mobile", kind: .phone),
                ItemField(label: "UPI ID", kind: .text),
                ItemField(label: "Nominee", kind: .text)
            ]

        case .card:
            [
                ItemField(label: "Issuer", kind: .text),
                ItemField(label: "Card type", kind: .text),
                ItemField(label: "Name on card", kind: .text),
                ItemField(label: "Card number", kind: .secret),
                ItemField(label: "Expiry (MM/YY)", kind: .text),
                ItemField(label: "CVV", kind: .secret),
                ItemField(label: "ATM / card PIN", kind: .secret),
                ItemField(label: "Credit limit", kind: .money),
                ItemField(label: "Statement date", kind: .text),
                ItemField(label: "Payment due date", kind: .text),
                ItemField(label: "Linked bank account", kind: .text),
                ItemField(label: "Customer care", kind: .phone),
                ItemField(label: "Card portal login", kind: .secret)
            ]

        case .insurance:
            [
                ItemField(label: "Insurer", kind: .text),
                ItemField(label: "Policy type", kind: .text),
                ItemField(label: "Policy number", kind: .secret),
                ItemField(label: "Policy holder", kind: .text),
                ItemField(label: "Persons covered", kind: .text),
                ItemField(label: "Sum assured / cover", kind: .money),
                ItemField(label: "Premium amount", kind: .money),
                ItemField(label: "Premium frequency", kind: .text),
                ItemField(label: "Start date", kind: .date),
                ItemField(label: "Maturity date", kind: .date),
                ItemField(label: "Nominee", kind: .text),
                ItemField(label: "Agent / advisor", kind: .phone),
                ItemField(label: "Claim helpline", kind: .phone),
                ItemField(label: "Portal login", kind: .secret)
            ]

        case .investment:
            [
                ItemField(label: "Instrument", kind: .text),
                ItemField(label: "Institution / AMC", kind: .text),
                ItemField(label: "Folio / account number", kind: .secret),
                ItemField(label: "Held in the name of", kind: .text),
                ItemField(label: "Amount invested", kind: .money),
                ItemField(label: "Current value", kind: .money),
                ItemField(label: "Interest / return rate", kind: .text),
                ItemField(label: "Start date", kind: .date),
                ItemField(label: "Maturity date", kind: .date),
                ItemField(label: "Nominee", kind: .text),
                ItemField(label: "Portal login", kind: .secret)
            ]

        case .loan:
            [
                ItemField(label: "Lender", kind: .text),
                ItemField(label: "Loan type", kind: .text),
                ItemField(label: "Loan account number", kind: .secret),
                ItemField(label: "Borrower", kind: .text),
                ItemField(label: "Principal amount", kind: .money),
                ItemField(label: "Outstanding amount", kind: .money),
                ItemField(label: "Interest rate", kind: .text),
                ItemField(label: "EMI amount", kind: .money),
                ItemField(label: "EMI date", kind: .text),
                ItemField(label: "Tenure", kind: .text),
                ItemField(label: "Loan end date", kind: .date),
                ItemField(label: "Debit account", kind: .text),
                ItemField(label: "Customer care", kind: .phone),
                ItemField(label: "Portal login", kind: .secret)
            ]

        case .identity:
            [
                ItemField(label: "Document type", kind: .text),
                ItemField(label: "Name on document", kind: .text),
                ItemField(label: "Document number", kind: .secret),
                ItemField(label: "Date of birth", kind: .date),
                ItemField(label: "Issued on", kind: .date),
                ItemField(label: "Valid until", kind: .date),
                ItemField(label: "Issuing authority", kind: .text)
            ]

        case .document:
            [
                ItemField(label: "Document type", kind: .text),
                ItemField(label: "Issued by", kind: .text),
                ItemField(label: "In the name of", kind: .text),
                ItemField(label: "Reference number", kind: .secret),
                ItemField(label: "Issued on", kind: .date),
                ItemField(label: "Valid until", kind: .date),
                ItemField(label: "Where the original is kept", kind: .multiline)
            ]

        case .login:
            [
                ItemField(label: "Website / app", kind: .url),
                ItemField(label: "Username", kind: .text),
                ItemField(label: "Password", kind: .secret),
                ItemField(label: "Registered email", kind: .email),
                ItemField(label: "Registered mobile", kind: .phone),
                ItemField(label: "Security questions", kind: .multiline),
                ItemField(label: "Two-factor backup codes", kind: .secret)
            ]

        case .property:
            [
                ItemField(label: "Asset type", kind: .text),
                ItemField(label: "Description", kind: .text),
                ItemField(label: "Owner", kind: .text),
                ItemField(label: "Registration / document number", kind: .secret),
                ItemField(label: "Purchase date", kind: .date),
                ItemField(label: "Purchase value", kind: .money),
                ItemField(label: "Current value", kind: .money),
                ItemField(label: "Where documents are kept", kind: .multiline)
            ]

        case .note:
            [
                ItemField(label: "Detail", kind: .multiline),
                ItemField(label: "Secret", kind: .secret)
            ]
        }
    }

    /// A brand new item pre-filled with its template.
    static func newItem(category: ItemCategory) -> VaultItem {
        VaultItem(
            category: category,
            fields: fields(for: category),
            reminderRepeat: defaultRepeat(for: category)
        )
    }

    /// EMIs and card bills come round every month; policies usually once a
    /// year. Starting there means most entries need no thought at all.
    static func defaultRepeat(for category: ItemCategory) -> ReminderRepeat {
        switch category {
        case .loan, .card: .monthly
        case .insurance: .yearly
        default: .never
        }
    }

    /// The field naming the bank, insurer or lender behind an entry.
    static func institutionField(for category: ItemCategory) -> String {
        subtitleField(for: category)
    }

    /// The money figure worth naming in a reminder, when there is one.
    static func amountField(for category: ItemCategory) -> String? {
        switch category {
        case .loan: "EMI amount"
        case .insurance: "Premium amount"
        default: nil
        }
    }

    /// The field that should be unique per entry in a category — the same
    /// account number or policy number turning up twice almost always means
    /// the same real-world thing was added from two different scans.
    static func identifyingField(for category: ItemCategory) -> String? {
        switch category {
        case .bankAccount: "Account number"
        case .card: "Card number"
        case .insurance: "Policy number"
        case .investment: "Folio / account number"
        case .loan: "Loan account number"
        case .identity: "Document number"
        case .document: "Reference number"
        case .property: "Registration / document number"
        case .login, .note: nil
        }
    }

    /// Which field, if present, is worth showing under the title in lists.
    static func subtitleField(for category: ItemCategory) -> String {
        switch category {
        case .bankAccount: "Bank"
        case .card: "Issuer"
        case .insurance: "Insurer"
        case .investment: "Institution / AMC"
        case .loan: "Lender"
        case .identity: "Document type"
        case .document: "Issued by"
        case .login: "Username"
        case .property: "Asset type"
        case .note: "Detail"
        }
    }
}
