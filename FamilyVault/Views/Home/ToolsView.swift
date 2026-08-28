import SwiftUI

/// The views that answer a question rather than hold a record.
///
/// These used to exist twice — once on the dashboard and again inside
/// Settings — which left Settings holding sixteen destinations and no clear
/// line between "look something up" and "configure the app". They live here
/// now, in one place, and Settings went back to being settings.
struct ToolsView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ToolRow(
                        title: "Documents",
                        detail: documentsDetail,
                        icon: "doc.on.doc.fill",
                        badge: store.attachmentCount > 0 ? "\(store.attachmentCount)" : nil
                    ) { DocumentsLibraryView() }

                    ToolRow(
                        title: "Check-up",
                        detail: "What needs attention: gaps, weak spots, things lapsing",
                        icon: "stethoscope",
                        tint: urgentFindings > 0 ? .red : Theme.accent,
                        badge: urgentFindings > 0 ? "\(urgentFindings)" : nil,
                        badgeEmphasis: .urgent
                    ) { HealthCheckView() }

                    ToolRow(
                        title: "Year ahead",
                        detail: "What's due, month by month",
                        icon: "calendar"
                    ) { YearAheadView() }
                } header: {
                    Text("Keep on top")
                }

                Section {
                    ToolRow(
                        title: "At a glance",
                        detail: "Cover, balances and net worth in one place",
                        icon: "chart.pie.fill"
                    ) { SummaryView() }

                    ToolRow(
                        title: "Important numbers",
                        detail: "Every helpline and agent, tap to call",
                        icon: "phone.fill"
                    ) { ContactsView() }

                    ToolRow(
                        title: "Nominees",
                        detail: "Who inherits what, and what has nobody",
                        icon: "person.2.fill"
                    ) { NomineesView() }
                } header: {
                    Text("Understand")
                }

                Section {
                    if !store.allTags.isEmpty {
                        ToolRow(
                            title: "Tags",
                            detail: store.allTags.prefix(3).joined(separator: ", "),
                            icon: "tag.fill"
                        ) { TagsView() }
                    }

                    ToolRow(
                        title: "Recent activity",
                        detail: "What changed, on either phone",
                        icon: "clock.arrow.circlepath"
                    ) { ActivityView() }
                } header: {
                    Text("Trace")
                }
            }
            .navigationTitle("Tools")
        }
    }

    private var documentsDetail: String {
        store.attachmentCount == 0
            ? "Scan or attach a policy, a statement, a deed"
            : "Every file in the vault, all shareable"
    }

    private var urgentFindings: Int {
        store.healthFindings.filter { $0.severity != .suggestion }.count
    }
}
