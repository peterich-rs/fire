import SwiftUI
import UIKit

struct FireProfileView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @ObservedObject var profileViewModel: FireProfileViewModel
    @State private var copiedErrorMessage = false
    @State private var showLogoutConfirmation = false
    @State private var showComingSoonToast = false

    private var isLoggedIn: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    private var canLogout: Bool {
        viewModel.session.hasLoginSession || isLoggedIn
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let errorMessage = profileViewModel.errorMessage ?? viewModel.errorMessage {
                        errorBanner(message: errorMessage)
                    }

                    profileHeader
                    statsRow
                    badgesSection
                    activitySection
                    settingsSection
                }
            }
            .refreshable {
                await profileViewModel.refreshProfile()
            }
            .background(FireTheme.canvasTop)
            .navigationTitle("我的")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(FireTheme.subtleInk)
                }
            }
            .task(id: profileViewModel.currentUsername) {
                profileViewModel.syncWithCurrentSession()
            }
            .overlay {
                if showComingSoonToast {
                    comingSoonToast
                }
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            LinearGradient(
                colors: [FireTheme.accent.opacity(0.3), FireTheme.canvasTop],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .overlay(alignment: .bottom) {
                headerContent
                    .offset(y: 36)
            }

            Spacer()
                .frame(height: 40)
        }
    }

    private var headerContent: some View {
        VStack(spacing: 8) {
            FireAvatarView(
                avatarTemplate: profileViewModel.profile?.avatarTemplate,
                username: profileViewModel.currentUsername ?? viewModel.session.profileDisplayName,
                size: 72
            )

            VStack(spacing: 4) {
                if let name = profileViewModel.profile?.name, !name.isEmpty {
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FireTheme.ink)
                }

                HStack(spacing: 6) {
                    Text("@\(profileViewModel.currentUsername ?? viewModel.session.profileDisplayName)")
                        .font(.subheadline)
                        .foregroundStyle(FireTheme.subtleInk)

                    if let profile = profileViewModel.profile {
                        FireProfileTrustLevelPill(trustLevel: profile.trustLevel)
                    }
                }

                if let bioCooked = profileViewModel.profile?.bioCooked, !bioCooked.isEmpty {
                    Text(plainTextFromHtml(rawHtml: bioCooked))
                        .font(.caption)
                        .foregroundStyle(FireTheme.subtleInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        let following = profileViewModel.profile?.totalFollowing ?? 0
        let followers = profileViewModel.profile?.totalFollowers ?? 0
        let likes = profileViewModel.summary?.stats.likesReceived ?? 0
        let daysVisited = profileViewModel.summary?.stats.daysVisited ?? 0

        return FireProfileStatsRow(items: [
            (value: formatNumber(UInt32(following)), label: "关注"),
            (value: formatNumber(UInt32(followers)), label: "粉丝"),
            (value: formatNumber(likes), label: "获赞"),
            (value: formatNumber(daysVisited), label: "访问天数"),
        ])
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Badges Section

    @ViewBuilder
    private var badgesSection: some View {
        if let badges = profileViewModel.summary?.badges, !badges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("勋章")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FireTheme.ink)
                    Spacer()
                    Text("查看全部 >")
                        .font(.caption)
                        .foregroundStyle(FireTheme.subtleInk)
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(badges, id: \.id) { badge in
                            FireProfileBadgeChip(badge: badge)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(spacing: 0) {
            Picker("Activity", selection: Binding(
                get: { profileViewModel.selectedTab },
                set: { profileViewModel.selectTab($0) }
            )) {
                ForEach(FireProfileViewModel.ProfileTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)

            LazyVStack(spacing: 0) {
                ForEach(Array(profileViewModel.actions.enumerated()), id: \.offset) { index, action in
                    FireProfileActivityRow(action: action) {
                    }
                    .padding(.horizontal, 16)

                    if index < profileViewModel.actions.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }

                    if index == profileViewModel.actions.count - 3 {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                profileViewModel.loadActions(reset: false)
                            }
                    }
                }

                if profileViewModel.isLoadingActions {
                    ProgressView()
                        .padding(.vertical, 16)
                }

                if profileViewModel.actions.isEmpty && !profileViewModel.isLoadingActions && !profileViewModel.isLoadingProfile {
                    Text("暂无动态")
                        .font(.subheadline)
                        .foregroundStyle(FireTheme.tertiaryInk)
                        .padding(.vertical, 32)
                }
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.top, 16)

            VStack(spacing: 0) {
                settingsRow(icon: "bookmark", title: "我的书签", showChevron: true) {
                    showComingSoonToast = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        showComingSoonToast = false
                    }
                }

                Divider()
                    .padding(.leading, 44)

                NavigationLink {
                    FireDeveloperToolsView(viewModel: viewModel)
                } label: {
                    settingsRowContent(icon: "wrench.and.screwdriver", title: "开发者工具", showChevron: true)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 44)

                if canLogout {
                    settingsRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: viewModel.isLoggingOut ? "退出中…" : "退出登录",
                        isDestructive: true,
                        showChevron: false
                    ) {
                        showLogoutConfirmation = true
                    }
                    .disabled(viewModel.isLoggingOut)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .padding(.bottom, 32)
    }

    private func settingsRow(
        icon: String,
        title: String,
        isDestructive: Bool = false,
        showChevron: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRowContent(icon: icon, title: title, isDestructive: isDestructive, showChevron: showChevron)
        }
        .buttonStyle(.plain)
    }

    private func settingsRowContent(
        icon: String,
        title: String,
        isDestructive: Bool = false,
        showChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(isDestructive ? .red : FireTheme.subtleInk)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(isDestructive ? .red : FireTheme.ink)

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FireTheme.tertiaryInk)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Error Banner

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
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Coming Soon Toast

    private var comingSoonToast: some View {
        VStack {
            Spacer()
            Text("即将推出")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(.bottom, 32)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.3), value: showComingSoonToast)
    }

    // MARK: - Helpers

    private func formatNumber(_ value: UInt32) -> String {
        if value >= 10000 {
            return String(format: "%.1fw", Double(value) / 10000.0)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return "\(value)"
    }
}
