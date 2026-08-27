import Charts
import SwiftUI

/// The whole financial picture on one screen, built from the money fields
/// people already fill in — nothing extra to maintain.
struct SummaryView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        List {
            let summary = store.summary
            let history = store.netWorthHistory()

            if history.count >= 2 {
                Section {
                    Chart(history) { snapshot in
                        LineMark(
                            x: .value("Month", snapshot.month, unit: .month),
                            y: .value("Net worth", snapshot.netWorth)
                        )
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.monotone)

                        AreaMark(
                            x: .value("Month", snapshot.month, unit: .month),
                            y: .value("Net worth", snapshot.netWorth)
                        )
                        .foregroundStyle(Theme.accent.opacity(0.12))
                        .interpolationMethod(.monotone)
                    }
                    .chartYAxis {
                        AxisMarks { _ in AxisGridLine() }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        }
                    }
                    .frame(height: 160)
                    .padding(.vertical, 6)
                } header: {
                    Text("Net worth over time")
                } footer: {
                    Text("Investments at current value, minus loans outstanding. Recorded once a month from what's in the vault right now.")
                }
            }

            Section {
                MoneyRow(label: "Total life & health cover", value: summary.insuranceCover, tint: ItemCategory.insurance.tint)
                MoneyRow(label: "Premiums, per year", value: summary.annualPremium, tint: ItemCategory.insurance.tint)
                if summary.annualPremium > 0 {
                    MoneyRow(label: "Premiums, per month", value: summary.annualPremium / Decimal(12), tint: .secondary)
                }
            } header: {
                Text("Protection")
            } footer: {
                Text("Across \(summary.policyCount) polic\(summary.policyCount == 1 ? "y" : "ies"). Monthly, quarterly and half-yearly premiums are converted to a yearly figure.")
            }

            Section {
                MoneyRow(label: "Amount invested", value: summary.invested, tint: ItemCategory.investment.tint)
                MoneyRow(label: "Current value", value: summary.currentValue, tint: ItemCategory.investment.tint)
                if summary.invested > 0 {
                    HStack {
                        Text(summary.investmentGain >= 0 ? "Gain" : "Loss")
                        Spacer()
                        Text(MoneyValue.formatted(abs(summary.investmentGain)))
                            .foregroundStyle(summary.investmentGain >= 0 ? Color.green : Color.red)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Holdings")
            } footer: {
                Text("Across \(summary.investmentCount) investment\(summary.investmentCount == 1 ? "" : "s"). Entries with no current value counted at what was put in.")
            }

            Section {
                MoneyRow(label: "Outstanding", value: summary.loanOutstanding, tint: ItemCategory.loan.tint)
                MoneyRow(label: "EMIs, per month", value: summary.monthlyEMI, tint: ItemCategory.loan.tint)
            } header: {
                Text("Borrowings")
            } footer: {
                Text("Across \(summary.loanCount) loan\(summary.loanCount == 1 ? "" : "s").")
            }

            Section {
                MoneyRow(label: "Total credit limit", value: summary.creditLimit, tint: ItemCategory.card.tint)
                LabeledContent("Cards", value: "\(summary.cardCount)")
                LabeledContent("Bank accounts", value: "\(summary.accountCount)")
            } header: {
                Text("Cards & accounts")
            }

            Section {
                LabeledContent("Entries", value: "\(store.items.count)")
                LabeledContent("Documents stored", value: "\(store.attachmentCount)")
            } header: {
                Text("Vault")
            } footer: {
                Text("These totals are worked out on this iPhone from the amounts you typed. Nothing is fetched from any bank.")
            }
        }
        .navigationTitle("At a glance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MoneyRow: View {
    var label: String
    var value: Decimal
    var tint: Color

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value == 0 ? "—" : MoneyValue.formatted(value))
                .foregroundStyle(value == 0 ? Color.secondary : tint)
                .monospacedDigit()
        }
    }
}
