import SwiftUI
import UIKit

struct FireCDKView: View {
    @ObservedObject var viewModel: FireAppViewModel

    @State private var userInfo: CdkUserInfoState?
    @State private var authorization: CdkAuthorizationUrlState?
    @State private var approvalLink: String?
    @State private var approvalStatus: LdcApprovalStatusState?
    @State private var isLoadingUserInfo = false
    @State private var isPreparingAuthorization = false
    @State private var isCompletingAuthorization = false
    @State private var isLoggingOut = false
    @State private var copiedErrorMessage = false
    @State private var noticeMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let noticeMessage {
                Section {
                    noticeRow(message: noticeMessage)
                }
            }

            if let errorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: copiedErrorMessage,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                            copiedErrorMessage = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                copiedErrorMessage = false
                            }
                        },
                        onDismiss: {
                            self.errorMessage = nil
                        }
                    )
                }
            }

            Section {
                if isLoadingUserInfo && userInfo == nil {
                    loadingRow
                } else if let userInfo {
                    accountOverview(userInfo)
                } else {
                    emptyState
                }
            } header: {
                Text("连接状态")
            }

            authorizationSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FireTheme.canvasMid)
        .navigationTitle("CDK 连接")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadUserInfo(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoadingUserInfo || isCompletingAuthorization || isLoggingOut)
                .accessibilityLabel("刷新")
            }
        }
        .task {
            await loadUserInfo(force: false)
        }
        .refreshable {
            await loadUserInfo(force: true)
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 20)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "key")
                .font(.title2)
                .foregroundStyle(FireTheme.tertiaryInk)

            Text("还没有 CDK 授权信息")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FireTheme.ink)

            Text("完成授权后可以查看连接账号和积分。")
                .font(.caption)
                .foregroundStyle(FireTheme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private func accountOverview(_ info: CdkUserInfoState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.nickname.isEmpty ? "@\(info.username)" : info.nickname)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(FireTheme.ink)

                    Text("@\(info.username) · TL\(info.trustLevel)")
                        .font(.caption)
                        .foregroundStyle(FireTheme.subtleInk)
                }

                Spacer()

                FireStatusChip(label: "已连接", tone: .success)
            }

            FireMetricTile(label: "CDK 积分", value: "\(info.score)")
        }
        .padding(.vertical, 4)
    }

    private var authorizationSection: some View {
        Section("授权") {
            Button {
                Task { await prepareAuthorization() }
            } label: {
                HStack {
                    if isPreparingAuthorization {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isPreparingAuthorization ? "准备授权…" : "获取授权链接")
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            .disabled(isPreparingAuthorization || isCompletingAuthorization || isLoggingOut)

            if let authorization {
                FireKeyValueRow(label: "state", value: authorization.state)
                copyableRow(label: "授权地址", value: authorization.url)
            }

            if let approvalLink {
                copyableRow(label: "确认路径", value: approvalLink)

                Button {
                    Task { await completeAuthorization(approvalPath: approvalLink) }
                } label: {
                    HStack {
                        if isCompletingAuthorization {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isCompletingAuthorization ? "确认中…" : "确认并完成授权")
                            .fontWeight(.medium)
                        Spacer()
                    }
                }
                .disabled(isCompletingAuthorization || isLoggingOut)
            }

            if let approvalStatus {
                FireKeyValueRow(label: "确认状态", value: approvalText(approvalStatus))
            }

            if userInfo != nil {
                Button(role: .destructive) {
                    Task { await logout() }
                } label: {
                    HStack {
                        if isLoggingOut {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isLoggingOut ? "退出中…" : "退出 CDK 授权")
                            .fontWeight(.medium)
                        Spacer()
                    }
                }
                .disabled(isCompletingAuthorization || isLoggingOut)
            }
        }
    }

    private func copyableRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(FireTheme.tertiaryInk)

            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(FireTheme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UIPasteboard.general.string = value
                noticeMessage = "\(label)已复制"
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(FireTheme.accent)
        }
        .padding(.vertical, 4)
    }

    private func noticeRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(FireTheme.success)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(FireTheme.ink)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func loadUserInfo(force: Bool) async {
        guard !isLoadingUserInfo, force || userInfo == nil else { return }
        isLoadingUserInfo = true
        defer { isLoadingUserInfo = false }

        do {
            userInfo = try await viewModel.cdkUserInfo()
            errorMessage = nil
        } catch {
            if userInfo == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareAuthorization() async {
        isPreparingAuthorization = true
        defer { isPreparingAuthorization = false }

        do {
            let auth = try await viewModel.cdkAuthorizationUrl()
            authorization = auth
            approvalLink = try await viewModel.cdkApprovalLink(authorizationURL: auth.url)
            approvalStatus = nil
            noticeMessage = "授权链接已准备"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeAuthorization(approvalPath: String) async {
        isCompletingAuthorization = true
        defer { isCompletingAuthorization = false }

        do {
            let status = try await viewModel.cdkApprove(approvePath: approvalPath)
            approvalStatus = status
            switch status.kind {
            case .approved:
                guard let code = status.code, let state = status.state else {
                    errorMessage = "授权确认成功，但回调参数不完整。"
                    noticeMessage = nil
                    return
                }
                try await viewModel.cdkCallback(code: code, state: state)
                userInfo = try await viewModel.cdkUserInfo()
                noticeMessage = "CDK 授权已完成"
                errorMessage = nil
            case .pending:
                noticeMessage = "授权仍在等待确认"
                errorMessage = nil
            case .denied:
                errorMessage = "CDK 授权已被拒绝"
                noticeMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func logout() async {
        isLoggingOut = true
        defer { isLoggingOut = false }

        do {
            try await viewModel.cdkLogout()
            userInfo = nil
            authorization = nil
            approvalLink = nil
            approvalStatus = nil
            noticeMessage = "已退出 CDK 授权"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func approvalText(_ status: LdcApprovalStatusState) -> String {
        switch status.kind {
        case .pending:
            return "等待确认"
        case .approved:
            return "已确认"
        case .denied:
            return "已拒绝"
        }
    }
}
