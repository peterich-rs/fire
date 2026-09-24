import Foundation

struct FireComposerRoute: Identifiable, Equatable {
    enum Kind: Equatable {
        case createTopic
        case advancedReply(
            topicID: UInt64,
            topicTitle: String,
            categoryID: UInt64?,
            replyToPostNumber: UInt32?,
            replyToUsername: String?,
            isPrivateMessage: Bool
        )
        case privateMessage(
            recipients: [String],
            title: String?
        )
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .createTopic:
            return "create-topic"
        case .advancedReply(let topicID, _, _, let replyToPostNumber, _, let isPrivateMessage):
            let suffix = isPrivateMessage ? "pm" : "topic"
            return "reply-\(topicID)-\(replyToPostNumber ?? 0)"
                + "-\(suffix)"
        case .privateMessage(let recipients, _):
            let seed = recipients.isEmpty ? "new" : recipients.sorted().joined(separator: ",")
            return "private-message-\(seed)"
        }
    }

    var navigationTitle: String {
        switch kind {
        case .createTopic:
            return "新建话题"
        case .advancedReply(_, _, _, _, _, let isPrivateMessage):
            return isPrivateMessage ? "完整私信回复" : "完整回复"
        case .privateMessage:
            return "新建私信"
        }
    }

    var submitLabel: String {
        switch kind {
        case .createTopic:
            return "发布"
        case .advancedReply, .privateMessage:
            return "发送"
        }
    }

    var topicID: UInt64? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(let topicID, _, _, _, _, _):
            return topicID
        case .privateMessage:
            return nil
        }
    }

    var topicTitle: String? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, let topicTitle, _, _, _, _):
            return topicTitle
        case .privateMessage(_, let title):
            return title
        }
    }

    var replyToPostNumber: UInt32? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, _, let replyToPostNumber, _, _):
            return replyToPostNumber
        case .privateMessage:
            return nil
        }
    }

    var replyToUsername: String? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, _, _, let replyToUsername, _):
            return replyToUsername
        case .privateMessage:
            return nil
        }
    }

    var fallbackCategoryID: UInt64? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, let categoryID, _, _, _):
            return categoryID
        case .privateMessage:
            return nil
        }
    }

    var recipients: [String] {
        switch kind {
        case .privateMessage(let recipients, _):
            return recipients
        default:
            return []
        }
    }

    var isPrivateMessage: Bool {
        switch kind {
        case .privateMessage:
            return true
        case .advancedReply(_, _, _, _, _, let isPrivateMessage):
            return isPrivateMessage
        case .createTopic:
            return false
        }
    }

    var draftKey: String {
        switch kind {
        case .createTopic:
            return "new_topic"
        case .advancedReply(let topicID, _, _, let replyToPostNumber, _, _):
            if let replyToPostNumber, replyToPostNumber > 0 {
                return "topic_\(topicID)_post_\(replyToPostNumber)"
            }
            return "topic_\(topicID)"
        case .privateMessage:
            return "new_private_message"
        }
    }
}
