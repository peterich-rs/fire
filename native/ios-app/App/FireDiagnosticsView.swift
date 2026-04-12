import Foundation
import SwiftUI
import UIKit

struct FireDiagnosticsTextWindow: Equatable {
    let text: String
    let startOffset: UInt64
    let endOffset: UInt64
    let totalBytes: UInt64
    let hasMoreOlder: Bool
    let hasMoreNewer: Bool
    let isHeadAligned: Bool
    let isTailAligned: Bool

    init(page: DiagnosticsTextPageState) {
        self.text = page.text
        self.startOffset = page.startOffset
        self.endOffset = page.endOffset
        self.totalBytes = page.totalBytes
        self.hasMoreOlder = page.hasMoreOlder
        self.hasMoreNewer = page.hasMoreNewer
        self.isHeadAligned = page.isHeadAligned
        self.isTailAligned = page.isTailAligned
    }

    init(
        text: String,
        startOffset: UInt64,
        endOffset: UInt64,
        totalBytes: UInt64,
        hasMoreOlder: Bool,
        hasMoreNewer: Bool,
        isHeadAligned: Bool,
        isTailAligned: Bool
    ) {
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.totalBytes = totalBytes
        self.hasMoreOlder = hasMoreOlder
        self.hasMoreNewer = hasMoreNewer
        self.isHeadAligned = isHeadAligned
        self.isTailAligned = isTailAligned
    }
}

struct FireDiagnosticsPagedTextDocument: Equatable {
    let newestFirst: Bool
    private(set) var windows: [FireDiagnosticsTextWindow]

    init(newestFirst: Bool, windows: [FireDiagnosticsTextWindow]) {
        self.newestFirst = newestFirst
        self.windows = windows.sorted { $0.startOffset < $1.startOffset }
    }

    var totalBytes: UInt64 {
        windows.last?.totalBytes ?? 0
    }

    var olderCursor: UInt64? {
        guard let first = windows.first, first.hasMoreOlder else {
            return nil
        }
        return first.startOffset
    }

    var newerCursor: UInt64? {
        guard let last = windows.last, last.hasMoreNewer else {
            return nil
        }
        return last.endOffset
    }

    var hasLoadedAdditionalPages: Bool {
        windows.count > 1 || !(windows.first?.isHeadAligned ?? true)
    }

    var hasMultipleWindows: Bool {
        windows.count > 1
    }

    var loadedBytes: UInt64 {
        guard let first = windows.first, let last = windows.last else {
            return 0
        }
        return last.endOffset >= first.startOffset
            ? last.endOffset - first.startOffset
            : 0
    }

    var renderedText: String {
        let combined = windows
            .sorted { $0.startOffset < $1.startOffset }
            .map(\.text)
            .joined()
        guard newestFirst else {
            return combined
        }

        var lines = combined.components(separatedBy: .newlines)
        if lines.last == "" {
            lines.removeLast()
        }
        return lines.reversed().joined(separator: "\n")
    }

    var renderedLines: [String] {
        var lines = renderedText.components(separatedBy: .newlines)
        if lines.last == "" {
            lines.removeLast()
        }
        return lines.isEmpty ? [""] : lines
    }

    var identifiedRenderedLines: [FireIdentifiedValue<String>] {
        fireIdentifiedValues(renderedLines) { line in
            line.isEmpty ? "<empty-line>" : line
        }
    }

    mutating func replace(with window: FireDiagnosticsTextWindow) {
        windows = [window]
    }

    mutating func merge(with window: FireDiagnosticsTextWindow) {
        guard !windows.contains(where: { $0.startOffset == window.startOffset && $0.endOffset == window.endOffset }) else {
            return
        }
        windows.append(window)
        windows.sort { $0.startOffset < $1.startOffset }
    }
}

@MainActor
final class FireDiagnosticsViewModel: ObservableObject {
    private static let traceAutoRefreshInterval: Duration = .seconds(1)
    private static let logPageBytes: UInt64 = 128 * 1024
    private static let traceBodyPageBytes: UInt64 = 32 * 1024

