import Foundation
import SwiftUI

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

struct FireDiagnosticsShareRequest: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
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
    @Published var shareRequest: FireDiagnosticsShareRequest?

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

    func presentSupportBundleShare() {
        guard let url = supportBundleURL() else {
            return
        }
        shareRequest = FireDiagnosticsShareRequest(
            title: "Fire Rust Diagnostics",
            url: url
        )
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
                let export = try await appViewModel.exportFullAPMSupportBundle(
                    scenePhase: scenePhase
                )
                latestFullAPMSupportBundle = export
                shareRequest = FireDiagnosticsShareRequest(
                    title: "Fire Full APM Export",
                    url: export.absoluteURL
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func fullAPMSupportBundleURL() -> URL? {
        latestFullAPMSupportBundle?.absoluteURL
    }

    func presentFullAPMSupportBundleShare() {
        guard let url = fullAPMSupportBundleURL() else {
            return
        }
        shareRequest = FireDiagnosticsShareRequest(
            title: "Fire Full APM Export",
            url: url
        )
    }

    func clearShareRequest() {
        shareRequest = nil
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
