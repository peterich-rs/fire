import SwiftUI
import UIKit

struct FireDeveloperToolsView: View {
    @ObservedObject var viewModel: FireAppViewModel

    private var isLoggedIn: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
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
        List {
            sessionSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("开发者工具")
        .navigationBarTitleDisplayMode(.inline)
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

            LabeledContent("站点元数据") {
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.session.bootstrap.hasSiteMetadata ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.session.bootstrap.hasSiteMetadata ? "就绪" : "缺失")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("站点设置") {
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.session.bootstrap.hasSiteSettings ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.session.bootstrap.hasSiteSettings ? "就绪" : "缺失")
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
        }
    }
}
