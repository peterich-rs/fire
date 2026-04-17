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
                    FireDiagnosticsMiniStat(
                        value: "\(viewModel.apmSummary.recentCrashes.count)",
                        label: "Crash",
                        color: viewModel.apmSummary.recentCrashes.isEmpty ? .secondary : .red
                    )
                    FireDiagnosticsMiniStat(
                        value: "\(viewModel.apmSummary.recentStalls.count)",
                        label: "卡顿",
                        color: viewModel.apmSummary.recentStalls.isEmpty ? .secondary : .orange
                    )
                }
            }

            Section("最近事件") {
                if !viewModel.apmSummary.recentEvents.isEmpty {
                    ForEach(viewModel.apmSummary.recentEvents) { event in
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
    }
}