    @Published private(set) var diagnosticSessionID: String?
    @Published private(set) var logFiles: [LogFileSummaryState] = []
    @Published private(set) var logDocuments: [String: FireDiagnosticsPagedTextDocument] = [:]
    @Published private(set) var requestTraces: [NetworkTraceSummaryState] = []
    @Published private(set) var requestTraceDetails: [UInt64: NetworkTraceDetailState] = [:]
    @Published private(set) var traceBodyDocuments: [UInt64: FireDiagnosticsPagedTextDocument] = [:]
    @Published private(set) var apmSummary: FireAPMDiagnosticsSummary = .empty
    @Published private(set) var latestSupportBundle: SupportBundleExportState?
    @Published private(set) var latestFullAPMSupportBundle: FireAPMSupportBundleExport?
    @Published private(set) var isExportingSupportBundle = false
    @Published private(set) var isExportingFullAPMSupportBundle = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel
    private var traceAutoRefreshTask: Task<Void, Never>?
    private var isRefreshingTraces = false
    private var loadingLogPagePaths: Set<String> = []
    private var loadingTraceDetailIDs: Set<UInt64> = []
    private var loadingTraceBodyPageIDs: Set<UInt64> = []

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    deinit {
        traceAutoRefreshTask?.cancel()
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
                async let diagnosticSessionID = appViewModel.diagnosticSessionID()
                async let files = appViewModel.listLogFiles()
                async let traces = appViewModel.listNetworkTraces(limit: 200)
                async let apmSummary = appViewModel.apmDiagnosticsSummary()
                let latestTraces = try await traces
                self.diagnosticSessionID = try await diagnosticSessionID
                logFiles = try await files
                self.apmSummary = try await apmSummary
                applyTraceSummaries(latestTraces)
                await refreshCachedTraceDetails(using: latestTraces)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func startTraceAutoRefresh() {
        guard traceAutoRefreshTask == nil else {
            return
        }

        traceAutoRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshTracesIfNeeded()
                try? await Task.sleep(for: Self.traceAutoRefreshInterval)
            }
        }
    }

    func stopTraceAutoRefresh() {
        traceAutoRefreshTask?.cancel()
        traceAutoRefreshTask = nil
    }

    func loadLogFile(relativePath: String) {
        if logDocuments[relativePath] != nil {
            return
        }
        loadLogFile(relativePath: relativePath, force: false)
    }

    func loadLogFile(relativePath: String, force: Bool) {
        guard !loadingLogPagePaths.contains(relativePath) else {
            return
        }
        Task {
            if force {
                logDocuments.removeValue(forKey: relativePath)
            }
            loadingLogPagePaths.insert(relativePath)
            defer { loadingLogPagePaths.remove(relativePath) }
            do {
                errorMessage = nil
                let page = try await appViewModel.readLogFilePage(
                    relativePath: relativePath,
                    cursor: nil,
                    maxBytes: Self.logPageBytes,
                    direction: .older
                )
                logDocuments[relativePath] = FireDiagnosticsPagedTextDocument(
                    newestFirst: true,
                    windows: [FireDiagnosticsTextWindow(page: page.page)]
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func resetLogFile(relativePath: String) {
        loadLogFile(relativePath: relativePath, force: true)
    }

    func loadOlderLogPage(relativePath: String) {
        guard let cursor = logDocuments[relativePath]?.olderCursor else {
            return
        }
        guard !loadingLogPagePaths.contains(relativePath) else {
            return
        }

        Task {
            loadingLogPagePaths.insert(relativePath)
            defer { loadingLogPagePaths.remove(relativePath) }
            do {
                errorMessage = nil
                let page = try await appViewModel.readLogFilePage(
                    relativePath: relativePath,
                    cursor: cursor,
                    maxBytes: Self.logPageBytes,
                    direction: .older
                )
                var document = logDocuments[relativePath]
                    ?? FireDiagnosticsPagedTextDocument(newestFirst: true, windows: [])
                document.merge(with: FireDiagnosticsTextWindow(page: page.page))
                logDocuments[relativePath] = document
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func isLoadingLogPage(relativePath: String) -> Bool {
        loadingLogPagePaths.contains(relativePath)
    }

    func logDocument(relativePath: String) -> FireDiagnosticsPagedTextDocument? {
        logDocuments[relativePath]
    }

    func loadTraceDetail(traceID: UInt64, force: Bool = false) {
        if !force, requestTraceDetails[traceID] != nil {
            return
        }
        guard !loadingTraceDetailIDs.contains(traceID) else {
            return
        }

        Task {
            loadingTraceDetailIDs.insert(traceID)
            defer { loadingTraceDetailIDs.remove(traceID) }
            do {
                errorMessage = nil
                let detail = try await appViewModel.networkTraceDetail(traceID: traceID)
                requestTraceDetails[traceID] = detail
                seedTraceBodyDocumentIfNeeded(
                    from: detail,
                    replaceInlinePreview: force && !(traceBodyDocuments[traceID]?.hasLoadedAdditionalPages ?? false)
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func requestTraceDetail(traceID: UInt64) -> NetworkTraceDetailState? {
        requestTraceDetails[traceID]
    }

    func traceBodyDocument(traceID: UInt64) -> FireDiagnosticsPagedTextDocument? {
        traceBodyDocuments[traceID]
    }

    func isLoadingTraceBodyPage(traceID: UInt64) -> Bool {
        loadingTraceBodyPageIDs.contains(traceID)
    }

    func loadNewerTraceBodyPage(traceID: UInt64) {
        guard let cursor = traceBodyDocuments[traceID]?.newerCursor else {
            return
        }
        loadTraceBodyPage(
            traceID: traceID,
            cursor: cursor,
            direction: .newer,
            replaceExisting: false
        )
    }

    func loadOlderTraceBodyPage(traceID: UInt64) {
        guard let cursor = traceBodyDocuments[traceID]?.olderCursor else {
            return
        }
        loadTraceBodyPage(
            traceID: traceID,
            cursor: cursor,
            direction: .older,
            replaceExisting: false
        )
    }

    func showTraceBodyTail(traceID: UInt64) {
        loadTraceBodyPage(
            traceID: traceID,
            cursor: nil,
            direction: .older,
            replaceExisting: true
        )
    }

    func resetTraceBodyPreview(traceID: UInt64) {
        guard let detail = requestTraceDetails[traceID] else {
            loadTraceDetail(traceID: traceID, force: true)
            return
        }
        seedTraceBodyDocumentIfNeeded(from: detail, replaceInlinePreview: true)
    }

    func exportSupportBundle(scenePhase: String) {
        guard !isExportingSupportBundle else {
            return
        }

        Task {
            isExportingSupportBundle = true
            defer { isExportingSupportBundle = false }
            do {
                errorMessage = nil
                latestSupportBundle = try await appViewModel.exportSupportBundle(scenePhase: scenePhase)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func supportBundleURL() -> URL? {
        latestSupportBundle.map { URL(fileURLWithPath: $0.absolutePath) }
    }

    func exportFullAPMSupportBundle(scenePhase: String) {
        guard !isExportingFullAPMSupportBundle else {
            return
        }

        Task {
            isExportingFullAPMSupportBundle = true
            defer { isExportingFullAPMSupportBundle = false }
            do {
                errorMessage = nil
                latestFullAPMSupportBundle = try await appViewModel.exportFullAPMSupportBundle(
                    scenePhase: scenePhase
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func fullAPMSupportBundleURL() -> URL? {
        latestFullAPMSupportBundle?.absoluteURL
    }

    private func loadTraceBodyPage(
        traceID: UInt64,
        cursor: UInt64?,
        direction: DiagnosticsPageDirectionState,
        replaceExisting: Bool
    ) {
        guard !loadingTraceBodyPageIDs.contains(traceID) else {
            return
        }

        Task {
            loadingTraceBodyPageIDs.insert(traceID)
            defer { loadingTraceBodyPageIDs.remove(traceID) }
            do {
                errorMessage = nil
                guard let page = try await appViewModel.networkTraceBodyPage(
                    traceID: traceID,
                    cursor: cursor,
                    maxBytes: Self.traceBodyPageBytes,
                    direction: direction
                ) else {
                    return
                }

                let window = FireDiagnosticsTextWindow(page: page.page)
                var document = traceBodyDocuments[traceID]
                    ?? FireDiagnosticsPagedTextDocument(newestFirst: false, windows: [])
                if replaceExisting {
                    document.replace(with: window)
                } else {
                    document.merge(with: window)
                }
                traceBodyDocuments[traceID] = document
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func seedTraceBodyDocumentIfNeeded(
        from detail: NetworkTraceDetailState,
        replaceInlinePreview: Bool
    ) {
        guard let responseBody = detail.responseBody, !responseBody.isEmpty else {
            if replaceInlinePreview {
                traceBodyDocuments.removeValue(forKey: detail.summary.id)
            }
            return
        }

        if traceBodyDocuments[detail.summary.id] != nil, !replaceInlinePreview {
            return
        }

        let inlineBytes = UInt64(responseBody.lengthOfBytes(using: .utf8))
        let totalBytes = detail.responseBodyStoredBytes ?? inlineBytes
        traceBodyDocuments[detail.summary.id] = FireDiagnosticsPagedTextDocument(
            newestFirst: false,
            windows: [
                FireDiagnosticsTextWindow(
                    text: responseBody,
                    startOffset: 0,
                    endOffset: inlineBytes,
                    totalBytes: totalBytes,
                    hasMoreOlder: false,
                    hasMoreNewer: detail.responseBodyPageAvailable,
                    isHeadAligned: true,
                    isTailAligned: !detail.responseBodyPageAvailable
                )
            ]
        )
    }

    // MARK: - Computed Stats

    var succeededCount: Int {
        requestTraces.filter { $0.outcome == .succeeded }.count
    }

    var failedCount: Int {
        requestTraces.filter { $0.outcome == .failed }.count
    }

    var inProgressCount: Int {
        requestTraces.filter { $0.outcome == .inProgress }.count
    }

    var averageDurationMs: UInt64? {
        let durations = requestTraces.compactMap(\.durationMs)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / UInt64(durations.count)
    }

    var totalLogSizeBytes: UInt64 {
        logFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    private func refreshTracesIfNeeded() async {
        guard !isRefreshingTraces, !isLoading else {
            return
        }

        isRefreshingTraces = true
        defer { isRefreshingTraces = false }

        do {
            let traces = try await appViewModel.listNetworkTraces(limit: 200)
            errorMessage = nil
            applyTraceSummaries(traces)
            await refreshCachedTraceDetails(using: traces)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyTraceSummaries(_ traces: [NetworkTraceSummaryState]) {
        requestTraces = traces
    }

    private func refreshCachedTraceDetails(using traces: [NetworkTraceSummaryState]) async {
        guard !requestTraceDetails.isEmpty else {
            return
        }

        let latestByID = Dictionary(uniqueKeysWithValues: traces.map { ($0.id, $0) })
        let traceIDsToRefresh: [UInt64] = requestTraceDetails.compactMap { entry in
            let (traceID, detail) = entry
            guard let latest = latestByID[traceID] else {
                return nil
            }
            return traceDetailNeedsRefresh(cached: detail.summary, latest: latest) ? traceID : nil
        }

        guard !traceIDsToRefresh.isEmpty else {
            return
        }

        for traceID in traceIDsToRefresh {
            guard !Task.isCancelled else {
                return
            }
            loadTraceDetail(traceID: traceID, force: true)
        }
    }

    private func traceDetailNeedsRefresh(
        cached: NetworkTraceSummaryState,
        latest: NetworkTraceSummaryState
    ) -> Bool {
        cached.outcome == .inProgress
            || cached.outcome != latest.outcome
            || cached.finishedAtUnixMs != latest.finishedAtUnixMs
            || cached.durationMs != latest.durationMs
            || cached.statusCode != latest.statusCode
            || cached.responseContentType != latest.responseContentType
    }
}

// MARK: - Dashboard (Entry Point)

struct FireDiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var diagnosticsViewModel: FireDiagnosticsViewModel
    @StateObject private var pushRegistrationCoordinator = FirePushRegistrationCoordinator.shared

    init(viewModel: FireAppViewModel) {
        _diagnosticsViewModel = StateObject(
            wrappedValue: FireDiagnosticsViewModel(appViewModel: viewModel)
        )
    }

    var body: some View {
        List {
            if let errorMessage = diagnosticsViewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                NavigationLink {
                    FireNetworkTracesListView(viewModel: diagnosticsViewModel)
                } label: {
                    networkCard
                }

                NavigationLink {
                    FireLogFilesListView(viewModel: diagnosticsViewModel)
                } label: {
                    logCard
                }

                apmCard
                pushCard
                supportBundleCard
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
        .navigationTitle("诊断工具")
        .onAppear {
            diagnosticsViewModel.startTraceAutoRefresh()
            Task {
                await pushRegistrationCoordinator.refreshAuthorizationStatus()
            }
        }
        .onDisappear {
            diagnosticsViewModel.stopTraceAutoRefresh()
        }
        .task {
            diagnosticsViewModel.refresh()
            await pushRegistrationCoordinator.refreshAuthorizationStatus()
        }
        .refreshable {
            diagnosticsViewModel.refresh()
            await pushRegistrationCoordinator.refreshAuthorizationStatus()
        }
    }

    // MARK: - Network Summary Card

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("网络请求", systemImage: "network")
                .font(.headline)

            if diagnosticsViewModel.isLoading && diagnosticsViewModel.requestTraces.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 0) {
                    miniStat(
                        value: "\(diagnosticsViewModel.requestTraces.count)",
                        label: "总计",
                        color: .primary
                    )
                    miniStat(
                        value: "\(diagnosticsViewModel.succeededCount)",
                        label: "成功",
                        color: .green
                    )
                    miniStat(
                        value: "\(diagnosticsViewModel.failedCount)",
                        label: "失败",
                        color: diagnosticsViewModel.failedCount > 0 ? .red : .secondary
                    )
                    if let avgMs = diagnosticsViewModel.averageDurationMs {
                        miniStat(
                            value: "\(avgMs)ms",
                            label: "平均耗时",
                            color: .secondary
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Log Summary Card

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("日志文件", systemImage: "doc.text")
                .font(.headline)

            if diagnosticsViewModel.isLoading && diagnosticsViewModel.logFiles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 0) {
                    miniStat(
                        value: "\(diagnosticsViewModel.logFiles.count)",
                        label: "文件数",
                        color: .primary
                    )
                    miniStat(
                        value: FireDiagnosticsPresentation.byteSize(diagnosticsViewModel.totalLogSizeBytes),
                        label: "总计大小",
                        color: .secondary
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var supportBundleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("诊断包", systemImage: "square.and.arrow.up")
                .font(.headline)

            Text("导出 Rust 诊断包，或附带本地 crash / MetricKit / route / span 工件的完整 APM 包，便于留档或分享排障。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let diagnosticSessionID = diagnosticsViewModel.diagnosticSessionID {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session ID")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(diagnosticSessionID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                Button {
                    diagnosticsViewModel.exportSupportBundle(
                        scenePhase: scenePhaseLabel(scenePhase)
                    )
                } label: {
                    Label(
                        diagnosticsViewModel.isExportingSupportBundle ? "导出中…" : "导出诊断包",
                        systemImage: "tray.and.arrow.down"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(diagnosticsViewModel.isExportingSupportBundle)

                if let bundleURL = diagnosticsViewModel.supportBundleURL() {
                    ShareLink(item: bundleURL) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                if diagnosticsViewModel.isExportingSupportBundle {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Button {
                    diagnosticsViewModel.exportFullAPMSupportBundle(
                        scenePhase: scenePhaseLabel(scenePhase)
                    )
                } label: {
                    Label(
                        diagnosticsViewModel.isExportingFullAPMSupportBundle ? "导出中…" : "导出完整 APM 包",
                        systemImage: "archivebox"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(diagnosticsViewModel.isExportingFullAPMSupportBundle)

                if let bundleURL = diagnosticsViewModel.fullAPMSupportBundleURL() {
                    ShareLink(item: bundleURL) {
                        Label("分享 APM 包", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                if diagnosticsViewModel.isExportingFullAPMSupportBundle {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let export = diagnosticsViewModel.latestSupportBundle {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(export.fileName) · \(FireDiagnosticsPresentation.byteSize(export.sizeBytes))")
                        .font(.caption.monospaced())
                    Text(FireDiagnosticsPresentation.timestamp(export.createdAtUnixMs))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(export.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let export = diagnosticsViewModel.latestFullAPMSupportBundle {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(export.fileName) · \(FireDiagnosticsPresentation.byteSize(export.sizeBytes))")
                        .font(.caption.monospaced())
                    Text(FireDiagnosticsPresentation.timestamp(export.createdAtUnixMs))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(export.absoluteURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var apmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("APM 概览", systemImage: "waveform.path.ecg")
                .font(.headline)

            HStack(spacing: 0) {
                miniStat(
                    value: diagnosticsViewModel.apmSummary.currentSample?.cpuPercent.map {
                        String(format: "%.1f%%", $0)
                    } ?? "N/A",
                    label: "CPU",
                    color: .primary
                )
                miniStat(
                    value: diagnosticsViewModel.apmSummary.currentSample?.physicalFootprintBytes.map {
                        FireDiagnosticsPresentation.byteSize($0)
                    } ?? "N/A",
                    label: "Footprint",
                    color: .secondary
                )
                miniStat(
                    value: "\(diagnosticsViewModel.apmSummary.recentCrashes.count)",
                    label: "Crash",
                    color: diagnosticsViewModel.apmSummary.recentCrashes.isEmpty ? .secondary : .red
                )
                miniStat(
                    value: "\(diagnosticsViewModel.apmSummary.recentStalls.count)",
                    label: "卡顿",
                    color: diagnosticsViewModel.apmSummary.recentStalls.isEmpty ? .secondary : .orange
                )
            }

            if !diagnosticsViewModel.apmSummary.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(diagnosticsViewModel.apmSummary.recentEvents.prefix(4)) { event in
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
            } else {
                Text("暂无 APM 事件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var pushCard: some View {
        let diagnostics = pushRegistrationCoordinator.diagnostics

        return VStack(alignment: .leading, spacing: 12) {
            Label("远程通知注册", systemImage: "bell.badge")
                .font(.headline)

            Text("当前阶段只申请系统通知权限并在本地保存 APNs token；不会把 token 上传到 LinuxDo 后端。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                miniStat(
                    value: diagnostics.authorizationStatusTitle,
                    label: "权限",
                    color: diagnostics.authorizationStatus == .denied ? .red : .primary
                )
                miniStat(
                    value: diagnostics.registrationStateTitle,
                    label: "注册状态",
                    color: diagnostics.registrationState == .failed ? .red : .secondary
                )
            }

            if let deviceToken = diagnostics.deviceTokenHex, !deviceToken.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Token")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(deviceToken)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let errorMessage = diagnostics.lastErrorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await pushRegistrationCoordinator.ensurePushRegistration()
                    }
                } label: {
                    Label(pushActionTitle(for: diagnostics), systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)

                Button("刷新状态") {
                    Task {
                        await pushRegistrationCoordinator.refreshAuthorizationStatus()
                    }
                }
                .buttonStyle(.bordered)
            }

            if diagnostics.authorizationStatus == .denied {
                Text("如需继续验证 APNs 注册，请先在系统设置里重新开启通知权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let updatedAt = diagnostics.lastUpdatedAtUnixMs {
                Text("最近更新：\(FireDiagnosticsPresentation.timestamp(updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

// MARK: - Network Traces List

private struct FireNetworkTracesListView: View {
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

private struct FireRequestTraceRow: View {
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

// MARK: - Request Trace Detail (Tabbed — Postman style)

private struct FireRequestTraceDetailView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    let traceID: UInt64

    @State private var selectedTab: DetailTab = .overview
    @State private var showCopiedToast = false

    enum DetailTab: String, CaseIterable {
        case overview = "概要"
        case request = "Request"
        case response = "Response"
        case timeline = "Timeline"
    }

    private var bodyDocument: FireDiagnosticsPagedTextDocument? {
        viewModel.traceBodyDocument(traceID: traceID)
    }

    var body: some View {
        Group {
            if let detail = viewModel.requestTraceDetail(traceID: traceID) {
                VStack(spacing: 0) {
                    requestSummaryBar(detail: detail)

                    Picker("Tab", selection: $selectedTab) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Divider()

                    ScrollView {
                        switch selectedTab {
                        case .overview:
                            overviewContent(detail: detail)
                        case .request:
                            requestContent(detail: detail)
                        case .response:
                            responseContent(detail: detail)
                        case .timeline:
                            timelineContent(detail: detail)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            copyToClipboard(
                                fullHTTPText(
                                    detail: detail,
                                    bodyText: bodyDocument?.renderedText ?? detail.responseBody
                                )
                            )
                        } label: {
                            Label("复制全部", systemImage: "doc.on.doc")
                        }
                    }
                }
            } else {
                ProgressView("加载请求详情…")
                    .task {
                        viewModel.loadTraceDetail(traceID: traceID)
                    }
            }
        }
        .navigationTitle("请求详情")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("已复制")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(.label).opacity(0.85), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.3), value: showCopiedToast)
    }

    // MARK: - Copy Helper

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        guard !showCopiedToast else { return }
        withAnimation { showCopiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showCopiedToast = false }
        }
    }

    // MARK: - Full Request Copy

    private func fullHTTPText(
        detail: NetworkTraceDetailState,
        bodyText: String?
    ) -> String {
        var lines: [String] = []

        lines.append("\(detail.summary.method) \(detail.summary.url) HTTP/1.1")

        if !detail.requestHeaders.isEmpty {
            for h in detail.requestHeaders {
                lines.append("\(h.name): \(h.value)")
            }
        }

        lines.append("")

        if let statusCode = detail.summary.statusCode {
            lines.append("HTTP/1.1 \(statusCode)")
        }

        if !detail.responseHeaders.isEmpty {
            for h in detail.responseHeaders {
                lines.append("\(h.name): \(h.value)")
            }
        }

        if let bodyText, !bodyText.isEmpty {
            lines.append("")
            lines.append(bodyText)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Summary Bar (always visible at top)

    private func requestSummaryBar(detail: NetworkTraceDetailState) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(detail.summary.method)
                    .font(.subheadline.monospaced().weight(.bold))
                    .foregroundStyle(methodColor(detail.summary.method))

                if let statusCode = detail.summary.statusCode {
                    Text("\(statusCode)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(statusCodeColor(statusCode))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusCodeColor(statusCode).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Spacer()

                if let durationMs = detail.summary.durationMs {
                    Label("\(durationMs)ms", systemImage: "clock")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(detail.summary.url)
                .font(.caption.monospaced())
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Overview Tab

    private func overviewContent(detail: NetworkTraceDetailState) -> some View {
        VStack(spacing: 0) {
            kvRow("Operation", detail.summary.operation)
            kvRow("Method", detail.summary.method)
            kvRow("URL", detail.summary.url, selectable: true)
            kvRow("Started", FireDiagnosticsPresentation.timestamp(detail.summary.startedAtUnixMs))

            if let finishedAtUnixMs = detail.summary.finishedAtUnixMs {
                kvRow("Finished", FireDiagnosticsPresentation.timestamp(finishedAtUnixMs))
            }

            if let durationMs = detail.summary.durationMs {
                kvRow("Duration", "\(durationMs) ms")
            }

            kvRow("Outcome", FireDiagnosticsPresentation.outcome(detail.summary))

            if let statusCode = detail.summary.statusCode {
                kvRow("Status", "HTTP \(statusCode)")
            }

            if let responseBodyBytes = detail.responseBodyBytes {
                kvRow("Body Size", FireDiagnosticsPresentation.byteSize(responseBodyBytes))
            }

            if let storedBytes = detail.responseBodyStoredBytes {
                kvRow("Preview Cache", FireDiagnosticsPresentation.byteSize(storedBytes))
            }

            if let contentType = detail.summary.responseContentType {
                kvRow("Content-Type", contentType)
            }

            if let callID = detail.summary.callId {
                kvRow("Call ID", "\(callID)")
            }

            if let errorMessage = detail.summary.errorMessage {
                kvRow("Error", errorMessage, valueColor: .red)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Request Tab

    private func requestContent(detail: NetworkTraceDetailState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                "Headers (\(detail.requestHeaders.count))",
                copyAction: detail.requestHeaders.isEmpty ? nil : {
                    copyToClipboard(
                        detail.requestHeaders
                            .map { "\($0.name): \($0.value)" }
                            .joined(separator: "\n")
                    )
                }
            )

            if detail.requestHeaders.isEmpty {
                emptyNote("无请求 headers")
            } else {
                headersBlock(detail.requestHeaders)
            }

            // Request body is not captured in the current model,
            // but the section is here for future support.
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Response Tab

    private func responseContent(detail: NetworkTraceDetailState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                "Headers (\(detail.responseHeaders.count))",
                copyAction: detail.responseHeaders.isEmpty ? nil : {
                    copyToClipboard(
                        detail.responseHeaders
                            .map { "\($0.name): \($0.value)" }
                            .joined(separator: "\n")
                    )
                }
            )

            if detail.responseHeaders.isEmpty {
                emptyNote("无响应 headers")
            } else {
                headersBlock(detail.responseHeaders)
            }

            sectionHeader(
                "Body",
                copyAction: {
                    guard let body = bodyDocument?.renderedText ?? detail.responseBody, !body.isEmpty else { return }
                    copyToClipboard(body)
                }
            )

            if let document = bodyDocument {
                VStack(alignment: .leading, spacing: 8) {
                    if detail.responseBodyStorageTruncated {
                        Label("响应 body 仅保留前 256 KB 缓存预览，无法回看原始尾部。", systemImage: "scissors")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if detail.responseBodyPageAvailable {
                        Label("当前仅内联首屏预览，可继续按需加载。", systemImage: "text.append")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if let storedBytes = detail.responseBodyStoredBytes {
                            Text("已加载 \(FireDiagnosticsPresentation.byteSize(document.loadedBytes)) / \(FireDiagnosticsPresentation.byteSize(storedBytes))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if bodyDocument?.hasLoadedAdditionalPages == true {
                            Button("回到首屏") {
                                viewModel.resetTraceBodyPreview(traceID: traceID)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack(spacing: 8) {
                        if document.newerCursor != nil {
                            Button("加载更多") {
                                viewModel.loadNewerTraceBodyPage(traceID: traceID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if detail.responseBodyPageAvailable || detail.responseBodyStorageTruncated {
                            Button(detail.responseBodyStorageTruncated ? "查看缓存尾部" : "查看尾部") {
                                viewModel.showTraceBodyTail(traceID: traceID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if document.olderCursor != nil {
                            Button("向前加载") {
                                viewModel.loadOlderTraceBodyPage(traceID: traceID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if viewModel.isLoadingTraceBodyPage(traceID: traceID) {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    FireDiagnosticsTextView(text: document.renderedText)
                        .frame(minHeight: 220, maxHeight: 360)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } else {
                emptyNote("未捕获到响应 body")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Timeline Tab

    private func timelineContent(detail: NetworkTraceDetailState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if detail.events.isEmpty {
                ContentUnavailableView(
                    "无执行链",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("该请求没有记录执行事件。")
                )
            } else {
                ForEach(
                    fireIdentifiedValues(detail.events) { $0.fireStableBaseID }
                ) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(item.index == 0 ? Color.accentColor : Color(.tertiaryLabel))
                                .frame(width: 8, height: 8)

                            if item.index < detail.events.count - 1 {
                                Rectangle()
                                    .fill(Color(.separator))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 8)
                        .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.value.phase)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(FireDiagnosticsPresentation.timestamp(item.value.timestampUnixMs))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Text(item.value.summary)
                                .font(.subheadline)

                            if let details = item.value.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    if item.index < detail.events.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Reusable Parts

    private func kvRow(_ key: String, _ value: String, selectable: Bool = false, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                if selectable {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(valueColor)
                        .textSelection(.enabled)
                } else {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(valueColor)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    copyToClipboard(value)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }

            Divider()
        }
    }

    private func headersBlock(_ headers: [NetworkTraceHeaderState]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fireIdentifiedValues(headers) { $0.fireStableBaseID }) { item in
                (Text("\(item.value.name): ")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                + Text(item.value.value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary))
                .textSelection(.enabled)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        copyToClipboard("\(item.value.name): \(item.value.value)")
                    } label: {
                        Label("复制 Header", systemImage: "doc.on.doc")
                    }
                    Button {
                        copyToClipboard(item.value.value)
                    } label: {
                        Label("复制值", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        copyToClipboard(item.value.name)
                    } label: {
                        Label("复制名称", systemImage: "character.cursor.ibeam")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sectionHeader(_ title: String, copyAction: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if let copyAction {
                Button(action: copyAction) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 8)
    }

    // MARK: - Color Helpers

    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .secondary
        }
    }

    private func statusCodeColor(_ code: UInt16) -> Color {
        if code < 300 { return .green }
        if code < 400 { return .orange }
        return .red
    }
}

// MARK: - Log Files List

private struct FireLogFilesListView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel

    var body: some View {
        List {
            if viewModel.logFiles.isEmpty {
                ContentUnavailableView(
                    "暂无日志",
                    systemImage: "doc.text",
                    description: Text("尚未生成任何日志文件。")
                )
            } else {
                ForEach(viewModel.logFiles, id: \.relativePath) { file in
                    NavigationLink {
                        FireDiagnosticsLogView(viewModel: viewModel, relativePath: file.relativePath)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.fileName)
                                    .font(.subheadline.weight(.medium))

                                Text(FireDiagnosticsPresentation.timestamp(file.modifiedAtUnixMs))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(FireDiagnosticsPresentation.byteSize(file.sizeBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("日志文件")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Log Detail View

private struct FireDiagnosticsLogView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    let relativePath: String

    private var fileSummary: LogFileSummaryState? {
        viewModel.logFiles.first { $0.relativePath == relativePath }
    }

    var body: some View {
        Group {
            if let document = viewModel.logDocument(relativePath: relativePath) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fileSummary?.fileName ?? relativePath)
                                .font(.headline)

                            if let fileSummary {
                                Text(FireDiagnosticsPresentation.byteSize(fileSummary.sizeBytes))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("最新在上，滚动到底部自动加载更早内容")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if document.hasMultipleWindows {
                            Button("回到最新") {
                                viewModel.resetLogFile(relativePath: relativePath)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if document.renderedLines == [""] {
                        Text("暂无日志内容。")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Text("已加载 \(FireDiagnosticsPresentation.byteSize(document.loadedBytes)) / \(FireDiagnosticsPresentation.byteSize(document.totalBytes))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(document.identifiedRenderedLines) { item in
                                    Text(item.value.isEmpty ? " " : item.value)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if viewModel.isLoadingLogPage(relativePath: relativePath) {
                                    ProgressView()
                                        .padding(.vertical, 8)
                                } else if document.olderCursor != nil {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            viewModel.loadOlderLogPage(relativePath: relativePath)
                                        }
                                }
                            }
                            .padding(12)
                            .textSelection(.enabled)
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView("加载日志…")
                    .task {
                        viewModel.loadLogFile(relativePath: relativePath)
                    }
            }
        }
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FireDiagnosticsTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            uiView.setContentOffset(.zero, animated: false)
        }
    }
}

// MARK: - Presentation Helpers

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
            return "进行中"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        }
    }
}
