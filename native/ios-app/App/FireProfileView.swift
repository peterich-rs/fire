import SwiftUI
import UIKit

struct FireProfileView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @State private var copiedErrorMessage = false

    private var username: String {
        viewModel.session.profileDisplayName
    }

    private var isLoggedIn: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    private var canLogout: Bool {
        viewModel.session.hasLoginSession || isLoggedIn
    }

    private var sessionStatusColor: Color {
        if viewModel.session.readiness.hasCurrentUser {
            return .green
        }
        if isLoggedIn {
            return .orange
        }
        return .red
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = viewModel.errorMessage {
                    errorSection(message: errorMessage)
                }

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
                            .fill(sessionStatusColor)
                            .frame(width: 8, height: 8)

                        Text(viewModel.session.profileStatusTitle)
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
                    value: "\(viewModel.topicRows.reduce(0) { $0 + Int($1.topic.unreadPosts) })",
                    label: "未读帖子"
                )
                Divider()
                    .frame(height: 30)
                statItem(
                    value: "\(viewModel.topicRows.filter(\.hasAcceptedAnswer).count)",
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
            LabeledContent("账号") {
                HStack(spacing: 4) {
                    Circle()
                        .fill(sessionStatusColor)
                        .frame(width: 8, height: 8)
                    Text(viewModel.session.bootstrap.currentUsername ?? (isLoggedIn ? "等待同步" : "未登录"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("登录阶段", value: viewModel.session.profileStatusTitle)

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
            .disabled(viewModel.isLoggingOut)

            Button {
                viewModel.loadInitialState()
            } label: {
                Label("恢复会话", systemImage: "arrow.counterclockwise")
            }
            .disabled(viewModel.isLoggingOut)

            if canLogout {
                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    HStack(spacing: 12) {
                        Label(
                            viewModel.isLoggingOut ? "退出中…" : "退出登录",
                            systemImage: "rectangle.portrait.and.arrow.right"
                        )

                        Spacer()

                        if viewModel.isLoggingOut {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(viewModel.isLoggingOut)
            } else {
                Button {
                    viewModel.openLogin()
                } label: {
                    Label(
                        viewModel.isPreparingLogin ? "准备登录中…" : "登录 LinuxDo",
                        systemImage: "person.badge.key"
                    )
                }
                .disabled(viewModel.isPreparingLogin || viewModel.isLoggingOut)
            }
        }
    }

    private func errorSection(message: String) -> some View {
        Section {
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
                onDismiss: viewModel.dismissError
            )
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
