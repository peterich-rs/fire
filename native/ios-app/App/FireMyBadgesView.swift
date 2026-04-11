import SwiftUI

private enum FireBadgeSection: String, CaseIterable, Identifiable {
    case gold
    case silver
    case bronze
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gold: "金徽章"
        case .silver: "银徽章"
        case .bronze: "铜徽章"
        case .other: "其他徽章"
        }
    }

    var symbol: String {
        switch self {
        case .gold: "medal.star"
        case .silver: "medal"
        case .bronze: "rosette"
        case .other: "seal"
        }
    }

    var color: Color {
        switch self {
        case .gold:
            Color(red: 0.90, green: 0.68, blue: 0.16)
        case .silver:
            Color(red: 0.60, green: 0.64, blue: 0.72)
        case .bronze:
            Color(red: 0.73, green: 0.49, blue: 0.28)
        case .other:
            FireTheme.subtleInk
        }
    }

    init(badgeTypeId: UInt32) {
        switch badgeTypeId {
        case 1:
            self = .gold
        case 2:
            self = .silver
        case 3:
            self = .bronze
        default:
            self = .other
        }
    }
}

struct FireMyBadgesView: View {
    let badges: [BadgeState]

    private var groupedBadges: [(section: FireBadgeSection, badges: [BadgeState])] {
        FireBadgeSection.allCases.compactMap { section in
            let badgesForSection = badges
                .filter { FireBadgeSection(badgeTypeId: $0.badgeTypeId) == section }
                .sorted { lhs, rhs in
                    if lhs.grantCount != rhs.grantCount {
                        return lhs.grantCount > rhs.grantCount
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

            guard !badgesForSection.isEmpty else { return nil }
            return (section, badgesForSection)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                summaryHero

                if groupedBadges.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedBadges, id: \.section.id) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: group.section.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(group.section.color)

                                Text(group.section.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(FireTheme.ink)

                                Spacer()

                                Text("\(group.badges.count)")
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(group.section.color)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(group.section.color.opacity(0.12), in: Capsule())
                            }

                            VStack(spacing: 12) {
                                ForEach(group.badges, id: \.id) { badge in
                                    FireBadgeListCard(badge: badge)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(FireTheme.canvasTop)
        .navigationTitle("我的勋章")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryHero: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("累计获得")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(FireTheme.subtleInk)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(badges.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(FireTheme.ink)

                    Text("枚徽章")
                        .font(.subheadline)
                        .foregroundStyle(FireTheme.tertiaryInk)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(FireTheme.accent.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "rosette")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FireTheme.accent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [FireTheme.chrome, FireTheme.softSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(FireTheme.chromeBorder, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rosette")
                .font(.title2)
                .foregroundStyle(FireTheme.tertiaryInk)

            Text("还没有获得徽章")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FireTheme.ink)

            Text("获得的勋章会在这里按类型整理展示。")
                .font(.caption)
                .foregroundStyle(FireTheme.subtleInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

private struct FireBadgeListCard: View {
    let badge: BadgeState

    private var section: FireBadgeSection {
        FireBadgeSection(badgeTypeId: badge.badgeTypeId)
    }

    private var detailText: String? {
        let longDescription = badge.longDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !longDescription.isEmpty {
            return longDescription
        }

        let description = badge.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty {
            return description
        }

        return nil
    }

    private var tierLabel: String {
        section.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                emblem

                VStack(alignment: .leading, spacing: 5) {
                    Text(badge.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FireTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(tierLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(section.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(section.color.opacity(0.12), in: Capsule())

                        if badge.grantCount > 0 {
                            Text("累计授予 \(badge.grantCount) 次")
                                .font(.caption)
                                .foregroundStyle(FireTheme.subtleInk)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if let detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(FireTheme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FireTheme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(section.color.opacity(0.18), lineWidth: 1)
        )
    }

    private var emblem: some View {
        ZStack {
            Circle()
                .fill(section.color.opacity(0.14))

            Circle()
                .strokeBorder(section.color.opacity(0.22), lineWidth: 1)

            badgeIcon
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(section.color)
        }
        .frame(width: 42, height: 42)
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
            Image(systemName: "medal.fill")
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
