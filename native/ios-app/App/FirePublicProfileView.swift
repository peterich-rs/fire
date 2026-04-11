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

    private var socialStats: [(value: String, label: String)] {
        [
            (formatNumber(profileViewModel.profile?.totalFollowers ?? 0), "粉丝"),
            (formatNumber(profileViewModel.profile?.totalFollowing ?? 0), "关注"),
            (formatNumber(profileViewModel.summary?.stats.likesReceived ?? 0), "获赞"),
        ]
    }

    private var overviewMetrics: [(label: String, value: String)] {
        let stats = profileViewModel.summary?.stats
        return [
            ("话题", formatNumber(stats?.topicCount ?? 0)),
            ("帖子", formatNumber(stats?.postCount ?? 0)),
            ("书签", formatNumber(stats?.bookmarkCount ?? 0)),
            ("访问天数", formatNumber(stats?.daysVisited ?? 0)),
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
            .listRowSeparator(.hidden)

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

            Section {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    ForEach(Array(overviewMetrics.enumerated()), id: \.offset) { _, item in
                        FireMetricTile(label: item.label, value: item.value)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("概览")
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                FireAvatarView(
                    avatarTemplate: profileViewModel.profile?.avatarTemplate,
                    username: displayUsername,
                    size: 84
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(FireTheme.ink)

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

            FireProfileStatsRow(items: socialStats)
        }
        .padding(.vertical, 4)
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
                FireProfileActivityRow(action: action, showsChevron: true)
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

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(FireTheme.tertiaryInk)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
