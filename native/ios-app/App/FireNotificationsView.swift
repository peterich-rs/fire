import SwiftUI
import UIKit

// MARK: - Notification helpers

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
        case .mentioned: return "\(actor) 提到了你\(suffix)"
        case .replied: return "\(actor) 回复了你\(suffix)"
        case .quoted: return "\(actor) 引用了你的帖子\(suffix)"
        case .edited: return "\(actor) 编辑了帖子\(suffix)"
        case .liked:
            let count = data.count ?? 1
            if count <= 1 {
                return "\(actor) 赞了你的帖子\(suffix)"
            } else if let u2 = data.username2, !u2.isEmpty {
                return "\(actor) 和 \(u2) 赞了你的帖子\(suffix)"
            } else {
                return "\(actor) 等 \(count) 人赞了你的帖子\(suffix)"
            }
        case .privateMessage: return "\(actor) 给你发了私信\(suffix)"
        case .invitedToPrivateMessage: return "\(actor) 邀请你加入私信\(suffix)"
        case .inviteeAccepted: return "\(actor) 接受了你的邀请"
        case .posted: return "\(actor) 发帖\(suffix)"
        case .movedPost: return "\(actor) 移动了帖子\(suffix)"
        case .linked: return "\(actor) 链接了你的帖子\(suffix)"
        case .grantedBadge:
            let badge = data.badgeName ?? title
            return badge.isEmpty ? "你获得了新徽章" : "你获得了徽章「\(badge)」"
        case .invitedToTopic: return "\(actor) 邀请你参与话题\(suffix)"
        case .custom: return title.isEmpty ? "自定义通知" : title
        case .groupMentioned: return "\(actor) 提及了你所在的群组\(suffix)"
        case .groupMessageSummary:
            let count = Int(data.inboxCount ?? "0") ?? 0
            let group = data.groupName ?? ""
            return "\(group) 有 \(count) 条新消息"
        case .watchingFirstPost: return "新话题\(suffix)"
        case .topicReminder: return "话题提醒\(suffix)"
        case .likedConsolidated:
            let count = data.count ?? 0
            return "\(actor) 等 \(count) 人赞了你的多篇帖子"
        case .postApproved: return "你的帖子已通过审核\(suffix)"
        case .membershipRequestAccepted:
            let group = data.groupName ?? ""
            return group.isEmpty ? "加群申请已通过" : "你已加入群组「\(group)」"
        case .bookmarkReminder: return "书签提醒\(suffix)"
        case .reaction: return "\(actor) 对你的帖子使用了表情\(suffix)"
        case .following: return "\(actor) 关注了你"
        case .followingCreatedTopic: return "\(actor) 发布了新话题\(suffix)"
        case .followingReplied: return "\(actor) 回复了话题\(suffix)"
        case .circlesActivity: return "圈子动态\(suffix)"
        case nil: return title.isEmpty ? "新通知" : title
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
        case .mentioned: return "at"
        case .replied: return "arrowshape.turn.up.left"
        case .quoted: return "quote.bubble"
        case .edited: return "pencil"
        case .liked: return "heart"
        case .privateMessage: return "envelope"
        case .invitedToPrivateMessage: return "envelope.badge"
        case .inviteeAccepted: return "person.badge.plus"
        case .posted: return "bubble.right"
        case .movedPost: return "arrow.right.arrow.left"
        case .linked: return "link"
        case .grantedBadge: return "medal"
        case .invitedToTopic: return "person.badge.plus"
        case .custom: return "bell"
        case .groupMentioned: return "person.3"
        case .groupMessageSummary: return "tray.full"
        case .watchingFirstPost: return "eye"
        case .topicReminder: return "clock"
        case .likedConsolidated: return "heart.fill"
        case .postApproved: return "checkmark.circle"
        case .membershipRequestAccepted: return "person.crop.circle.badge.checkmark"
        case .bookmarkReminder: return "bookmark"
        case .reaction: return "face.smiling"
        case .following: return "person.badge.plus"
        case .followingCreatedTopic: return "plus.bubble"
        case .followingReplied: return "arrowshape.turn.up.left"
        case .circlesActivity: return "circle.grid.3x3"
        case nil: return "bell"
        }
    }

    var typeIconColor: Color {
        switch discourseType {
        case .mentioned, .replied, .privateMessage, .posted, .followingReplied:
            return FireTheme.accent
        case .quoted:
            return .purple
        case .edited, .bookmarkReminder, .reaction, .topicReminder:
            return .orange
        case .liked, .likedConsolidated:
            return .red
        case .linked:
            return .teal
        case .grantedBadge:
            return .yellow
        case .groupMentioned, .groupMessageSummary:
            return .indigo
        case .inviteeAccepted, .following:
            return .green
        case .invitedToPrivateMessage, .invitedToTopic:
            return FireTheme.accent
        case .movedPost:
            return .secondary
        case .watchingFirstPost, .followingCreatedTopic:
            return FireTheme.accent
        case .postApproved, .membershipRequestAccepted:
            return .green
        case .circlesActivity:
            return .purple
        case .custom, nil:
            return FireTheme.tertiaryInk
        }
    }
}

