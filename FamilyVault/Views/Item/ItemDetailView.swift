import SwiftUI

struct ItemDetailView: View {
    var itemID: UUID

    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var confirmingDelete = false
    @State private var viewingAttachment: ItemAttachment?
    @State private var attachmentPendingRemoval: ItemAttachment?
    @State private var isRecordingPayment = false
    @State private var showingAllHistory = false
    @State private var paymentPendingRemoval: PaymentRecord?

    var body: some View {
        Group {
            if let item = store.item(id: itemID) {
                content(for: item)
            } else {
                EmptyStateView(icon: "trash", title: "Entry removed", message: "This entry was deleted.")
            }
        }
    }

    @ViewBuilder
    private func content(for item: VaultItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(for: item)

                if let summary = BenefitSummary.build(for: item), !summary.isEmpty {
                    BenefitSummaryCard(item: item, summary: summary)
                }

                if !item.filledFields.isEmpty {
                    CardSection(title: "Details") {
                        let fields = item.filledFields
                        ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                            FieldRow(
                                field: field,
                                clipboardClearSeconds: settings.clipboardClearSeconds,
                                requireBiometricsToReveal: settings.requireBiometricsToReveal
                            )
                            if index < fields.count - 1 { RowDivider() }
                        }
                    }
                }

                if let reminderDate = item.nextDueDate {
                    CardSection(title: item.category.reminderLabel) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(dueTint(for: item))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(reminderDate.formatted(date: .long, time: .omitted))
                                    if item.reminderRepeat != .never {
                                        Text(item.reminderRepeat.shortLabel)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.accent.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(dueDescription(for: item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)

                        if isPayable(item) {
                            RowDivider()
                            Button {
                                isRecordingPayment = true
                            } label: {
                                HStack {
                                    Label("Mark this one as paid", systemImage: "checkmark.circle")
                                    Spacer()
                                }
                                .padding(16)
                            }
                        }
                    }
                }

                if !item.payments.isEmpty {
                    paymentsSection(for: item)
                }

                if !item.tags.isEmpty {
                    CardSection(title: "Tags") {
                        TagWrap(tags: item.tags)
                            .padding(16)
                    }
                }

                CardSection(
                    title: "Documents",
                    footnote: item.attachments.isEmpty
                        ? "Scan the policy papers, or add a PDF you already have. Vault reads it on the phone and fills in what it can."
                        : nil
                ) {
                    if !item.attachments.isEmpty {
                        AttachmentGrid(
                            item: item,
                            onOpen: { viewingAttachment = $0 },
                            onDelete: { attachmentPendingRemoval = $0 }
                        )
                        RowDivider()
                    }
                    AttachmentPicker(item: item)
                }

                if !item.notes.isEmpty {
                    CardSection(title: "Notes") {
                        Text(item.notes)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(16)
                    }
                }

                if !item.history.isEmpty {
                    historySection(for: item)
                }

                CardSection(footnote: provenance(for: item)) {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        HStack {
                            Label("Delete entry", systemImage: "trash")
                            Spacer()
                        }
                        .padding(16)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.content)
            // Clear the floating tab bar, which sits over this screen too.
            .padding(.bottom, Theme.Spacing.section * 2)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleFavourite(item)
                } label: {
                    Image(systemName: item.isFavourite ? "pin.fill" : "pin")
                }
                .accessibilityLabel(item.isFavourite ? "Unpin" : "Pin to home")
            }
        }
        .sheet(isPresented: $isEditing) {
            ItemEditorView(item: item, isNew: false)
        }
        .sheet(item: $viewingAttachment) { attachment in
            AttachmentViewer(attachment: attachment)
        }
        .sheet(isPresented: $isRecordingPayment) {
            RecordPaymentView(item: item)
        }
        .confirmationDialog(
            "Remove this payment record?",
            isPresented: Binding(get: { paymentPendingRemoval != nil }, set: { if !$0 { paymentPendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let payment = paymentPendingRemoval { store.deletePayment(payment, from: item) }
                paymentPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { paymentPendingRemoval = nil }
        } message: {
            Text("The due date moves back to that instalment.")
        }
        .confirmationDialog("Delete “\(item.displayTitle)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Recently Deleted on both phones, and is destroyed for good after \(VaultStore.trashRetentionDays) days.")
        }
        .confirmationDialog(
            "Remove “\(attachmentPendingRemoval?.filename ?? "")”?",
            isPresented: Binding(get: { attachmentPendingRemoval != nil }, set: { if !$0 { attachmentPendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let attachment = attachmentPendingRemoval {
                    store.removeAttachment(attachment, from: item)
                }
                attachmentPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { attachmentPendingRemoval = nil }
        } message: {
            Text("This deletes the file from both phones straight away.")
        }
    }

    /// Only the things that actually get paid on a schedule.
    private func isPayable(_ item: VaultItem) -> Bool {
        switch item.category {
        case .loan, .insurance, .card: true
        default: false
        }
    }

    private func paymentsSection(for item: VaultItem) -> some View {
        CardSection(
            title: "Payments",
            footnote: "\(item.payments.count) recorded. Swipe a row to remove one."
        ) {
            let payments = item.paymentsByRecency
            ForEach(Array(payments.prefix(6).enumerated()), id: \.element.id) { index, payment in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payment.displayAmount ?? "Paid")
                            .font(.body)
                        Text(paymentSubtitle(payment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !payment.note.isEmpty {
                            Text(payment.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        paymentPendingRemoval = payment
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                if index < min(payments.count, 6) - 1 { RowDivider() }
            }
        }
    }

    private func paymentSubtitle(_ payment: PaymentRecord) -> String {
        var parts = ["Paid \(payment.paidOn.formatted(date: .abbreviated, time: .omitted))"]
        if let due = payment.dueDate {
            parts.append("for \(due.formatted(date: .abbreviated, time: .omitted))")
        }
        if !payment.recordedBy.isEmpty { parts.append("on \(payment.recordedBy)") }
        return parts.joined(separator: " · ")
    }

    private func historySection(for item: VaultItem) -> some View {
        let events = item.recentHistory
        let shown = showingAllHistory ? events : Array(events.prefix(4))

        return CardSection(title: "History") {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: event.kind.icon)
                        .foregroundStyle(item.category.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.summary)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(eventAttribution(event))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                if index < shown.count - 1 { RowDivider() }
            }

            if events.count > 4 {
                RowDivider()
                Button {
                    withAnimation { showingAllHistory.toggle() }
                } label: {
                    HStack {
                        Text(showingAllHistory ? "Show less" : "Show all \(events.count)")
                        Spacer()
                    }
                    .padding(16)
                }
            }
        }
    }

    private func eventAttribution(_ event: ItemEvent) -> String {
        var parts = [event.at.formatted(date: .abbreviated, time: .shortened)]
        if !event.deviceName.isEmpty { parts.append(event.deviceName) }
        return parts.joined(separator: " · ")
    }

    private func header(for item: VaultItem) -> some View {
        HStack(spacing: 14) {
            CategoryBadge(category: item.category, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.title3.weight(.semibold))
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !item.holder.isEmpty {
                    Label(item.holder, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
    }

    private func dueTint(for item: VaultItem) -> Color {
        guard let days = item.daysUntilReminder else { return Theme.accent }
        if days < 0 { return .red }
        if days <= 14 { return .orange }
        return Theme.accent
    }

    private func dueDescription(for item: VaultItem) -> String {
        guard let days = item.daysUntilReminder else { return "" }
        let lead = "Reminder \(item.reminderLeadDays) day\(item.reminderLeadDays == 1 ? "" : "s") before"
        switch days {
        case ..<0: return "Overdue by \(abs(days)) day\(abs(days) == 1 ? "" : "s") · \(lead)"
        case 0: return "Due today · \(lead)"
        default: return "In \(days) day\(days == 1 ? "" : "s") · \(lead)"
        }
    }

    private func provenance(for item: VaultItem) -> String {
        var parts = ["Last changed \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))"]
        if !item.lastEditedBy.isEmpty { parts.append("on \(item.lastEditedBy)") }
        parts.append("· added \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
        return parts.joined(separator: " ")
    }
}
