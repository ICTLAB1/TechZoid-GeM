import SwiftUI
import UIKit

/// Turns the typed-in phone numbers, emails and links into things you can
/// actually tap. A claim helpline you have to copy and paste into the dialler
/// is a claim helpline you won't use.
enum FieldAction: Identifiable {
    case call(String)
    case message(String)
    case whatsApp(String)
    case email(String)
    case open(URL)

    var id: String {
        switch self {
        case .call(let value): "call-\(value)"
        case .message(let value): "sms-\(value)"
        case .whatsApp(let value): "wa-\(value)"
        case .email(let value): "mail-\(value)"
        case .open(let url): "open-\(url.absoluteString)"
        }
    }

    var label: String {
        switch self {
        case .call: "Call"
        case .message: "Message"
        case .whatsApp: "WhatsApp"
        case .email: "Email"
        case .open: "Open"
        }
    }

    var icon: String {
        switch self {
        case .call: "phone.fill"
        case .message: "message.fill"
        case .whatsApp: "bubble.left.and.bubble.right.fill"
        case .email: "envelope.fill"
        case .open: "safari.fill"
        }
    }

    var url: URL? {
        switch self {
        case .call(let value): URL(string: "tel://\(Self.dialable(value))")
        case .message(let value): URL(string: "sms://\(Self.dialable(value))")
        case .whatsApp(let value): URL(string: "https://wa.me/\(Self.dialable(value).replacingOccurrences(of: "+", with: ""))")
        case .email(let value): URL(string: "mailto:\(value.trimmingCharacters(in: .whitespaces))")
        case .open(let url): url
        }
    }

    static func dialable(_ value: String) -> String {
        value.filter { $0.isNumber || $0 == "+" }
    }

    /// What can be done with a given field, if anything.
    static func actions(for field: ItemField) -> [FieldAction] {
        let value = field.value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return [] }

        switch field.kind {
        case .phone:
            guard dialable(value).count >= 5 else { return [] }
            return [.call(value), .message(value), .whatsApp(value)]
        case .email:
            guard value.contains("@") else { return [] }
            return [.email(value)]
        case .url:
            return [resolvedURL(value)].compactMap { $0 }.map { FieldAction.open($0) }
        default:
            return []
        }
    }

    /// People type "hdfcbank.com", not "https://hdfcbank.com".
    private static func resolvedURL(_ value: String) -> URL? {
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return URL(string: value)
        }
        return URL(string: "https://\(value)")
    }

    func perform() {
        guard let url, UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

/// The row of tappable buttons shown under an actionable field.
struct FieldActionBar: View {
    var actions: [FieldAction]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                Button {
                    action.perform()
                } label: {
                    Label(action.label, systemImage: action.icon)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
    }
}
