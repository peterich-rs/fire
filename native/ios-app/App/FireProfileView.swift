import SwiftUI
import UIKit

struct FireProfileView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @ObservedObject var profileViewModel: FireProfileViewModel
    @State private var copiedErrorMessage = false
    @State private var showLogoutConfirmation = false
    @State private var showDeveloperTools = false
    private static let recentActivityPreviewLimit = 3

    private var isLoggedIn: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    private var canLogout: Bool {
        viewModel.session.hasLoginSession || isLoggedIn
    }

    private var displayUsername: String {
        profileViewModel.currentUsername ?? viewModel.session.profileDisplayName
    }

    private var displayName: String {
        let trimmedName = profileViewModel.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? displayUsername : trimmedName
    }

    private var bookmarkCount: UInt32 {
        profileViewModel.summary?.stats.bookmarkCount ?? 0
    }

    private var badgeCount: UInt32 {
        UInt32(profileViewModel.summary?.badges.count ?? 0)
    }

    private var bookmarkSubtitle: String {
        bookmarkCount > 0
            ? "已保存 \(formatNumber(bookmarkCount)) 条内容，可继续编辑或跳回原楼层。"
            : "把想回看的内容收进来，后面可以统一整理。"
    }

    private var historySubtitle: String {
        "继续上次读到的位置，补回最近看过的话题。"
    }

    private var draftsSubtitle: String {
        "管理未发出的新话题和完整回复。"
    }

    private var badgesSubtitle: String {
        badgeCount > 0
            ? "累计获得 \(formatNumber(badgeCount)) 枚徽章。"
            : "查看已获得的徽章档案。"
    }

    private var inviteSubtitle: String {
        "生成和整理待使用的邀请码链接。"
    }

    private var followingSubtitle: String {
        "当前关注 \(formatNumber(profileViewModel.profile?.totalFollowing ?? 0)) 位用户。"
    }

    private var followersSubtitle: String {
        "当前有 \(formatNumber(profileViewModel.profile?.totalFollowers ?? 0)) 位粉丝。"
    }

    private var profileHighlights: [(value: String, label: String)] {
        [
            (formatNumber(profileViewModel.profile?.totalFollowers ?? 0), "粉丝"),
            (formatNumber(profileViewModel.summary?.stats.likesReceived ?? 0), "获赞"),
            (formatNumber(profileViewModel.profile?.totalFollowing ?? 0), "关注"),
        ]
    }

    private var profileMetaEntries: [(symbol: String, label: String, value: String, tint: Color)] {
        var entries: [(String, String, String, Color)] = []

        if let joinedDateText {
            entries.append(("calendar", "加入时间", joinedDateText, FireTheme.subtleInk))
        }
        if let lastSeenText {
            entries.append(("clock.arrow.circlepath", "最近活跃", lastSeenText, FireTheme.success))
        }
        if let readTimeText {
            entries.append(("book.closed", "阅读时长", readTimeText, FireTheme.accent))
        }
        if let gamificationText {
            entries.append(("bolt.fill", "活跃分", gamificationText, FireTheme.accent))
        }

        return entries
    }

    private var recentActions: [UserActionState] {
        Array(profileViewModel.actions.prefix(Self.recentActivityPreviewLimit))
    }

    private var recentActivityTitle: String {
        profileViewModel.selectedTab == .all ? "最近动态" : "最近\(profileViewModel.selectedTab.title)"
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = profileViewModel.errorMessage ?? viewModel.errorMessage {
                    Section {
                        errorBanner(message: errorMessage)
                    }
                }

                Section {
                    profileHeader
                }

                Section {
                    NavigationLink {
                        FireBookmarksView(viewModel: viewModel, username: displayUsername)
                    } label: {
                        shortcutRowContent(
                            icon: "bookmark.fill",
                            tint: FireTheme.accent,
                            title: "我的书签",
                            subtitle: bookmarkSubtitle
                        )
                    }

                    NavigationLink {
                        FireReadHistoryView(viewModel: viewModel)
                    } label: {
                        shortcutRowContent(
                            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                            tint: .blue,
                            title: "浏览历史",
                            subtitle: historySubtitle
                        )
                    }

                    NavigationLink {
                        FireDraftsView(viewModel: viewModel)
                    } label: {
                        shortcutRowContent(
                            icon: "tray.full.fill",
                            tint: .orange,
                            title: "草稿箱",
                            subtitle: draftsSubtitle
                        )
                    }

                    NavigationLink {
                        FireMyBadgesView(badges: profileViewModel.summary?.badges ?? [])
                    } label: {
                        shortcutRowContent(
                            icon: "rosette",
                            tint: .yellow,
                            title: "我的勋章",
                            subtitle: badgesSubtitle
                        )
                    }

                    NavigationLink {
                        FireInviteLinksView(viewModel: viewModel, username: displayUsername)
                    } label: {
                        shortcutRowContent(
                            icon: "ticket.fill",
                            tint: .green,
                            title: "邀请链接",
                            subtitle: inviteSubtitle
                        )
                    }

                    NavigationLink {
                        FireFollowListView(
                            viewModel: viewModel,
                            username: displayUsername,
                            kind: .following
                        )
                    } label: {
                        shortcutRowContent(
                            icon: "person.2",
                            tint: FireTheme.accent,
                            title: "关注列表",
                            subtitle: followingSubtitle
                        )
                    }

                    NavigationLink {
                        FireFollowListView(
                            viewModel: viewModel,
                            username: displayUsername,
                            kind: .followers
                        )
                    } label: {
                        shortcutRowContent(
                            icon: "person.2.fill",
                            tint: .pink,
                            title: "粉丝列表",
                            subtitle: followersSubtitle
                        )
                    }
                }

                Section {
                    if recentActions.isEmpty, profileViewModel.isLoadingActions {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 18)
                            Spacer()
                        }
                    } else if recentActions.isEmpty {
                        Text("还没有可展示的动态")
                            .font(.subheadline)
                            .foregroundStyle(FireTheme.tertiaryInk)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(Array(recentActions.enumerated()), id: \.offset) { _, action in
                            activityRow(action)
                        }
                    }

                    NavigationLink {
                        FireProfileActivityTimelineView(
                            viewModel: viewModel,
                            profileViewModel: profileViewModel
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FireTheme.accent)
                                .frame(width: 24)

                            Text("查看全部动态")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(FireTheme.ink)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(recentActivityTitle)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(FireTheme.canvasTop)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showDeveloperTools = true
                        } label: {
                            Label("开发者工具", systemImage: "wrench.and.screwdriver")
                        }

                        if canLogout {
                            Button(role: .destructive) {
                                showLogoutConfirmation = true
                            } label: {
                                Label(
                                    viewModel.isLoggingOut ? "退出中…" : "退出登录",
                                    systemImage: "rectangle.portrait.and.arrow.right"
                                )
                            }
                            .disabled(viewModel.isLoggingOut)
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(FireTheme.subtleInk)
                    }
                }
            }
            .navigationDestination(isPresented: $showDeveloperTools) {
                FireDeveloperToolsView(viewModel: viewModel)
            }
            .refreshable {
                await profileViewModel.refreshAll()
            }
            .task(id: profileViewModel.currentUsername) {
                profileViewModel.syncWithCurrentSession()
            }
            .alert("确认退出", isPresented: $showLogoutConfirmation) {
                Button("取消", role: .cancel) {}
                Button("退出登录", role: .destructive) {
                    viewModel.logout()
                }
            } message: {
                Text("确定要退出当前账号吗？")
            }
        }
    }

    private var profileHeader: some View {
        FireProfileHeaderCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    FireAvatarView(
                        avatarTemplate: profileViewModel.profile?.avatarTemplate,
                        username: displayUsername,
                        size: 86
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(displayName)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(FireTheme.ink)
                                .lineLimit(2)

                            if let profile = profileViewModel.profile {
                                FireProfileTrustLevelPill(trustLevel: profile.trustLevel)
                            }
                        }

                        Text("@\(displayUsername)")
                            .font(.subheadline)
                            .foregroundStyle(FireTheme.subtleInk)

                        if let bioCooked = profileViewModel.profile?.bioCooked, !bioCooked.isEmpty {
                            Text(plainTextFromHtml(rawHtml: bioCooked))
                                .font(.footnote)
                                .foregroundStyle(FireTheme.subtleInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    FireProfileStatsRow(items: profileHighlights)

                    if hasProfileMeta {
                        Divider()
                            .overlay(FireTheme.divider)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                            ],
                            spacing: 14
                        ) {
                            ForEach(Array(profileMetaEntries.enumerated()), id: \.offset) { _, item in
                                FireProfileMetaEntryView(
                                    symbol: item.symbol,
                                    label: item.label,
                                    value: item.value,
                                    tint: item.tint
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ action: UserActionState) -> some View {
        if let row = topicRow(for: action) {
            NavigationLink {
                FireTopicDetailView(
                    viewModel: viewModel,
                    row: row,
                    scrollToPostNumber: action.postNumber
                )
            } label: {
                FireProfileActivityRow(action: action)
            }
            .buttonStyle(.plain)
        } else {
            FireProfileActivityRow(action: action)
        }
    }

    private func topicRow(for action: UserActionState) -> FireTopicRowPresentation? {
        guard let topicId = action.topicId else {
            return nil
        }

        let resolvedSlug = {
            let trimmed = action.slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "topic-\(topicId)" : trimmed
        }()

        return .stub(
            topicId: topicId,
            title: action.title?.ifEmpty("话题 #\(topicId)") ?? "话题 #\(topicId)",
            slug: resolvedSlug,
            categoryId: action.categoryId
        )
    }

    private func shortcutRowContent(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FireTheme.ink)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(FireTheme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func errorBanner(message: String) -> some View {
        FireErrorBanner(
            message: message,
            copied: copiedErrorMessage,
            onCopy: {
                UIPasteboard.general.string = message
                copiedErrorMessage = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    copiedErrorMessage = false
                }
            },
            onDismiss: {
                profileViewModel.errorMessage = nil
                viewModel.dismissError()
            }
        )
        .padding(.vertical, 2)
    }

    private var hasProfileMeta: Bool {
        !profileMetaEntries.isEmpty
    }

    private var joinedDateText: String? {
        formattedDate(profileViewModel.profile?.createdAt)
    }

    private var lastSeenText: String? {
        guard let lastSeen = profileViewModel.profile?.lastSeenAt else {
            return nil
        }

        return relativeTimeString(lastSeen)
    }

    private var readTimeText: String? {
        let seconds = profileViewModel.summary?.stats.timeReadSeconds ?? 0
        guard seconds > 0 else {
            return nil
        }

        return formatReadTime(seconds)
    }

    private var gamificationText: String? {
        guard let score = profileViewModel.profile?.gamificationScore, score > 0 else {
            return nil
        }

        return formatNumber(score)
    }

    private func formatNumber(_ value: UInt32) -> String {
        if value >= 10000 {
            return String(format: "%.1fw", Double(value) / 10000.0)
        }
        if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return "\(value)"
    }

    private func formatReadTime(_ seconds: UInt64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(hours) 小时"
        }
        if minutes > 0 {
            return "\(minutes) 分钟"
        }
        return "不到 1 分钟"
    }

    private func formattedDate(_ isoDate: String?) -> String? {
        guard let isoDate else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date: Date?
        if let parsed = formatter.date(from: isoDate) {
            date = parsed
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: isoDate)
        }

        guard let date else {
            return nil
        }

        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    private func relativeTimeString(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date: Date?
        if let parsed = formatter.date(from: isoDate) {
            date = parsed
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: isoDate)
        }

        guard let date else {
            return isoDate
        }

        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
