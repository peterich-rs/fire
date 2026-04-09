import SwiftUI

struct FireProfileBadgeChip: View {
    let badge: BadgeState

    private var tierColor: Color {
        switch badge.badgeTypeId {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return FireTheme.subtleInk
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            badgeIcon
                .font(.caption2)
                .foregroundStyle(tierColor)

            Text(badge.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(FireTheme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(FireTheme.softSurface, in: RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius)
                .strokeBorder(FireTheme.divider, lineWidth: 0.5)
        )
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
}
