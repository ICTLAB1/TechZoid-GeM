import SwiftUI

/// What a policy, loan or investment actually gives you, in sentences.
///
/// Nobody reads a 40-page policy bond at the moment they need it, and the
/// person who most needs to understand it is usually not the person who bought
/// it. This is the version that can be read in ten seconds and sent on.
struct BenefitSummaryCard: View {
    var item: VaultItem
    var summary: BenefitSummary

    @State private var shareFile: BackupFile?
    @State private var shareError: String?

    var body: some View {
        CardSection(title: "What this gives you", footnote: summary.caveat) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(summary.headline)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        share()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Share this summary")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ForEach(summary.lines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: line.icon)
                            .font(.footnote)
                            .foregroundStyle(line.fromDocument ? Color.secondary : item.category.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            if line.fromDocument {
                                Text("from the attached document")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Summary", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
    }

    private func share() {
        let text = summary.plainText(title: item.displayTitle)
        let name = item.displayTitle.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) — summary.txt")
        do {
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            shareFile = BackupFile(url: url)
        } catch {
            shareError = error.localizedDescription
        }
    }
}
