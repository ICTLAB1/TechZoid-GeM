import SwiftUI

enum Theme {
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.72)

    static let cardCornerRadius: CGFloat = 16

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.07) : Color(red: 0.96, green: 0.96, blue: 0.97)
    }
}

/// Card container used across the dashboard and detail screens.
struct CardSection<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            VStack(spacing: 0) { content }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

struct CategoryBadge: View {
    var category: ItemCategory
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: category.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.tint.gradient)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Covers the screen in the app switcher so secrets don't end up in a snapshot.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(Theme.accent)
                Text("Vault")
                    .font(.title3.weight(.semibold))
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
