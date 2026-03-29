import SwiftUI

struct FireTopicRow: View {
    let row: FireTopicRowPresentation
    let category: FireTopicCategoryPresentation?

    private var accentColor: Color {
        Color(fireHex: category?.colorHex) ?? FireTheme.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FireAvatarView(
                avatarTemplate: avatarTemplate,
                username: displayUsername,
                size: 36
            )
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(row.topic.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if let category {
                        Text(category.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color(fireHex: category.textColorHex) ?? accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if row.topic.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if row.topic.hasAcceptedAnswer {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    if row.topic.unreadPosts > 0 {
                        Circle()
                            .fill(FireTheme.accent)
                            .frame(width: 7, height: 7)
                    }

                    Spacer(minLength: 0)

                    if let activityTimestampText = row.activityTimestampText {
                        Text(activityTimestampText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 10) {
                    if let lastPosterUsername = row.lastPosterUsername {
                        Text(lastPosterUsername)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Label("\(row.topic.postsCount)", systemImage: "text.bubble")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Label("\(row.topic.views)", systemImage: "eye")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if row.topic.likeCount > 0 {
                        Label("\(row.topic.likeCount)", systemImage: "heart")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var displayUsername: String {
        row.lastPosterUsername
            ?? row.topic.lastPosterUsername
            ?? row.topic.posters.first?.description
            ?? "?"
    }

    private var avatarTemplate: String? {
        nil
    }
}
