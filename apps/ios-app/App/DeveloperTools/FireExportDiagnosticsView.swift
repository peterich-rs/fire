import SwiftUI

struct FireExportDiagnosticsView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if let diagnosticSessionID = viewModel.diagnosticSessionID {
                Section("Session ID") {
                    Text(diagnosticSessionID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                exportActionTile(
                    title: "Rust 诊断快照",
                    subtitle: "JSON，包含当前会话、最近日志和网络请求摘要，适合快速留档或单独转交。",
                    formatLabel: "JSON",
                    accent: .gray,
                    primaryProminent: false,
                    isBusy: viewModel.isExportingSupportBundle,
                    primaryTitle: viewModel.isExportingSupportBundle ? "导出中…" : "导出 JSON",
                    primarySystemImage: "doc.badge.arrow.up",
                    onPrimaryTap: {
                        viewModel.exportSupportBundle(
                            scenePhase: scenePhaseLabel(scenePhase)
                        )
                    },
                    secondaryTitle: viewModel.supportBundleURL() == nil ? nil : "分享上次导出",
                    onSecondaryTap: {
                        viewModel.presentSupportBundleShare()
                    }
                ) {
                    supportBundleMetadata
                }
            }

            Section {
                exportActionTile(
                    title: "完整 APM 采集包",
                    subtitle: "ZIP，附带 crash、MetricKit、runtime breadcrumbs 以及临时生成的 Rust 诊断快照，适合完整排障。",
                    formatLabel: "ZIP",
                    accent: .teal,
                    primaryProminent: true,
                    isBusy: viewModel.isExportingFullAPMSupportBundle,
                    primaryTitle: viewModel.isExportingFullAPMSupportBundle ? "生成中…" : "生成并分享 ZIP",
                    primarySystemImage: "archivebox",
                    onPrimaryTap: {
                        viewModel.exportFullAPMSupportBundle(
                            scenePhase: scenePhaseLabel(scenePhase)
                        )
                    },
                    secondaryTitle: viewModel.fullAPMSupportBundleURL() == nil ? nil : "再次分享",
                    onSecondaryTap: {
                        viewModel.presentFullAPMSupportBundleShare()
                    }
                ) {
                    fullAPMSupportBundleMetadata
                }
            }

            Section {
                Label("完整 APM ZIP 最多保留最近 3 份，并在 24 小时后自动过期清理；打包临时目录会在导出结束后立即删除。", systemImage: "trash.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("导出与分享")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.shareRequest) { request in
            FireActivityShareSheet(
                activityItems: [request.url],
                subject: request.title
            )
        }
    }

    // MARK: - Support Bundle Metadata

    @ViewBuilder
    private var supportBundleMetadata: some View {
        if let export = viewModel.latestSupportBundle {
            VStack(alignment: .leading, spacing: 4) {
                Text("最近导出：\(FireDiagnosticsPresentation.timestamp(export.createdAtUnixMs)) · \(FireDiagnosticsPresentation.byteSize(export.sizeBytes))")
                    .font(.caption.weight(.medium))
                Text(export.fileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Text(export.relativePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            Text("输出单个 JSON 文件，不会触发额外的目录打包。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Full APM Support Bundle Metadata

    @ViewBuilder
    private var fullAPMSupportBundleMetadata: some View {
        if viewModel.isExportingFullAPMSupportBundle {
            Text("正在汇总采集目录并生成 ZIP，完成后会直接拉起系统分享。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let export = viewModel.latestFullAPMSupportBundle {
            VStack(alignment: .leading, spacing: 4) {
                Text("ZIP 已就绪：\(FireDiagnosticsPresentation.timestamp(export.createdAtUnixMs)) · \(FireDiagnosticsPresentation.byteSize(export.sizeBytes))")
                    .font(.caption.weight(.medium))
                Text(export.fileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Text(export.absoluteURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            Text("导出时会先临时组包，再写入单个 ZIP 文件；中间目录不会长期留在本地。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Export Format Badge

    private func exportFormatBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    // MARK: - Export Action Tile

    private func exportActionTile<Metadata: View>(
        title: String,
        subtitle: String,
        formatLabel: String,
        accent: Color,
        primaryProminent: Bool,
        isBusy: Bool,
        primaryTitle: String,
        primarySystemImage: String,
        onPrimaryTap: @escaping () -> Void,
        secondaryTitle: String?,
        onSecondaryTap: @escaping () -> Void = {},
        @ViewBuilder metadata: () -> Metadata
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                exportFormatBadge(formatLabel, color: accent)
            }

            HStack(spacing: 10) {
                if primaryProminent {
                    Button(action: onPrimaryTap) {
                        Label(primaryTitle, systemImage: primarySystemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                } else {
                    Button(action: onPrimaryTap) {
                        Label(primaryTitle, systemImage: primarySystemImage)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }

                if let secondaryTitle {
                    Button(action: onSecondaryTap) {
                        Label(secondaryTitle, systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            metadata()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Scene Phase Helper

    private func scenePhaseLabel(_ phase: ScenePhase) -> String {
        switch phase {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }
}
