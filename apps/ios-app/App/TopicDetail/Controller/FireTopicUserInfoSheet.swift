import SwiftUI

struct FireTopicUserInfoSheet: View {
    @ObservedObject var viewModel: FireAppViewModel
    let username: String
    let onMessage: (UserProfileState) -> Void

    @State private var profile: UserProfileState?
    @State private var summary: UserSummaryState?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let profile {
                header(profile)
                FireProfileStatsRow(items: [
                    (formatNumber(summary?.stats.topicCount ?? 0), "话题"),
                    (formatNumber(summary?.stats.postCount ?? 0), "回复"),
                    (formatNumber(summary?.stats.likesReceived ?? 0), "获赞"),
                    (formatNumber(profile.totalFollowers), "粉丝"),
                ])
                metaRows(profile)
                if let bio = profile.bioPlainText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !bio.isEmpty {
                    Text(bio)
                        .font(.footnote)
                        .foregroundStyle(FireTheme.subtleInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if canSendPrivateMessage(profile) {
                    Button {
                        onMessage(profile)
                    } label: {
                        Label("发私信", systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FireTheme.accent)
                }
            } else if isLoading {
                ProgressView("正在加载用户信息...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(errorMessage ?? "无法加载用户信息。")
                    .font(.footnote)
                    .foregroundStyle(FireTheme.subtleInk)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: username) {
            await load()
        }
    }

    private func header(_ profile: UserProfileState) -> some View {
        HStack(alignment: .center, spacing: 14) {
            FireAvatarView(
                avatarTemplate: profile.avatarTemplate,
                username: profile.username,
                size: 64,
                baseURLString: viewModel.session.bootstrap.baseUrl.ifEmpty("https://linux.do")
            )

            VStack(alignment: .leading, spacing: 5) {
                Text((profile.name ?? "").ifEmpty(profile.username))
                    .font(.headline)
                    .foregroundStyle(FireTheme.ink)
                Text("@\(profile.username) · \(profile.trustLevelLabel)")
                    .font(.caption)
                    .foregroundStyle(FireTheme.tertiaryInk)
            }
        }
    }

    @ViewBuilder
    private func metaRows(_ profile: UserProfileState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let createdAt = profile.createdAt, !createdAt.isEmpty {
                FireProfileMetaEntryView(symbol: "calendar", label: "加入时间", value: createdAt)
            }
            if let lastSeenAt = profile.lastSeenAt, !lastSeenAt.isEmpty {
                FireProfileMetaEntryView(symbol: "clock", label: "最近活跃", value: lastSeenAt)
            }
            if let score = profile.gamificationScore {
                FireProfileMetaEntryView(symbol: "sparkles", label: "积分", value: formatNumber(score))
            }
        }
    }

    private func load() async {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let fetchedProfile = viewModel.fetchUserProfile(username: normalized)
            async let fetchedSummary = viewModel.fetchUserSummary(username: normalized)
            let (profile, summary) = try await (fetchedProfile, fetchedSummary)
            self.profile = profile
            self.summary = summary
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func canSendPrivateMessage(_ profile: UserProfileState) -> Bool {
        let current = viewModel.session.bootstrap.currentUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return current?.localizedCaseInsensitiveCompare(profile.username) != ComparisonResult.orderedSame
            && profile.canSendPrivateMessageToUser
    }

    private func formatNumber(_ value: UInt32) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000.0)
        }
        return "\(value)"
    }
}
