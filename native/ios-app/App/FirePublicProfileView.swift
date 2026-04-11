import SwiftUI
import UIKit

private struct FireSelectedBadge: Identifiable, Hashable {
    let badge: BadgeState
    var id: UInt64 { badge.id }
}

struct FirePublicProfileView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let username: String

    @StateObject private var profileViewModel: FireProfileViewModel
    @State private var selectedBadge: FireSelectedBadge?
    @State private var isUpdatingFollow = false

    init(viewModel: FireAppViewModel, username: String) {
        self.viewModel = viewModel
        self.username = username
        _profileViewModel = StateObject(
            wrappedValue: FireProfileViewModel(appViewModel: viewModel, fixedUsername: username)
        )
    }

    private var displayUsername: String {
        profileViewModel.currentUsername ?? username
    }

    private var displayName: String {
        let trimmed = profileViewModel.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? displayUsername : trimmed
    }

    private var profileHighlights: [(value: String, label: String)] {
        [
            (formatNumber(profileViewModel.profile?.totalFollowers ?? 0), "粉丝"),
            (formatNumber(profileViewModel.summary?.stats.likesReceived ?? 0), "获赞"),
            (formatNumber(profileViewModel.profile?.totalFollowing ?? 0), "关注"),
        ]
    }

    private var recentActions: [UserActionState] {
        Array(profileViewModel.actions.prefix(4))
    }

    private var isOwnProfile: Bool {
        let current = viewModel.session.bootstrap.currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        return current?.caseInsensitiveCompare(displayUsername) == .orderedSame
    }

    private var canFollow: Bool {
        !isOwnProfile && (profileViewModel.profile?.canFollow ?? false)
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

    var body: some View {
        List {
            if let errorMessage = profileViewModel.errorMessage ?? viewModel.errorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            profileViewModel.errorMessage = nil
                            viewModel.dismissError()
                        }
                    )
                }
            }

            Section {
                profileHeader
            }

            Section {
                NavigationLink {
                    FireFollowListView(
                        viewModel: viewModel,
                        username: displayUsername,
                        kind: .following
                    )
                } label: {
                    socialShortcutRow(
                        icon: "person.2",
                        tint: FireTheme.accent,
                        title: "关注",
                        value: profileViewModel.profile?.totalFollowing ?? 0
                    )
                }

                NavigationLink {
                    FireFollowListView(
                        viewModel: viewModel,
                        username: displayUsername,
                        kind: .followers
                    )
                } label: {
                    socialShortcutRow(
                        icon: "person.2.fill",
                        tint: .pink,
                        title: "粉丝",
                        value: profileViewModel.profile?.totalFollowers ?? 0
                    )
                }
            }

            if let badges = profileViewModel.summary?.badges, !badges.isEmpty {
                Section {
                    FlowLayout(
                        spacing: 8,
                        fallbackWidth: max(UIScreen.main.bounds.width - 72, 220)
                    ) {
                        ForEach(Array(badges.prefix(8)), id: \.id) { badge in
                            Button {
                                selectedBadge = FireSelectedBadge(badge: badge)
                            } label: {
                                FireProfileBadgeChip(badge: badge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("徽章")
                }
            }

            Section {
                if recentActions.isEmpty, profileViewModel.isLoadingActions {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                } else if recentActions.isEmpty {
                    Text("暂无动态")
                        .font(.subheadline)
                        .foregroundStyle(FireTheme.tertiaryInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(Array(recentActions.enumerated()), id: \.offset) { _, action in
                        activityRow(action)
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
                }
            } header: {
                Text("最近动态")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FireTheme.canvasTop)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedBadge) { item in
            FireBadgeDetailView(viewModel: viewModel, badgeID: item.badge.id, initialBadge: item.badge)
        }
        .refreshable {
            await profileViewModel.refreshAll()
        }
        .task(id: username) {
            profileViewModel.loadProfile(force: true)
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

                        if canFollow {
                            Button {
                                Task { await toggleFollow() }
                            } label: {
                                HStack(spacing: 8) {
                                    if isUpdatingFollow {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(profileViewModel.profile?.isFollowed == true ? "取消关注" : "关注")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(profileViewModel.profile?.isFollowed == true ? FireTheme.subtleInk : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    (profileViewModel.profile?.isFollowed == true ? FireTheme.softSurface : FireTheme.accent),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdatingFollow)
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

    private func formatNumber(_ value: UInt32) -> String {
        if value >= 10000 {
            return String(format: "%.1fw", Double(value) / 10000.0)
        }
        if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return "\(value)"
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

    private func socialShortcutRow(
        icon: String,
        tint: Color,
        title: String,
        value: UInt32
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
                Text("\(formatNumber(value)) 人")
                    .font(.caption)
                    .foregroundStyle(FireTheme.subtleInk)
            }

            Spacer(minLength: 12)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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

    private func toggleFollow() async {
        guard !isUpdatingFollow else { return }
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }

        do {
            if profileViewModel.profile?.isFollowed == true {
                try await viewModel.unfollowUser(username: username)
            } else {
                try await viewModel.followUser(username: username)
            }
            await profileViewModel.refreshAll()
        } catch {
            profileViewModel.errorMessage = error.localizedDescription
        }
    }
}
