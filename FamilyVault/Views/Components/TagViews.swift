import SwiftUI

/// Read-only tag chips that wrap onto as many lines as they need.
struct TagWrap: View {
    var tags: [String]
    var tint: Color = Theme.accent

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.12))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
            }
        }
    }
}

/// A plain left-to-right flow that wraps — SwiftUI has no built-in one, and an
/// HStack in a ScrollView would push long tag lists off the screen.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            let needed = current == 0 ? size.width : current + spacing + size.width

            if needed > maxWidth, current > 0 {
                rows.append(size.width)
                rowHeights.append(size.height)
            } else {
                rows[rows.count - 1] = needed
                rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
            }
        }

        let height = rowHeights.reduce(0, +) + spacing * CGFloat(max(rowHeights.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Tag editor: type to add, tap an existing tag to reuse it.
struct TagEditor: View {
    @Binding var tags: [String]
    var suggestions: [String]

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.accent.opacity(0.15))
                            .foregroundStyle(Theme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("Add a tag", text: $draft)
                    .autocorrectionDisabled()
                    .onSubmit(commit)
                    .submitLabel(.done)
                Button(action: commit) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            let unused = suggestions.filter { suggestion in
                !tags.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
            }
            if !unused.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(unused, id: \.self) { suggestion in
                            Button {
                                tags.append(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !value.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        tags.append(value)
    }
}
