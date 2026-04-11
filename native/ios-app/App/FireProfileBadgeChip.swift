import SwiftUI

enum FireProfileBadgeChipStyle {
    case compact
    case featured
}

struct FireProfileBadgeChip: View {
    let badge: BadgeState
    var style: FireProfileBadgeChipStyle = .compact

    private var tierColor: Color {
        switch badge.badgeTypeId {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return FireTheme.subtleInk
        }
    }

    private var badgeDetail: String? {
        let description = badge.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty {
            return description
        }
        if badge.grantCount > 1 {
            return "已授予 \(badge.grantCount) 次"
        }
        return nil
    }

    var body: some View {
        Group {
            switch style {
            case .compact:
                compactChip
            case .featured:
                featuredChip
            }
        }
    }

    @ViewBuilder
    private var badgeIcon: some View {
        if let icon = badge.icon, !icon.isEmpty {
            if icon.contains("fa-") {
                Image(systemName: sfSymbolFromFontAwesome(icon))
            } else {
                Image(systemName: icon)
            }
        } else {
            Image(systemName: "star.fill")
        }
    }

    private func sfSymbolFromFontAwesome(_ faClass: String) -> String {
        let mapping: [String: String] = [
            "fa-certificate": "rosette",
            "fa-heart": "heart.fill",
            "fa-user": "person.fill",
            "fa-star": "star.fill",
            "fa-pencil": "pencil",
            "fa-envelope": "envelope.fill",
            "fa-trophy": "trophy.fill",
            "fa-clock-o": "clock",
            "fa-eye": "eye.fill",
            "fa-link": "link",
        ]
        return mapping[faClass] ?? "medal.fill"
    }

    private var compactChip: some View {
        HStack(spacing: 8) {
            badgeEmblem(size: 26)

            Text(badge.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FireTheme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .fill(FireTheme.softSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .strokeBorder(tierColor.opacity(0.18), lineWidth: 0.8)
        )
    }

    private var featuredChip: some View {
        HStack(alignment: .top, spacing: 10) {
            badgeEmblem(size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(badge.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.ink)
                    .lineLimit(1)

                if let badgeDetail {
                    Text(badgeDetail)
                        .font(.caption)
                        .foregroundStyle(FireTheme.subtleInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 190, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tierColor.opacity(0.18), FireTheme.chrome],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tierColor.opacity(0.24), lineWidth: 1)
        )
    }

    private func badgeEmblem(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(tierColor.opacity(0.16))

            Circle()
                .strokeBorder(tierColor.opacity(0.28), lineWidth: 1)

            badgeIcon
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tierColor)
        }
        .frame(width: size, height: size)
    }
}
