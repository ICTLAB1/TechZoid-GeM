import SwiftUI

/// The app's design tokens.
///
/// Spacing, radius and colour are named rather than typed in at each call
/// site, so screens built months apart still line up with each other. Any
/// number that appears in more than one view belongs here.
enum Theme {
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.72)

    /// A four-step scale. Anything that needs a gap picks the nearest step
    /// rather than inventing a number.
    enum Spacing {
        /// Between a label and the value directly under it.
        static let tight: CGFloat = 4
        /// Inside a row.
        static let row: CGFloat = 10
        /// Inside a card, and around its content.
        static let content: CGFloat = 14
        /// Between one card or section and the next.
        static let section: CGFloat = 22
        /// From the screen edge.
        static let screen: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 11
        static let badge: CGFloat = 6
    }

    /// Kept as the original name so existing screens keep compiling.
    static let cardCornerRadius: CGFloat = Radius.card

    /// Icon plate size in a list row, so every row's text starts on the
    /// same vertical line.
    static let rowIconSize: CGFloat = 30

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.07) : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    /// What a count or status badge means, rather than which colour it is.
    enum Emphasis {
        case neutral
        case attention
        case urgent

        var tint: Color {
            switch self {
            case .neutral: .secondary
            case .attention: .orange
            case .urgent: .red
            }
        }
    }
}

/// A count or short status at the trailing edge of a row.
///
/// One component so "3 of 5", "12" and "Blocked" are never styled three
/// different ways on three different screens.
struct StatusBadge: View {
    var text: String
    var emphasis: Theme.Emphasis = .neutral

    var body: some View {
        if emphasis == .neutral {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(emphasis.tint, in: Capsule())
        }
    }
}

/// A navigable row: icon, title, a line of explanation, an optional badge.
///
/// The tools tab, the settings list and the dashboard all used to draw this
/// themselves, with different icon sizes and different subtitle treatment.
struct ToolRow<Destination: View>: View {
    var title: String
    var detail: String?
    var icon: String
    var tint: Color = Theme.accent
    var badge: String?
    var badgeEmphasis: Theme.Emphasis = .neutral
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Theme.Spacing.content) {
                Image(systemName: icon)
                    .font(.system(size: Theme.rowIconSize * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.rowIconSize, height: Theme.rowIconSize)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: Theme.Spacing.row)

                if let badge {
                    StatusBadge(text: badge, emphasis: badgeEmphasis)
                }
            }
            .padding(.vertical, 2)
        }
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
