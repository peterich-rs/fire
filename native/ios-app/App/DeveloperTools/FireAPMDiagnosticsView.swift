import SwiftUI

struct FireAPMDiagnosticsView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    FireDiagnosticsMiniStat(
                        value: viewModel.apmSummary.currentSample?.cpuPercent.map {
                            String(format: "%.1f%%", $0)
                        } ?? "N/A",
                        label: "CPU",
                        color: .primary
                    )
                    FireDiagnosticsMiniStat(
                        value: viewModel.apmSummary.currentSample?.physicalFootprintBytes.map {
                            FireDiagnosticsPresentation.byteSize($0)
                        } ?? "N/A",
                        label: "Footprint",
                        color: .secondary
                    )
                    NavigationLink {
                        FireAPMEventListView(
                            title: "Crash",
                            events: viewModel.apmSummary.recentCrashes,
                            emptyMessage: "暂无 Crash 事件。"
                        )
                    } label: {
                        FireDiagnosticsMiniStat(
                            value: "\(viewModel.apmSummary.recentCrashes.count)",
                            label: "Crash",
                            color: viewModel.apmSummary.recentCrashes.isEmpty ? .secondary : .red
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FireAPMEventListView(
                            title: "卡顿",
                            events: viewModel.apmSummary.recentStalls,
                            emptyMessage: "暂无卡顿事件。"
                        )
                    } label: {
                        FireDiagnosticsMiniStat(
                            value: "\(viewModel.apmSummary.recentStalls.count)",
                            label: "卡顿",
                            color: viewModel.apmSummary.recentStalls.isEmpty ? .secondary : .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("最近事件") {
                if !viewModel.apmSummary.recentEvents.isEmpty {
                    ForEach(viewModel.apmSummary.recentEvents) { event in
                        NavigationLink {
                            FireAPMEventDetailView(event: event)
                        } label: {
                            FireAPMEventRow(event: event)
                        }
                    }
                } else {
                    Text("暂无 APM 事件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("APM")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startAPMAutoRefresh(source: .apmDetail)
        }
        .onDisappear {
            viewModel.stopAPMAutoRefresh(source: .apmDetail)
        }
    }
}

private struct FireAPMEventListView: View {
    let title: String
    let events: [FireAPMRecentEvent]
    let emptyMessage: String

    var body: some View {
        List {
            Section {
                if events.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        NavigationLink {
                            FireAPMEventDetailView(event: event)
                        } label: {
                            FireAPMEventRow(event: event)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FireAPMEventRow: View {
    let event: FireAPMRecentEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.caption.weight(.semibold))
            if let subtitle = event.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(FireDiagnosticsPresentation.timestamp(event.timestampUnixMs))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

private struct FireAPMEventDetailView: View {
    let event: FireAPMRecentEvent

    private var payloadItems: [(key: String, value: String)] {
        event.payloadSummary
            .map { ($0.key, $0.value) }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            Section("事件") {
                FireAPMDetailRow(label: "类型", value: event.type.rawValue)
                FireAPMDetailRow(
                    label: "时间",
                    value: FireDiagnosticsPresentation.timestamp(event.timestampUnixMs)
                )
                FireAPMDetailRow(label: "Route", value: event.route ?? "unknown")
                FireAPMDetailRow(label: "Scene", value: event.scenePhase ?? "unknown")
                FireAPMDetailRow(label: "Privacy", value: event.privacyTier.rawValue)
                FireAPMDetailRow(label: "Launch", value: event.launchID ?? "unknown")
                FireAPMDetailRow(label: "Session", value: event.diagnosticSessionID ?? "unknown")
            }

            if !payloadItems.isEmpty {
                Section("Payload") {
                    ForEach(payloadItems, id: \.key) { item in
                        FireAPMDetailRow(label: item.key, value: item.value)
                    }
                }
            }

            if let payloadPath = event.payloadPath {
                Section("附件") {
                    FireAPMDetailRow(label: "路径", value: payloadPath)
                    Text("原始 crash 或 MetricKit payload 会随完整 APM 导出一起保存。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("构建") {
                FireAPMDetailRow(label: "App", value: event.appVersion)
                FireAPMDetailRow(label: "Build", value: event.buildNumber)
                FireAPMDetailRow(label: "Git", value: event.gitSha)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FireAPMDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
