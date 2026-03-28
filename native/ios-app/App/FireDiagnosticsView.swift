import Foundation
import SwiftUI

@MainActor
final class FireDiagnosticsViewModel: ObservableObject {
    @Published private(set) var logFiles: [LogFileSummaryState] = []
    @Published private(set) var logFileDetails: [String: LogFileDetailState] = [:]
    @Published private(set) var requestTraces: [NetworkTraceSummaryState] = []
    @Published private(set) var requestTraceDetails: [UInt64: NetworkTraceDetailState] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func refresh() {
        guard !isLoading else {
            return
        }

        isLoading = true
        Task {
            defer { isLoading = false }

            do {
                errorMessage = nil
                async let files = appViewModel.listLogFiles()
                async let traces = appViewModel.listNetworkTraces(limit: 200)
                logFiles = try await files
                requestTraces = try await traces
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadLogFile(relativePath: String) {
        guard logFileDetails[relativePath] == nil else {
            return
        }

        Task {
            do {
                errorMessage = nil
                logFileDetails[relativePath] = try await appViewModel.readLogFile(relativePath: relativePath)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func logFile(relativePath: String) -> LogFileDetailState? {
        logFileDetails[relativePath]
    }

    func loadTraceDetail(traceID: UInt64) {
        guard requestTraceDetails[traceID] == nil else {
            return
        }

        Task {
            do {
                errorMessage = nil
                requestTraceDetails[traceID] = try await appViewModel.networkTraceDetail(traceID: traceID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func requestTraceDetail(traceID: UInt64) -> NetworkTraceDetailState? {
        requestTraceDetails[traceID]
    }
}

struct FireDiagnosticsView: View {
    @StateObject private var diagnosticsViewModel: FireDiagnosticsViewModel

    init(viewModel: FireAppViewModel) {
        _diagnosticsViewModel = StateObject(
            wrappedValue: FireDiagnosticsViewModel(appViewModel: viewModel)
        )
    }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Captured Requests", value: "\(diagnosticsViewModel.requestTraces.count)")
                LabeledContent("Log Files", value: "\(diagnosticsViewModel.logFiles.count)")
            }

            Section("Log Files") {
                if diagnosticsViewModel.isLoading && diagnosticsViewModel.logFiles.isEmpty {
                    ProgressView("Loading logs...")
                } else if diagnosticsViewModel.logFiles.isEmpty {
                    Text("No log files are available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diagnosticsViewModel.logFiles, id: \.relativePath) { file in
                        NavigationLink {
                            FireDiagnosticsLogView(
                                viewModel: diagnosticsViewModel,
                                relativePath: file.relativePath
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(file.fileName)
                                    .font(.headline)
                                HStack(spacing: 12) {
                                    Text(FireDiagnosticsPresentation.byteSize(file.sizeBytes))
                                    Text(FireDiagnosticsPresentation.timestamp(file.modifiedAtUnixMs))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Text(file.relativePath)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Section("Network Requests") {
                if diagnosticsViewModel.isLoading && diagnosticsViewModel.requestTraces.isEmpty {
                    ProgressView("Loading request traces...")
                } else if diagnosticsViewModel.requestTraces.isEmpty {
                    Text("No captured network requests yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diagnosticsViewModel.requestTraces, id: \.id) { trace in
                        NavigationLink {
                            FireRequestTraceDetailView(
                                viewModel: diagnosticsViewModel,
                                traceID: trace.id
                            )
                        } label: {
                            FireRequestTraceRow(trace: trace)
                        }
                    }
                }
            }

            if let errorMessage = diagnosticsViewModel.errorMessage {
                Section("Diagnostics Error") {
                    Text(errorMessage)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .task {
            diagnosticsViewModel.refresh()
        }
        .refreshable {
            diagnosticsViewModel.refresh()
        }
    }
}

private struct FireDiagnosticsLogView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    let relativePath: String

    var body: some View {
        Group {
            if let logFile = viewModel.logFile(relativePath: relativePath) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(logFile.fileName)
                                .font(.headline)
                            Text(logFile.relativePath)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                            Text(
                                logFile.isTruncated
                                    ? "Showing a truncated preview of \(FireDiagnosticsPresentation.byteSize(logFile.sizeBytes))."
                                    : "Showing \(FireDiagnosticsPresentation.byteSize(logFile.sizeBytes))."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        Text(logFile.contents.isEmpty ? "No log lines captured yet." : logFile.contents)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
            } else {
                ProgressView("Loading log...")
                    .task {
                        viewModel.loadLogFile(relativePath: relativePath)
                    }
            }
        }
        .navigationTitle("Log File")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FireRequestTraceRow: View {
    let trace: NetworkTraceSummaryState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(trace.method)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(trace.operation)
                    .font(.subheadline)
                Text(FireDiagnosticsPresentation.compactURL(trace.url))
                    .font(.headline)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                Text(FireDiagnosticsPresentation.outcome(trace))
                if let statusCode = trace.statusCode {
                    Text("HTTP \(statusCode)")
                }
                if let durationMs = trace.durationMs {
                    Text("\(durationMs) ms")
                }
                Text(FireDiagnosticsPresentation.timestamp(trace.startedAtUnixMs))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let errorMessage = trace.errorMessage {
                Text(errorMessage)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FireRequestTraceDetailView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    let traceID: UInt64

    var body: some View {
        Group {
            if let detail = viewModel.requestTraceDetail(traceID: traceID) {
                List {
                    Section("Overview") {
                        LabeledContent("Operation", value: detail.summary.operation)
                        LabeledContent("Method", value: detail.summary.method)
                        LabeledContent("URL", value: detail.summary.url)
                        LabeledContent(
                            "Started",
                            value: FireDiagnosticsPresentation.timestamp(detail.summary.startedAtUnixMs)
                        )
                        if let finishedAtUnixMs = detail.summary.finishedAtUnixMs {
                            LabeledContent(
                                "Finished",
                                value: FireDiagnosticsPresentation.timestamp(finishedAtUnixMs)
                            )
                        }
                        if let durationMs = detail.summary.durationMs {
                            LabeledContent("Duration", value: "\(durationMs) ms")
                        }
                        LabeledContent("Outcome", value: FireDiagnosticsPresentation.outcome(detail.summary))
                        if let statusCode = detail.summary.statusCode {
                            LabeledContent("Status", value: "HTTP \(statusCode)")
                        }
                        if let responseBodyBytes = detail.responseBodyBytes {
                            LabeledContent("Body Size", value: FireDiagnosticsPresentation.byteSize(responseBodyBytes))
                        }
                        if let callID = detail.summary.callId {
                            LabeledContent("Call ID", value: "\(callID)")
                        }
                        if let errorMessage = detail.summary.errorMessage {
                            LabeledContent("Error", value: errorMessage)
                                .foregroundStyle(.red)
                        }
                    }

                    Section("Request Headers") {
                        FireHeaderList(headers: detail.requestHeaders)
                    }

                    Section("Response Headers") {
                        FireHeaderList(headers: detail.responseHeaders)
                    }

                    Section("Response Body") {
                        if let responseBody = detail.responseBody, !responseBody.isEmpty {
                            if detail.responseBodyTruncated {
                                Text("Response body is truncated to the first 256 KB.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text(responseBody)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        } else {
                            Text("No response body captured.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Execution Chain") {
                        ForEach(Array(detail.events.enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.phase)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(event.summary)
                                    .font(.body)
                                if let details = event.details, !details.isEmpty {
                                    Text(details)
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Text(FireDiagnosticsPresentation.timestamp(event.timestampUnixMs))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else {
                ProgressView("Loading request trace...")
                    .task {
                        viewModel.loadTraceDetail(traceID: traceID)
                    }
            }
        }
        .navigationTitle("Request Trace")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FireHeaderList: View {
    let headers: [NetworkTraceHeaderState]

    var body: some View {
        if headers.isEmpty {
            Text("No headers captured.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                VStack(alignment: .leading, spacing: 4) {
                    Text(header.name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(header.value)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private enum FireDiagnosticsPresentation {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static func timestamp(_ unixMilliseconds: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixMilliseconds) / 1000)
        return timestampFormatter.string(from: date)
    }

    static func byteSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func compactURL(_ rawValue: String) -> String {
        guard let url = URL(string: rawValue) else {
            return rawValue
        }

        let path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    static func outcome(_ trace: NetworkTraceSummaryState) -> String {
        switch trace.outcome {
        case .inProgress:
            return "In Progress"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        }
    }
}
