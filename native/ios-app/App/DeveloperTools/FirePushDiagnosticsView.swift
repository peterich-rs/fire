import SwiftUI

struct FirePushDiagnosticsView: View {
    @ObservedObject var pushCoordinator: FirePushRegistrationCoordinator

    private var diagnostics: FirePushRegistrationDiagnostics {
        pushCoordinator.diagnostics
    }

    var body: some View {
        List {
            Section {
                Text("当前阶段只申请系统通知权限并在本地保存 APNs token；不会把 token 上传到 LinuxDo 后端。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 0) {
                    FireDiagnosticsMiniStat(
                        value: diagnostics.authorizationStatusTitle,
                        label: "权限",
                        color: diagnostics.authorizationStatus == .denied ? .red : .primary
                    )
                    FireDiagnosticsMiniStat(
                        value: diagnostics.registrationStateTitle,
                        label: "注册状态",
                        color: diagnostics.registrationState == .failed ? .red : .secondary
                    )
                }
            }

            if let deviceToken = diagnostics.deviceTokenHex, !deviceToken.isEmpty {
                Section("Device Token") {
                    Text(deviceToken)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let errorMessage = diagnostics.lastErrorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await pushCoordinator.ensurePushRegistration()
                        }
                    } label: {
                        Label(pushActionTitle(for: diagnostics), systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("刷新状态") {
                        Task {
                            await pushCoordinator.refreshAuthorizationStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if diagnostics.authorizationStatus == .denied {
                Section {
                    Text("如需继续验证 APNs 注册，请先在系统设置里重新开启通知权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let updatedAt = diagnostics.lastUpdatedAtUnixMs {
                Section {
                    Text("最近更新：\(FireDiagnosticsPresentation.timestamp(updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("推送诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pushActionTitle(for diagnostics: FirePushRegistrationDiagnostics) -> String {
        switch diagnostics.authorizationStatus {
        case .notDetermined:
            return "请求权限"
        case .denied:
            return "重新检测"
        default:
            return "重新注册"
        }
    }
}
