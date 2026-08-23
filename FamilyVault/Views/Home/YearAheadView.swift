import SwiftUI

/// The next twelve months of premiums, EMIs, bills and maturities, month by
/// month — the view that answers "what does the year cost?"
struct YearAheadView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        let months = store.yearAhead()

        Group {
            if months.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "Nothing due in the next year",
                    message: "Give a policy its renewal date or a loan its EMI date and it will show up here."
                )
            } else {
                List {
                    ForEach(months) { month in
                        Section {
                            ForEach(month.items) { item in
                                NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                                    DueRow(item: item)
                                }
                            }
                        } header: {
                            HStack {
                                Text(month.title)
                                if month.isCurrentMonth {
                                    Text("this month")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                if let total = monthTotal(month), total > 0 {
                                    Text(MoneyValue.compact(total))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Year ahead")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Only counts entries that carry an amount, so a month with an untyped
    /// premium doesn't quietly read as cheaper than it is.
    private func monthTotal(_ month: DueMonth) -> Decimal? {
        var total = Decimal(0)
        for item in month.items {
            guard let label = CategoryTemplates.amountField(for: item.category),
                  let text = item.value(forLabel: label),
                  let amount = MoneyValue.amount(from: text)
            else { continue }
            total += amount
        }
        return total
    }
}

struct DueRow: View {
    var item: VaultItem

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isOverdue ? Color.red : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let amount = amountText {
                Text(amount)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isOverdue: Bool { (item.daysUntilReminder ?? 0) < 0 }

    private var subtitle: String {
        guard let due = item.nextDueDate else { return "" }
        var parts = [due.formatted(.dateTime.day().month(.abbreviated))]
        if !item.holder.isEmpty { parts.append(item.holder) }
        if !item.subtitle.isEmpty { parts.append(item.subtitle) }
        if isOverdue { parts.insert("Overdue", at: 0) }
        return parts.joined(separator: " · ")
    }

    private var amountText: String? {
        guard let label = CategoryTemplates.amountField(for: item.category),
              let text = item.value(forLabel: label)
        else { return nil }
        return MoneyValue.display(text)
    }
}
