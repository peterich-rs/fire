import Foundation

@MainActor
extension FireAppViewModel {
    func listLogFiles() async throws -> [LogFileSummaryState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.listLogFiles()
    }

    func readLogFile(relativePath: String) async throws -> LogFileDetailState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.readLogFile(relativePath: relativePath)
    }

    func readLogFilePage(
        relativePath: String,
        cursor: UInt64? = nil,
        maxBytes: UInt64? = nil,
        direction: DiagnosticsPageDirectionState
    ) async throws -> LogFilePageState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.readLogFilePage(
            relativePath: relativePath,
            cursor: cursor,
            maxBytes: maxBytes,
            direction: direction
        )
    }

    func listNetworkTraces(limit: UInt64 = 200) async throws -> [NetworkTraceSummaryState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.listNetworkTraces(limit: limit)
    }

    func networkTraceDetail(traceID: UInt64) async throws -> NetworkTraceDetailState {
        let sessionStore = try await sessionStoreValue()
        guard let detail = try await sessionStore.networkTraceDetail(traceID: traceID) else {
            throw FireDiagnosticsAccessError.traceNotFound
        }
        return detail
    }

    func networkTraceBodyPage(
        traceID: UInt64,
        cursor: UInt64? = nil,
        maxBytes: UInt64? = nil,
        direction: DiagnosticsPageDirectionState
    ) async throws -> NetworkTraceBodyPageState? {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.networkTraceBodyPage(
            traceID: traceID,
            cursor: cursor,
            maxBytes: maxBytes,
            direction: direction
        )
    }

    func diagnosticSessionID() async throws -> String {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.diagnosticSessionID()
    }

    func exportSupportBundle(scenePhase: String?) async throws -> SupportBundleExportState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.exportSupportBundle(
            platform: "ios",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
            scenePhase: scenePhase
        )
    }

    func apmDiagnosticsSummary() async throws -> FireAPMDiagnosticsSummary {
        try await FireAPMManager.shared.diagnosticsSummary()
    }

    func exportFullAPMSupportBundle(scenePhase: String?) async throws -> FireAPMSupportBundleExport {
        let rustBundleURL: URL?
        if let sessionStore = try? await sessionStoreValue() {
            let rustBundle = try? await sessionStore.exportSupportBundle(
                platform: "ios",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                buildNumber: Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
                scenePhase: scenePhase
            )
            rustBundleURL = rustBundle.map { URL(fileURLWithPath: $0.absolutePath) }
        } else {
            rustBundleURL = nil
        }
        defer {
            if let rustBundleURL {
                try? FileManager.default.removeItem(at: rustBundleURL)
            }
        }
        return try await FireAPMManager.shared.exportSupportBundle(
            rustSupportBundleURL: rustBundleURL,
            scenePhase: scenePhase
        )
    }

    func flushDiagnosticsLogs(sync: Bool = true) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.flushLogs(sync: sync)
    }

    func handleDiagnosticsScenePhaseChange(_ phase: String, isAuthenticated: Bool) {
        FireCfClearanceRefreshService.shared.setSceneActive(phase == "active")
        Task {
            guard let sessionStore = currentSessionStore() else { return }
            let logger = sessionStore.makeLogger(target: Self.diagnosticsLifecycleLogTarget)
            logger.info("scene phase changed to \(phase), authenticated=\(isAuthenticated)")
            if phase == "background" || phase == "inactive" {
                try? await sessionStore.flushLogs(sync: phase == "background")
            }
        }
    }
}
