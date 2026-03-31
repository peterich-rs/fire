import SwiftUI

// MARK: - Notification helpers

private enum DiscourseNotificationType: Int {
    case mentioned = 1
    case replied = 2
    case quoted = 3
    case edited = 4
    case liked = 5
    case privateMessage = 6
    case posted = 9
    case linked = 11
    case grantedBadge = 12
    case groupMentioned = 15
    case groupedLikes = 19
    case bookmarkReminder = 24
    case reaction = 25
}

private extension NotificationItemState {
    var discourseType: DiscourseNotificationType? {
        DiscourseNotificationType(rawValue: Int(notificationType))
    }

    var displayDescription: String {
        let actor = data.displayUsername ?? data.username ?? "Someone"
        let title = fancyTitle ?? data.topicTitle ?? ""
        let suffix = title.isEmpty ? "" : "「\(title)」"

        switch discourseType {
        case .mentioned: return "\(actor) 提到了你\(suffix)"
        case .replied: return "\(actor) 回复了你\(suffix)"
        case .quoted: return "\(actor) 引用了你的帖子\(suffix)"
        case .edited: return "\(actor) 编辑了帖子\(suffix)"
        case .liked: return "\(actor) 赞了你的帖子\(suffix)"
        case .privateMessage: return "\(actor) 给你发了私信\(suffix)"
        case .posted: return "\(actor) 发帖\(suffix)"
        case .linked: return "\(actor) 链接了你的帖子\(suffix)"
        case .grantedBadge:
            let badge = data.badgeName ?? title
            return badge.isEmpty ? "你获得了新徽章" : "你获得了徽章「\(badge)」"
        case .groupMentioned: return "\(actor) 提及了你所在的群组\(suffix)"
        case .groupedLikes: return "\(actor) 等 \(data.count ?? 1) 人赞了你的帖子\(suffix)"
        case .bookmarkReminder: return "书签提醒\(suffix)"
        case .reaction: return "\(actor) 对你的帖子使用了表情\(suffix)"
        case nil: return title.isEmpty ? "新通知" : title
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
        case .posted: return "bubble.right"
        case .linked: return "link"
        case .grantedBadge: return "medal"
        case .groupMentioned: return "person.3"
        case .groupedLikes: return "heart.fill"
        case .bookmarkReminder: return "bookmark"
        case .reaction: return "face.smiling"
        case nil: return "bell"
        }
    }

    var typeIconColor: Color {
        switch discourseType {
        case .mentioned, .replied, .privateMessage, .posted:
            return FireTheme.accent
        case .quoted:
            return .purple
        case .edited, .bookmarkReminder, .reaction:
            return .orange
        case .liked, .groupedLikes:
            return .red
        case .linked:
            return .teal
        case .grantedBadge:
            return .yellow
        case .groupMentioned:
            return .indigo
        case nil:
            return FireTheme.tertiaryInk
        }
    }

    var stubRow: TopicRowState? {
        guard let tid = topicId else { return nil }
        let t = fancyTitle ?? data.topicTitle ?? ""
        return TopicRowState.stub(
            topicId: tid,
            title: t,
            slug: slug ?? "",
            categoryId: nil
        )
    }
}

extension TopicRowState {
    static func stub(
        topicId: UInt64,
        title: String,
        slug: String,
        categoryId: UInt64?
    ) -> TopicRowState {
        TopicRowState(
            topic: TopicSummaryState(
                id: topicId,
                title: title,
                slug: slug,
                postsCount: 0,
                replyCount: 0,
                views: 0,
                likeCount: 0,
                excerpt: nil,
                createdAt: nil,
                lastPostedAt: nil,
                lastPosterUsername: nil,
                categoryId: categoryId,
                pinned: false,
                visible: true,
                closed: false,
                archived: false,
                tags: [],
                posters: [],
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: nil,
                highestPostNumber: 0,
                hasAcceptedAnswer: false,
                canHaveAnswer: false
            ),
            excerptText: nil,
            originalPosterUsername: nil,
            originalPosterAvatarTemplate: nil,
            tagNames: [],
            statusLabels: [],
            isPinned: false,
            isClosed: false,
            isArchived: false,
            hasAcceptedAnswer: false,
            hasUnreadPosts: false,
            createdTimestampUnixMs: nil,
            activityTimestampUnixMs: nil,
            lastPosterUsername: nil
        )
    }
}

// MARK: - View

struct FireNotificationsView: View {
    @ObservedObject var viewModel: FireAppViewModel

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingNotifications && viewModel.recentNotifications.isEmpty {
                    loadingSkeleton
                } else if viewModel.recentNotifications.isEmpty {
                    emptyState
                } else {
                    notificationList
                }
            }
            .navigationTitle("通知")
            .toolbar {
                if viewModel.notificationUnreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("全部已读") {
                            viewModel.markAllNotificationsRead()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.accent)
                    }
                }
            }
            .refreshable {
                await viewModel.loadRecentNotifications(force: true)
            }
        }
        .task {
            await viewModel.loadRecentNotifications(force: false)
        }
    }

    // MARK: - Notification list

    private var notificationList: some View {
        List {
            ForEach(viewModel.recentNotifications, id: \.id) { item in
                notificationRow(item)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func notificationRow(_ item: NotificationItemState) -> some View {
        if let stubRow = item.stubRow {
            NavigationLink {
                FireTopicDetailView(viewModel: viewModel, row: stubRow)
            } label: {
                notificationRowContent(item)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                if !item.read {
                    viewModel.markNotificationRead(id: item.id)
                }
            })
        } else {
            notificationRowContent(item)
        }
    }

    private func notificationRowContent(_ item: NotificationItemState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread indicator
            Circle()
                .fill(item.read ? Color.clear : FireTheme.accent)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            // Type icon or acting user avatar
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

            // Content
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

    private var emptyState: some View {
        VStack(spacing: 16) {
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
                Task {
                    await viewModel.loadRecentNotifications(force: true)
                }
            }
            .buttonStyle(FireSecondaryButtonStyle())
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
