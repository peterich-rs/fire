import SwiftUI

struct FireProfileView: View {
    @ObservedObject var viewModel: FireAppViewModel

    private var username: String {
        viewModel.session.bootstrap.currentUsername ?? "未登录"
    }

    private var isLoggedIn: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoggedIn {
                    userHeaderSection
                    statsSection
                }

                sessionSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的")
        }
    }

    // MARK: - User Header

    private var userHeaderSection: some View {
        Section {
            HStack(spacing: 14) {
                FireAvatarView(
                    avatarTemplate: nil,
                    username: username,
                    size: 54
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(username)
                        .font(.title3.weight(.semibold))

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)

                        Text(viewModel.session.loginPhase.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            HStack(spacing: 0) {
                statItem(value: "\(viewModel.topicRows.count)", label: "已加载话题")
                Divider()
                    .frame(height: 30)
                statItem(
                    value: "\(viewModel.topics.reduce(0) { $0 + Int($1.unreadPosts) })",
                    label: "未读帖子"
                )
                Divider()
                    .frame(height: 30)
                statItem(
                    value: "\(viewModel.topics.filter(\.hasAcceptedAnswer).count)",
                    label: "已解决"
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session Info

    private var sessionSection: some View {
        Section("会话信息") {
            LabeledContent("Base URL", value: viewModel.session.bootstrap.baseUrl)

            LabeledContent("Bootstrap") {
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.session.bootstrap.hasPreloadedData ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.session.bootstrap.hasPreloadedData ? "就绪" : "等待中")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("CSRF") {
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.session.cookies.csrfToken != nil ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.session.cookies.csrfToken != nil ? "就绪" : "缺失")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("API 权限") {
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.session.readiness.canReadAuthenticatedApi ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.session.readiness.canReadAuthenticatedApi ? "可用" : "不可用")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            NavigationLink {
                FireDiagnosticsView(viewModel: viewModel)
            } label: {
                Label("诊断工具", systemImage: "ant")
            }

            Button {
                viewModel.refreshBootstrap()
            } label: {
                Label("刷新 Bootstrap", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                viewModel.loadInitialState()
            } label: {
                Label("恢复会话", systemImage: "arrow.counterclockwise")
            }

            if isLoggedIn {
                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    viewModel.openLogin()
                } label: {
                    Label(
                        viewModel.isPreparingLogin ? "准备登录中…" : "登录 LinuxDo",
                        systemImage: "person.badge.key"
                    )
                }
                .disabled(viewModel.isPreparingLogin)
            }
        }
    }
}
