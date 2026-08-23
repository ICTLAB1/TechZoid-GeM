import SwiftUI

/// Everything the vault noticed that a person would rather be told than find
/// out later: a lapsed policy, an expired card, a policy with no nominee, one
/// password guarding three logins.
struct HealthCheckView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        let findings = store.healthFindings

        Group {
            if findings.isEmpty {
                EmptyStateView(
                    icon: "checkmark.seal.fill",
                    title: "Nothing needs attention",
                    message: "No lapsed renewals, no expired cards, nominees recorded, and no password used twice."
                )
            } else {
                List {
                    ForEach(grouped(findings), id: \.severity) { group in
                        Section {
                            ForEach(group.findings) { finding in
                                row(for: finding)
                            }
                        } header: {
                            Label(group.severity.label, systemImage: group.severity.icon)
                                .foregroundStyle(group.severity.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Check-up")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.sync() }
    }

    @ViewBuilder
    private func row(for finding: HealthFinding) -> some View {
        let destination = finding.itemID.flatMap { store.item(id: $0) }

        if let destination {
            NavigationLink(destination: ItemDetailView(itemID: destination.id)) {
                content(for: finding)
            }
        } else {
            content(for: finding)
        }
    }

    private func content(for finding: HealthFinding) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(finding.title)
                .font(.body)
            Text(finding.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private struct FindingGroup {
        var severity: FindingSeverity
        var findings: [HealthFinding]
    }

    private func grouped(_ findings: [HealthFinding]) -> [FindingGroup] {
        [FindingSeverity.critical, .warning, .suggestion].compactMap { severity in
            let matching = findings.filter { $0.severity == severity }
            return matching.isEmpty ? nil : FindingGroup(severity: severity, findings: matching)
        }
    }
}

