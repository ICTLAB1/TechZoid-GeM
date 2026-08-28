import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var session: VaultSession
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminders: ReminderScheduler

    @State private var newItemCategory: ItemCategory?
    @State private var showingCategoryPicker = false
    @State private var justCreatedItem: VaultItem?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    heroHeader

                    SyncStatusBar()

                    if !gettingStartedComplete {
                        GettingStartedCard(onAddEntry: { showingCategoryPicker = true })
                    }

                    if !store.summary.isEmpty {
                        summarySection
                    }

                    if !urgentFindings.isEmpty {
                        healthSection
                    }

                    if !store.upcomingReminders(within: 60).isEmpty {
                        remindersSection
                    }

                    if !store.favourites.isEmpty {
                        favouritesSection
                    }

                    categoriesSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCategoryPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add an entry")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        session.lock()
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .accessibilityLabel("Lock now")
                }
            }
            .refreshable { await store.sync() }
            .confirmationDialog("What are you adding?", isPresented: $showingCategoryPicker, titleVisibility: .visible) {
                ForEach(ItemCategory.allCases) { category in
                    Button(category.singular) { newItemCategory = category }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $newItemCategory) { category in
                ItemEditorView(
                    item: CategoryTemplates.newItem(category: category),
                    isNew: true,
                    onSaved: { justCreatedItem = $0 }
                )
            }
            .sheet(item: $justCreatedItem) { item in
                NavigationStack { ItemDetailView(itemID: item.id) }
            }
        }
    }

    // MARK: - Sections

    /// The page's headline: what the vault holds, in three figures.
    ///
    /// The screen used to open with a plain "Vault" navigation title and go
    /// straight into cards, which told you nothing at a glance.
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.content) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Your family vault")
                    .font(Theme.Typography.hero)
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 0) {
                StatTile(
                    value: "\(store.items.count)",
                    label: store.items.count == 1 ? "entry" : "entries",
                    icon: "square.stack.3d.up.fill",
                    tint: Theme.accent
                )
                statDivider
                StatTile(
                    value: "\(store.attachmentCount)",
                    label: store.attachmentCount == 1 ? "document" : "documents",
                    icon: "doc.on.doc.fill",
                    tint: ItemCategory.document.tint
                )
                statDivider
                StatTile(
                    value: "\(store.upcomingReminders(within: 60).count)",
                    label: "due soon",
                    icon: "bell.fill",
                    tint: ItemCategory.investment.tint
                )
            }
            .vaultCard()
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.5, height: 34)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<5: "Late night"
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var gettingStartedComplete: Bool {
        !store.items.isEmpty && store.devices.count >= 2 && settings.remindersEnabled && reminders.isAuthorized
    }

    private var urgentFindings: [HealthFinding] {
        store.healthFindings.filter { $0.severity != .suggestion }
    }

    private var summarySection: some View {
        NavigationLink(destination: SummaryView()) {
            SummaryCard(summary: store.summary)
        }
        .buttonStyle(.plain)
    }

    private var healthSection: some View {
        NavigationLink(destination: HealthCheckView()) {
            let critical = urgentFindings.filter { $0.severity == .critical }.count
            HStack(spacing: 12) {
                Image(systemName: critical > 0 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(critical > 0 ? Color.red : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(critical > 0 ? "\(critical) thing\(critical == 1 ? "" : "s") need attention" : "\(urgentFindings.count) thing\(urgentFindings.count == 1 ? "" : "s") worth checking")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Lapsed renewals, expired cards, missing nominees, reused passwords")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.Spacing.content)
            .vaultCard()
        }
        .buttonStyle(.plain)
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Coming up", detail: "next 60 days")

            VStack(spacing: 0) {
                let items = store.upcomingReminders(within: 60)
                ForEach(items) { item in
                    NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                        ReminderRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if item.id != items.last?.id { RowDivider() }
                }
            }
            .vaultCard()
        }
    }

    private var favouritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Pinned")

            VStack(spacing: 0) {
                ForEach(store.favourites) { item in
                    NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                        ItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if item.id != store.favourites.last?.id { RowDivider() }
                }
            }
            .vaultCard()
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Everything in here", detail: "\(store.items.count) entries")
            categoryGrid
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ItemCategory.allCases) { category in
                NavigationLink(destination: CategoryItemsView(category: category)) {
                    CategoryTile(category: category, count: store.count(in: category))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CategoryTile: View {
    var category: ItemCategory
    var count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            HStack(alignment: .top) {
                CategoryBadge(category: category, size: 38)
                Spacer()
                // The count reads as the tile's headline, in the category's
                // own colour, rather than as grey small print underneath.
                Text("\(count)")
                    .font(Theme.Typography.stat)
                    .foregroundStyle(count == 0 ? Color.secondary : category.tint)
            }

            Spacer(minLength: 0)

            Text(category.title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(count == 1 ? "1 entry" : "\(count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .padding(Theme.Spacing.content)
        .vaultCard(tint: count == 0 ? nil : category.tint)
    }
}

struct ItemRow: View {
    var item: VaultItem

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if item.isFavourite {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct ReminderRow: View {
    var item: VaultItem

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !attribution.isEmpty {
                    Text(attribution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(dueText)
                    .font(.caption)
                    .foregroundStyle(isOverdue ? Color.red : .secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var isOverdue: Bool { (item.daysUntilReminder ?? 0) < 0 }

    private var dueText: String {
        guard let days = item.daysUntilReminder, let date = item.nextDueDate else { return "" }
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        switch days {
        case ..<0: return "Overdue — was \(formatted)"
        case 0: return "\(item.category.reminderLabel) is today"
        case 1: return "\(item.category.reminderLabel) tomorrow"
        default: return "\(item.category.reminderLabel) in \(days) days — \(formatted)"
        }
    }

    /// "Priya · HDFC Bank" under the title, so the list answers "whose, and
    /// with whom" without opening anything.
    private var attribution: String {
        [item.holder, item.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct SyncStatusBar: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if store.syncState.isSyncing {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var icon: String {
        switch store.syncState {
        case .failed: "exclamationmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .idle: store.pendingChangeCount > 0 ? "icloud.and.arrow.up" : "checkmark.icloud"
        }
    }

    private var tint: Color {
        if case .failed = store.syncState { return .orange }
        return Theme.accent
    }

    private var text: String {
        switch store.syncState {
        case .failed(let message): return message
        case .syncing: return "Syncing with your other iPhone…"
        case .idle:
            if store.pendingChangeCount > 0 {
                return "\(store.pendingChangeCount) change\(store.pendingChangeCount == 1 ? "" : "s") waiting to sync"
            }
            if let last = store.lastSyncedAt {
                return "Up to date · \(last.formatted(date: .omitted, time: .shortened))"
            }
            return "Up to date"
        }
    }
}


/// Compact money picture on the home screen: cover, holdings, what's owed.
struct SummaryCard: View {
    var summary: VaultSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AT A GLANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                SummaryTile(label: "Cover", value: summary.insuranceCover, tint: ItemCategory.insurance.tint)
                SummaryTile(label: "Investments", value: summary.currentValue, tint: ItemCategory.investment.tint)
                SummaryTile(label: "Owed", value: summary.loanOutstanding, tint: ItemCategory.loan.tint)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

struct SummaryTile: View {
    var label: String
    var value: Decimal
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value == 0 ? "\u{2014}" : MoneyValue.compact(value))
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
