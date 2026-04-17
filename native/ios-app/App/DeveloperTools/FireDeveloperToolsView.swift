import SwiftUI

struct FireDeveloperToolsView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var diagnosticsViewModel: FireDiagnosticsViewModel
    @StateObject private var pushRegistrationCoordinator = FirePushRegistrationCoordinator.shared

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
        _diagnosticsViewModel = StateObject(
            wrappedValue: FireDiagnosticsViewModel(appViewModel: viewModel)
        )
    }

    // MARK: - Session Status

    private var isLoggedIn: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    private var sessionStatusColor: Color {
        if viewModel.session.readiness.hasCurrentUser { return .green }
        if isLoggedIn { return .orange }
        return .red
    }

    // MARK: - Body

    var body: some View {
        List {
            errorSection
            navigationSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("开发者工具")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            diagnosticsViewModel.refresh()
            await pushRegistrationCoordinator.refreshAuthorizationStatus()
        }
        .refreshable {
            diagnosticsViewModel.refresh()
            await pushRegistrationCoordinator.refreshAuthorizationStatus()
        }
    }

    // MARK: - Error Section

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = diagnosticsViewModel.errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Navigation Section

    private var navigationSection: some View {
        Section {
            // 1. Account Status
            NavigationLink {
                FireAccountStatusView(viewModel: viewModel)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("账号状态")
                        Text(viewModel.session.profileStatusTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.circle")
                        .foregroundStyle(sessionStatusColor)
                }
            }

            // 2. Network
            NavigationLink {
                FireNetworkTracesListView(viewModel: diagnosticsViewModel)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("网络请求")
                        Text(networkSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "network")
                }
            }

            // 3. Logs
            NavigationLink {
                FireLogFilesListView(viewModel: diagnosticsViewModel)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("日志文件")
                        Text(logSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.text")
                }
            }

            // 4. APM
            NavigationLink {
                FireAPMDiagnosticsView(viewModel: diagnosticsViewModel)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("APM 概览")
                        Text(apmSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "chart.bar")
                }
            }

            // 5. Push
            NavigationLink {
                FirePushDiagnosticsView(pushCoordinator: pushRegistrationCoordinator)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("远程通知")
                        Text(pushSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell")
                }
            }

            // 6. Export
            NavigationLink {
                FireExportDiagnosticsView(viewModel: diagnosticsViewModel)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("导出与分享")
                        Text(exportSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
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

    // MARK: - Subtitles

    private var networkSubtitle: String {
        let total = diagnosticsViewModel.requestTraces.count
        let failed = diagnosticsViewModel.failedCount
        var parts = ["\(total) 请求"]
        if failed > 0 {
            parts.append("\(failed) 失败")
        }
        if let avgMs = diagnosticsViewModel.averageDurationMs {
            parts.append("平均 \(avgMs)ms")
        }
        return parts.joined(separator: " · ")
    }

    private var logSubtitle: String {
        let count = diagnosticsViewModel.logFiles.count
        let size = FireDiagnosticsPresentation.byteSize(diagnosticsViewModel.totalLogSizeBytes)
        return "\(count) 文件 · \(size)"
    }

    private var apmSubtitle: String {
        let cpu = diagnosticsViewModel.apmSummary.currentSample?.cpuPercent
            .map { String(format: "CPU %.1f%%", $0) } ?? "CPU N/A"
        let mem = diagnosticsViewModel.apmSummary.currentSample?.physicalFootprintBytes
            .map { "Mem \(FireDiagnosticsPresentation.byteSize($0))" } ?? "Mem N/A"
        return "\(cpu) · \(mem)"
    }

    private var pushSubtitle: String {
        let diagnostics = pushRegistrationCoordinator.diagnostics
        return "\(diagnostics.authorizationStatusTitle) · \(diagnostics.registrationStateTitle)"
    }

    private var exportSubtitle: String {
        if let sessionID = diagnosticsViewModel.diagnosticSessionID {
            let truncated = sessionID.prefix(12)
            return "Session \(truncated)..."
        }
        return "Session ID 加载中"
    }
}
