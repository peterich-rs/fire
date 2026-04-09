import SwiftUI

struct FireTopicRow: View {
    let row: FireTopicRowPresentation
    let category: FireTopicCategoryPresentation?

    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color {
        Color(fireHex: category?.colorHex) ?? FireTheme.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FireAvatarView(
                avatarTemplate: avatarTemplate,
                username: displayUsername,
                size: 34
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.topic.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                FlowLayout(spacing: 6, fallbackWidth: tagFlowFallbackWidth) {
                    if let category {
                        categoryChip(category)
                    }

                    ForEach(row.tagNames, id: \.self) { tagName in
                        tagChip(tagName)
                    }

                    if row.isPinned {
                        statusIcon("pin.fill", color: .orange)
                    }

                    if row.hasAcceptedAnswer {
                        statusIcon("checkmark.circle.fill", color: .green)
                    }

                    if row.hasUnreadPosts {
                        unreadDot
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: 6) {
                    Text(displayUsername)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(FireTheme.subtleInk)
                        .lineLimit(1)

                    if let createdTimestampText = FireTopicPresentation.compactTimestamp(
                        unixMs: row.createdTimestampUnixMs
                    ) {
                        Text(createdTimestampText)
                            .font(.caption2)
                            .foregroundStyle(FireTheme.tertiaryInk)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 0) {
                    topicStat(
                        value: row.topic.replyCount,
                        systemImage: "arrowshape.turn.up.left",
                        alignment: .leading
                    )
                    topicStat(
                        value: row.topic.views,
                        systemImage: "eye",
                        alignment: .center
                    )
                    topicStat(
                        value: row.topic.likeCount,
                        systemImage: "heart",
                        alignment: .trailing
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var displayUsername: String {
        row.originalPosterUsername
            ?? row.topic.lastPosterUsername
            ?? fallbackPresentationUsername
            ?? row.topic.posters.first.map { "User \($0.userId)" }
            ?? "?"
    }

    private var avatarTemplate: String? {
        row.originalPosterAvatarTemplate
    }

    private var fallbackPresentationUsername: String? {
        guard let candidate = row.lastPosterUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty
        else {
            return nil
        }

        return candidate.localizedCaseInsensitiveContains("poster") ? nil : candidate
    }

    private var unreadDot: some View {
        ZStack {
            Circle()
                .fill(FireTheme.accent)
                .frame(width: 7, height: 7)
        }
        .frame(width: 18, height: 18)
    }

    private var tagFlowFallbackWidth: CGFloat {
        max(UIScreen.main.bounds.width - 120, 180)
    }

    private func categoryChip(_ category: FireTopicCategoryPresentation) -> some View {
        Text(category.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(FireTheme.categoryChipBackground(accent: accentColor, isDark: colorScheme == .dark))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func tagChip(_ tagName: String) -> some View {
        Text("#\(tagName)")
            .font(.caption2)
            .foregroundStyle(FireTheme.tagChipForeground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(FireTheme.tagChipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func statusIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.caption2)
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func topicStat(value: UInt32, systemImage: String, alignment: Alignment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2)

            Text(FireTopicPresentation.compactCount(value))
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(FireTheme.tertiaryInk)
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}