// MARK: - View

struct FireNotificationsView: View {
    let appViewModel: FireAppViewModel
    @ObservedObject var notificationStore: FireNotificationStore
    @State private var selectedRoute: FireAppRoute?

    private var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage = notificationStore.blockingRecentErrorMessage {
                    blockingErrorState(message: errorMessage)
                } else if !notificationStore.hasLoadedRecentOnce {
                    loadingSkeleton
                } else if notificationStore.recentNotifications.isEmpty {
                    emptyState(errorMessage: notificationStore.recentNonBlockingErrorMessage)
                } else {
                    notificationList
                }
            }
            .navigationTitle("通知")
            .toolbar {
                if notificationStore.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("全部已读") {
                            notificationStore.markAllRead()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.accent)
                        .fireCTAPress()
                    }
                }
            }
            .refreshable {
                await notificationStore.loadRecent(force: true)
            }
            .navigationDestination(item: $selectedRoute) { route in
                FireAppRouteDestinationView(viewModel: appViewModel, route: route)
            }
        }
        .task {
            await notificationStore.loadRecent(force: false)
        }
    }

    private func retryRecentLoad() {
        Task {
            await notificationStore.loadRecent(force: true)
        }
    }

    private func blockingErrorState(message: String) -> some View {
        FireBlockingErrorState(
            title: "通知加载失败",
            message: message,
            onRetry: retryRecentLoad
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Notification list

    private var notificationList: some View {
        List {
            if let errorMessage = notificationStore.recentNonBlockingErrorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            notificationStore.clearRecentError()
                        }
                    )
                }
            }

            ForEach(notificationStore.recentNotifications, id: \.id) { item in
                notificationRow(item)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .fireRespectingReduceMotion { content, reduceMotion in
                        content.transition(.fireListItem(reduceMotion: reduceMotion))
                    }
            }

            NavigationLink {
                FireNotificationHistoryView(
                    appViewModel: appViewModel,
                    notificationStore: notificationStore
                )
            } label: {
                HStack {
                    Spacer()
                    Text("查看全部通知")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FireTheme.accent)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .fireRespectingReduceMotion { content, reduceMotion in
            content.animation(
                FireMotionTokens.animation(for: .standard, reduceMotion: reduceMotion),
                value: notificationStore.recentNotifications.map(\.id)
            )
        }
    }

    private func notificationRow(_ item: NotificationItemState) -> some View {
        Button {
            handleNotificationTap(item)
        } label: {
            notificationRowContent(item)
        }
        .buttonStyle(.plain)
    }

    private func handleNotificationTap(_ item: NotificationItemState) {
        if !item.read {
            notificationStore.markRead(id: item.id)
        }

        selectedRoute = item.appRoute
    }

    private func notificationRowContent(_ item: NotificationItemState) -> some View {
        FireNotificationRowContent(item: item, baseURLString: baseURLString)
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        List {
            ForEach(0..<8, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)

                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 13)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.quaternarySystemFill))
                            .frame(width: 80, height: 10)
                    }
                }
                .padding(.vertical, 10)
                .redacted(reason: .placeholder)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty state

    private func emptyState(errorMessage: String?) -> some View {
        VStack(spacing: 16) {
            if let errorMessage {
                FireErrorBanner(
                    message: errorMessage,
                    copied: false,
                    onCopy: {
                        UIPasteboard.general.string = errorMessage
                    },
                    onDismiss: {
                        notificationStore.clearRecentError()
                    }
                )
            }

            Image(systemName: "bell.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(FireTheme.tertiaryInk)

            Text("暂无通知")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("当有人回复、提及或点赞你的帖子时，通知会出现在这里。")
                .font(.subheadline)
                .foregroundStyle(FireTheme.tertiaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("刷新") {
                retryRecentLoad()
            }
            .buttonStyle(FireSecondaryButtonStyle())
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared notification row

struct FireNotificationRowContent: View {
    let item: NotificationItemState
    let baseURLString: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.read ? Color.clear : FireTheme.accent)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            ZStack {
                Circle()
                    .fill(item.typeIconColor.opacity(0.12))
                    .frame(width: 36, height: 36)

                if let avatarTemplate = item.actingUserAvatarTemplate, !avatarTemplate.isEmpty {
                    FireAvatarView(
                        avatarTemplate: avatarTemplate,
                        username: item.data.displayUsername ?? "?",
                        size: 36,
                        baseURLString: baseURLString
                    )
                } else {
                    Image(systemName: item.typeSystemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.typeIconColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayDescription)
                    .font(item.read ? .subheadline : .subheadline.weight(.semibold))
                    .foregroundStyle(item.read ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                if let ts = FireTopicPresentation.compactTimestamp(item.createdAt) {
                    Text(ts)
                        .font(.caption2)
                        .foregroundStyle(FireTheme.tertiaryInk)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 10)
        .background(
            item.read
                ? Color.clear
                : FireTheme.accent.opacity(0.03)
        )
        .contentShape(Rectangle())
    }
}
