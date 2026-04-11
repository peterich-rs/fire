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
}
