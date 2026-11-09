import SwiftUI

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l
    var radius: CGFloat = Theme.Radius.large

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Colors.surface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.Colors.stroke)
            )
    }
}

extension View {
    func card(padding: CGFloat = Theme.Spacing.l, radius: CGFloat = Theme.Radius.large) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }
}

/// Квадратная плашка с SF-символом.
struct IconTile: View {
    var systemName: String
    var tint: Color = Theme.Colors.accentLight
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .accessibilityHidden(true)
    }
}

/// Строка меню: иконка, заголовок, подпись, шеврон.
struct MenuRow: View {
    var icon: String
    var title: String
    var subtitle: String?
    var tint: Color = Theme.Colors.accentLight

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            IconTile(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .card(padding: Theme.Spacing.m + 2, radius: Theme.Radius.medium)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    var title: String
    var action: (title: String, handler: () -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action.title, action: action.handler)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accentLight)
            }
        }
    }
}

struct Chip: View {
    var text: String
    var tint: Color = Theme.Colors.textSecondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            IconTile(systemName: icon, size: 56)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .card()
    }
}
