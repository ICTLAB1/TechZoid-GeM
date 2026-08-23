import Foundation
import UIKit

/// A printable summary of what exists and where — the sheet you leave with a
/// nominee or in a safe, so someone who doesn't have the app (or the
/// passphrase) still knows which insurer to call.
///
/// Unlike everything else here, the output is plain, readable PDF. That is the
/// point of it, and why the UI puts the warning where it can't be missed.
enum EmergencySheet {

    struct Options {
        /// Replace secret values with a masked form (••••3417) rather than printing them.
        var maskSecrets = true
        var includeNotes = false
        var categories: Set<ItemCategory> = Set(ItemCategory.allCases)
        var heading = "Family financial summary"
        var preparedFor = ""
    }

    private enum Block {
        case title(String)
        case subtitle(String)
        case sectionHeading(String)
        case entryTitle(String)
        case row(String, String)
        case note(String)
        case spacer(CGFloat)
    }

    private static let pageSize = CGSize(width: 595, height: 842)   // A4 at 72dpi
    private static let margin: CGFloat = 48

    static func render(items: [VaultItem], options: Options) -> URL? {
        let blocks = build(items: items, options: options)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        let data = renderer.pdfData { context in
            var y = margin
            context.beginPage()

            for block in blocks {
                let height = self.height(of: block)
                if y + height > pageSize.height - margin {
                    context.beginPage()
                    y = margin
                }
                draw(block, at: y)
                y += height
            }
        }

        let name = "Vault-summary-\(stamp()).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Content

    private static func build(items: [VaultItem], options: Options) -> [Block] {
        var blocks: [Block] = [.title(options.heading)]

        if !options.preparedFor.isEmpty {
            blocks.append(.subtitle("Prepared for \(options.preparedFor)"))
        }
        blocks.append(.subtitle("Generated \(Date().formatted(date: .long, time: .shortened))"))
        blocks.append(.note(options.maskSecrets
            ? "Account and policy numbers are partly hidden. The full details are in the Vault app on our two phones."
            : "This sheet contains full account and policy numbers. Treat it like cash — keep it in a safe, not in a drawer."))
        blocks.append(.spacer(14))

        for category in ItemCategory.allCases where options.categories.contains(category) {
            let matching = items
                .filter { $0.category == category }
                .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            guard !matching.isEmpty else { continue }

            blocks.append(.sectionHeading(category.title.uppercased()))

            for item in matching {
                var heading = item.displayTitle
                if !item.holder.isEmpty { heading += "  —  \(item.holder)" }
                blocks.append(.entryTitle(heading))

                for field in item.filledFields {
                    let value = field.kind.isSecret && options.maskSecrets ? mask(field.value) : field.value
                    blocks.append(.row(field.label, value))
                }
                if let reminder = item.reminderDate {
                    blocks.append(.row(item.category.reminderLabel, reminder.formatted(date: .abbreviated, time: .omitted)))
                }
                if !item.attachments.isEmpty {
                    blocks.append(.row("Documents in the app", item.attachments.map(\.filename).joined(separator: ", ")))
                }
                if options.includeNotes, !item.notes.isEmpty {
                    blocks.append(.note(item.notes))
                }
                blocks.append(.spacer(10))
            }
            blocks.append(.spacer(8))
        }

        blocks.append(.spacer(10))
        blocks.append(.note("This is a summary, not a legal document. Original papers are wherever each entry says they are kept."))
        return blocks
    }

    /// ••••3417 — enough to recognise the account, not enough to use it.
    private static func mask(_ value: String) -> String {
        let visible = value.suffix(4)
        guard value.count > 4 else { return String(repeating: "\u{2022}", count: max(value.count, 4)) }
        return String(repeating: "\u{2022}", count: 4) + visible
    }

    // MARK: - Layout

    private static let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
    private static let subtitleFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    private static let sectionFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
    private static let entryFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    private static let labelFont = UIFont.systemFont(ofSize: 11, weight: .medium)

    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private static var labelWidth: CGFloat { 170 }

    private static func height(of block: Block) -> CGFloat {
        switch block {
        case .title: 34
        case .subtitle: 16
        case .sectionHeading: 28
        case .entryTitle: 22
        case .row(_, let value):
            max(16, textHeight(value, font: bodyFont, width: contentWidth - labelWidth - 8) + 4)
        case .note(let text):
            textHeight(text, font: subtitleFont, width: contentWidth) + 8
        case .spacer(let amount): amount
        }
    }

    private static func draw(_ block: Block, at y: CGFloat) {
        switch block {
        case .title(let text):
            text.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont, .foregroundColor: UIColor.black])

        case .subtitle(let text):
            text.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: subtitleFont, .foregroundColor: UIColor.darkGray])

        case .sectionHeading(let text):
            text.draw(at: CGPoint(x: margin, y: y + 8), withAttributes: [
                .font: sectionFont,
                .foregroundColor: UIColor.darkGray,
                .kern: 0.8
            ])
            let line = UIBezierPath(rect: CGRect(x: margin, y: y + 24, width: contentWidth, height: 0.5))
            UIColor.lightGray.setFill()
            line.fill()

        case .entryTitle(let text):
            text.draw(at: CGPoint(x: margin, y: y + 4), withAttributes: [.font: entryFont, .foregroundColor: UIColor.black])

        case .row(let label, let value):
            label.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: labelFont, .foregroundColor: UIColor.darkGray])
            value.draw(
                with: CGRect(x: margin + labelWidth, y: y, width: contentWidth - labelWidth, height: 400),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: bodyFont, .foregroundColor: UIColor.black],
                context: nil
            )

        case .note(let text):
            text.draw(
                with: CGRect(x: margin, y: y + 2, width: contentWidth, height: 400),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: subtitleFont, .foregroundColor: UIColor.darkGray],
                context: nil
            )

        case .spacer:
            break
        }
    }

    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounding.height)
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
