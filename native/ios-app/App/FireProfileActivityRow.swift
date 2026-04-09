import SwiftUI

struct FireProfileActivityRow: View {
    let action: UserActionState
    let onTap: () -> Void

    private var actionIcon: String {
        switch action.actionType {
        case 1: return "heart.fill"
        case 2: return "heart.fill"
        case 4: return "text.bubble"
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

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: actionIcon)
                    .font(.subheadline)
                    .foregroundStyle(actionIconColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    if let title = action.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let excerpt = action.excerpt, !excerpt.isEmpty {
                        Text(plainTextFromHtml(rawHtml: excerpt))
                            .font(.caption)
                            .foregroundStyle(FireTheme.subtleInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let createdAt = action.createdAt {
                        Text(relativeTimeString(createdAt))
                            .font(.caption2)
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
