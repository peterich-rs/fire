import Foundation

struct FireDraftContentToken: Hashable {
    let key: String
    let title: String
    let excerpt: String?
    let kind: String
    let updatedAt: String?
    let routeID: String?

    init(_ draft: DraftState) {
        key = draft.draftKey
        title = draft.fireDraftTitle
        excerpt = draft.fireDraftExcerpt
        kind = draft.fireDraftKindLabel
        updatedAt = FireTopicPresentation.compactTimestamp(draft.updatedAt)
        routeID = draft.fireComposerRoute()?.id
    }
}

extension DraftState {
    func fireComposerRoute() -> FireComposerRoute? {
        let key = draftKey
        if key == "new_topic" {
            return FireComposerRoute(kind: .createTopic)
        }
        if key == "new_private_message" {
            return FireComposerRoute(
                kind: .privateMessage(
                    recipients: data.recipients,
                    title: data.title
                )
            )
        }
        guard let topicID = self.topicId else {
            return nil
        }
        let title = title?.ifEmpty("话题 #\(topicID)") ?? "话题 #\(topicID)"
        return FireComposerRoute(
            kind: .advancedReply(
                topicID: topicID,
                topicTitle: title,
                categoryID: data.categoryId,
                replyToPostNumber: data.replyToPostNumber,
                replyToUsername: nil,
                isPrivateMessage: data.archetypeId == "private_message"
            )
        )
    }

    var fireDraftTitle: String {
        if draftKey == "new_topic" {
            return title?.ifEmpty("未命名新话题") ?? "未命名新话题"
        }
        if draftKey == "new_private_message" {
            return title?.ifEmpty("未命名私信") ?? "未命名私信"
        }
        return title?.ifEmpty("回复草稿") ?? "回复草稿"
    }

    var fireDraftExcerpt: String? {
        let excerpt = excerpt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !excerpt.isEmpty {
            return excerpt
        }
        let reply = data.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reply.isEmpty ? nil : reply
    }

    var fireDraftKindLabel: String {
        if draftKey == "new_topic" {
            return "新话题"
        }
        if draftKey == "new_private_message" || data.archetypeId == "private_message" {
            return "私信"
        }
        return "完整回复"
    }

    var fireDraftIcon: String {
        switch fireDraftKindLabel {
        case "新话题":
            return "square.and.pencil"
        case "私信":
            return "paperplane"
        default:
            return "arrowshape.turn.up.left"
        }
    }

    func fireDraftAccessibilityLabel(supported: Bool) -> String {
        var parts = [fireDraftTitle, fireDraftKindLabel]
        if let excerpt = fireDraftExcerpt {
            parts.append(excerpt)
        }
        if let updatedAt = FireTopicPresentation.compactTimestamp(updatedAt) {
            parts.append(updatedAt)
        }
        if !supported {
            parts.append("暂不支持")
        }
        return parts.joined(separator: "，")
    }
}
