import Foundation
import UIKit

enum DiscourseNotificationType: Int {
    case mentioned = 1
    case replied = 2
    case quoted = 3
    case edited = 4
    case liked = 5
    case privateMessage = 6
    case invitedToPrivateMessage = 7
    case inviteeAccepted = 8
    case posted = 9
    case movedPost = 10
    case linked = 11
    case grantedBadge = 12
    case invitedToTopic = 13
    case custom = 14
    case groupMentioned = 15
    case groupMessageSummary = 16
    case watchingFirstPost = 17
    case topicReminder = 18
    case likedConsolidated = 19
    case postApproved = 20
    case membershipRequestAccepted = 22
    case bookmarkReminder = 24
    case reaction = 25
    case following = 800
    case followingCreatedTopic = 801
    case followingReplied = 802
    case circlesActivity = 900
}

extension NotificationItemState {
    var discourseType: DiscourseNotificationType? {
        DiscourseNotificationType(rawValue: Int(notificationType))
    }

    var resolvedUsername: String? {
        data.displayUsername ?? data.username ?? data.originalUsername
    }

    var displayDescription: String {
        let actor = resolvedUsername ?? "Someone"
        let title = fancyTitle ?? data.topicTitle ?? ""
        let suffix = title.isEmpty ? "" : "「\(title)」"

        switch discourseType {
        case .mentioned:
            return "\(actor) 提到了你\(suffix)"
        case .replied:
            return "\(actor) 回复了你\(suffix)"
        case .quoted:
            return "\(actor) 引用了你的帖子\(suffix)"
        case .edited:
            return "\(actor) 编辑了帖子\(suffix)"
        case .liked:
            let count = data.count ?? 1
            if count <= 1 {
                return "\(actor) 赞了你的帖子\(suffix)"
            } else if let u2 = data.username2, !u2.isEmpty {
                return "\(actor) 和 \(u2) 赞了你的帖子\(suffix)"
            } else {
                return "\(actor) 等 \(count) 人赞了你的帖子\(suffix)"
            }
        case .privateMessage:
            return "\(actor) 给你发了私信\(suffix)"
        case .invitedToPrivateMessage:
            return "\(actor) 邀请你加入私信\(suffix)"
        case .inviteeAccepted:
            return "\(actor) 接受了你的邀请"
        case .posted:
            return "\(actor) 发帖\(suffix)"
        case .movedPost:
            return "\(actor) 移动了帖子\(suffix)"
        case .linked:
            return "\(actor) 链接了你的帖子\(suffix)"
        case .grantedBadge:
            let badge = data.badgeName ?? title
            return badge.isEmpty ? "你获得了新徽章" : "你获得了徽章「\(badge)」"
        case .invitedToTopic:
            return "\(actor) 邀请你参与话题\(suffix)"
        case .custom:
            return title.isEmpty ? "自定义通知" : title
        case .groupMentioned:
            return "\(actor) 提及了你所在的群组\(suffix)"
        case .groupMessageSummary:
            let count = Int(data.inboxCount ?? "0") ?? 0
            let group = data.groupName ?? ""
            return "\(group) 有 \(count) 条新消息"
        case .watchingFirstPost:
            return "新话题\(suffix)"
        case .topicReminder:
            return "话题提醒\(suffix)"
        case .likedConsolidated:
            let count = data.count ?? 0
            return "\(actor) 等 \(count) 人赞了你的多篇帖子"
        case .postApproved:
            return "你的帖子已通过审核\(suffix)"
        case .membershipRequestAccepted:
            let group = data.groupName ?? ""
            return group.isEmpty ? "加群申请已通过" : "你已加入群组「\(group)」"
        case .bookmarkReminder:
            return "书签提醒\(suffix)"
        case .reaction:
            return "\(actor) 对你的帖子使用了表情\(suffix)"
        case .following:
            return "\(actor) 关注了你"
        case .followingCreatedTopic:
            return "\(actor) 发布了新话题\(suffix)"
        case .followingReplied:
            return "\(actor) 回复了话题\(suffix)"
        case .circlesActivity:
            return "圈子动态\(suffix)"
        case nil:
            return title.isEmpty ? "新通知" : title
        }
    }

    var appRoute: FireAppRoute? {
        switch discourseType {
        case .inviteeAccepted, .following:
            guard let username = resolvedUsername else { return nil }
            return .profile(username: username)
        case .grantedBadge:
            guard let badgeID = data.badgeId else { return nil }
            return .badge(id: badgeID, slug: data.badgeSlug)
        case .membershipRequestAccepted:
            return nil
        default:
            guard let tid = topicId else { return nil }
            return .topic(
                topicId: tid,
                postNumber: postNumber,
                preview: FireTopicRoutePreview.fromMetadata(
                    title: fancyTitle ?? data.topicTitle,
                    slug: slug,
                    excerptText: data.excerpt
                )
            )
        }
    }

    var typeSystemImage: String {
        switch discourseType {
        case .mentioned:
            return "at"
        case .replied:
            return "arrowshape.turn.up.left"
        case .quoted:
            return "quote.bubble"
        case .edited:
            return "pencil"
        case .liked:
            return "heart"
        case .privateMessage:
            return "envelope"
        case .invitedToPrivateMessage:
            return "envelope.badge"
        case .inviteeAccepted:
            return "person.badge.plus"
        case .posted:
            return "bubble.right"
        case .movedPost:
            return "arrow.right.arrow.left"
        case .linked:
            return "link"
        case .grantedBadge:
            return "medal"
        case .invitedToTopic:
            return "person.badge.plus"
        case .custom:
            return "bell"
        case .groupMentioned:
            return "person.3"
        case .groupMessageSummary:
            return "tray.full"
        case .watchingFirstPost:
            return "eye"
        case .topicReminder:
            return "clock"
        case .likedConsolidated:
            return "heart.fill"
        case .postApproved:
            return "checkmark.circle"
        case .membershipRequestAccepted:
            return "person.crop.circle.badge.checkmark"
        case .bookmarkReminder:
            return "bookmark"
        case .reaction:
            return "face.smiling"
        case .following:
            return "person.badge.plus"
        case .followingCreatedTopic:
            return "plus.bubble"
        case .followingReplied:
            return "arrowshape.turn.up.left"
        case .circlesActivity:
            return "circle.grid.3x3"
        case nil:
            return "bell"
        }
    }

    var typeIconUIColor: UIColor {
        switch discourseType {
        case .mentioned, .replied, .privateMessage, .posted, .followingReplied:
            return FireNotificationPresentationPalette.accent
        case .quoted, .circlesActivity:
            return .systemPurple
        case .edited, .bookmarkReminder, .reaction, .topicReminder:
            return .systemOrange
        case .liked, .likedConsolidated:
            return .systemRed
        case .linked:
            return .systemTeal
        case .grantedBadge:
            return .systemYellow
        case .groupMentioned, .groupMessageSummary:
            return .systemIndigo
        case .inviteeAccepted, .following, .postApproved, .membershipRequestAccepted:
            return .systemGreen
        case .invitedToPrivateMessage, .invitedToTopic, .watchingFirstPost, .followingCreatedTopic:
            return FireNotificationPresentationPalette.accent
        case .movedPost:
            return .secondaryLabel
        case .custom, nil:
            return .tertiaryLabel
        }
    }
}

private enum FireNotificationPresentationPalette {
    static let accent = UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1)
}
