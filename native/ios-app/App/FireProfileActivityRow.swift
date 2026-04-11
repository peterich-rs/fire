import SwiftUI

struct FireProfileActivityRow: View {
    let action: UserActionState

    private var actionIcon: String {
        switch action.actionType {
        case 1, 2: return "heart.fill"
        case 4: return "text.bubble.fill"
        case 5: return "arrowshape.turn.up.left.fill"
        default: return "doc.text"
        }
    }

    private var actionIconColor: Color {
        switch action.actionType {
        case 1, 2: return .pink
        case 4: return FireTheme.accent
        case 5: return FireTheme.success
        default: return FireTheme.subtleInk
        }
    }

    private var actionLabel: String {
        switch action.actionType {
        case 1, 2:
            if let username = action.actingUsername, !username.isEmpty {
                return "@\(username) 赞了你的内容"
            }
            return "收到了新的赞"
        case 4:
            return "发布了新话题"
        case 5:
            return "发表了新回复"
        default:
            return "最近动态"
        }
    }

    private var timestampText: String? {
        guard let createdAt = action.createdAt else {
            return nil
        }
        return relativeTimeString(createdAt)
    }

    private var excerptText: String? {
        guard let excerpt = action.excerpt, !excerpt.isEmpty else {
            return nil
        }
        return plainTextFromHtml(rawHtml: excerpt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(actionIconColor.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: actionIcon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(actionIconColor)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(actionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(actionIconColor)

                    if let timestampText {
                        Text(timestampText)
                            .font(.caption)
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }

                    Spacer(minLength: 0)
                }

                if let title = action.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FireTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if let excerptText, !excerptText.isEmpty {
                    Text(excerptText)
                        .font(.footnote)
                        .foregroundStyle(FireTheme.subtleInk)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }

        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func relativeTimeString(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoDate) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoDate) else {
                return isoDate
            }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
