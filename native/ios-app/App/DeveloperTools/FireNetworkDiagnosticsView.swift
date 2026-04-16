import SwiftUI

// MARK: - Network Traces List

struct FireNetworkTracesListView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel

    var body: some View {
        List {
            if viewModel.requestTraces.isEmpty {
                ContentUnavailableView(
                    "暂无请求记录",
                    systemImage: "network.slash",
                    description: Text("尚未捕获到任何网络请求。")
                )
            } else {
                ForEach(viewModel.requestTraces, id: \.id) { trace in
                    NavigationLink {
                        FireRequestTraceDetailView(viewModel: viewModel, traceID: trace.id)
                    } label: {
                        FireRequestTraceRow(trace: trace)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("网络请求")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Request Trace Row (compact, Postman-like)

struct FireRequestTraceRow: View {
    let trace: NetworkTraceSummaryState

    private var statusColor: Color {
        if trace.outcome == .failed { return .red }
        if trace.outcome == .cancelled { return .secondary }
        guard let code = trace.statusCode else { return .secondary }
        if code < 300 { return .green }
        if code < 400 { return .orange }
        return .red
    }

    private var errorColor: Color {
        trace.outcome == .cancelled ? .secondary : .red
    }

    private var methodColor: Color {
        switch trace.method.uppercased() {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(trace.method)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(methodColor)
                    .frame(width: 46, alignment: .leading)

                if let statusCode = trace.statusCode {
                    Text("\(statusCode)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(statusColor)
                }

                Spacer()

                if let durationMs = trace.durationMs {
                    Text("\(durationMs)ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                outcomeIcon
            }

            Text(FireDiagnosticsPresentation.compactURL(trace.url))
                .font(.subheadline.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)

            if let errorMessage = trace.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(errorColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var outcomeIcon: some View {
        Group {
            switch trace.outcome {
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            case .inProgress:
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .font(.caption)
    }
}
