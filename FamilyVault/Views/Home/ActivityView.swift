import SwiftUI

/// What changed lately, on either phone.
///
/// In a vault two people share, this is how you notice that the other one
/// updated the net-banking password without having to be told.
struct ActivityView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        let entries = store.recentActivity()

        Group {
            if entries.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No activity yet",
                    message: "Every change either of you makes is logged here — which entry, which fields, and from which phone."
                )
            } else {
                List {
                    ForEach(grouped(entries), id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                NavigationLink(destination: ItemDetailView(itemID: entry.item.id)) {
                                    ActivityRow(entry: entry)
                                }
                            }
                        } header: {
                            Text(dayTitle(group.day))
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.sync() }
    }

    private struct DayGroup {
        var day: Date
        var entries: [ActivityEntry]
    }

    private func grouped(_ entries: [ActivityEntry]) -> [DayGroup] {
        let calendar = Calendar.current
        var buckets: [Date: [ActivityEntry]] = [:]
        for entry in entries {
            buckets[calendar.startOfDay(for: entry.event.at), default: []].append(entry)
        }
        return buckets
            .map { DayGroup(day: $0.key, entries: $0.value.sorted { $0.event.at > $1.event.at }) }
            .sorted { $0.day > $1.day }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .complete, time: .omitted)
    }
}

struct ActivityRow: View {
    var entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.event.kind.icon)
                .font(.title3)
                .foregroundStyle(entry.item.category.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                Text(entry.event.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(attribution)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var attribution: String {
        var parts = [entry.event.at.formatted(date: .omitted, time: .shortened)]
        if !entry.event.deviceName.isEmpty { parts.append(entry.event.deviceName) }
        return parts.joined(separator: " · ")
    }
}
