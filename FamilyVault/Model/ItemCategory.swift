import SwiftUI

enum ItemCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case bankAccount
    case card
    case insurance
    case investment
    case loan
    case identity
    case login
    case property
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bankAccount: "Bank Accounts"
        case .card: "Cards"
        case .insurance: "Insurance"
        case .investment: "Investments"
        case .loan: "Loans & EMIs"
        case .identity: "Identity Documents"
        case .login: "Logins"
        case .property: "Property & Assets"
        case .note: "Secure Notes"
        }
    }

    var singular: String {
        switch self {
        case .bankAccount: "Bank Account"
        case .card: "Card"
        case .insurance: "Policy"
        case .investment: "Investment"
        case .loan: "Loan"
        case .identity: "Document"
        case .login: "Login"
        case .property: "Asset"
        case .note: "Note"
        }
    }

    var icon: String {
        switch self {
        case .bankAccount: "building.columns.fill"
        case .card: "creditcard.fill"
        case .insurance: "shield.lefthalf.filled"
        case .investment: "chart.line.uptrend.xyaxis"
        case .loan: "indianrupeesign.circle.fill"
        case .identity: "person.text.rectangle.fill"
        case .login: "key.fill"
        case .property: "house.fill"
        case .note: "note.text"
        }
    }

    var tint: Color {
        switch self {
        case .bankAccount: Color(red: 0.20, green: 0.44, blue: 0.85)
        case .card: Color(red: 0.55, green: 0.31, blue: 0.83)
        case .insurance: Color(red: 0.13, green: 0.60, blue: 0.47)
        case .investment: Color(red: 0.90, green: 0.55, blue: 0.13)
        case .loan: Color(red: 0.84, green: 0.29, blue: 0.33)
        case .identity: Color(red: 0.24, green: 0.55, blue: 0.62)
        case .login: Color(red: 0.42, green: 0.45, blue: 0.52)
        case .property: Color(red: 0.55, green: 0.42, blue: 0.24)
        case .note: Color(red: 0.36, green: 0.38, blue: 0.44)
        }
    }

    /// Label used for the item's date reminder, per category.
    var reminderLabel: String {
        switch self {
        case .insurance: "Renewal date"
        case .investment: "Maturity date"
        case .loan: "Next EMI date"
        case .card: "Payment due date"
        case .identity: "Expiry date"
        default: "Reminder date"
        }
    }
}
