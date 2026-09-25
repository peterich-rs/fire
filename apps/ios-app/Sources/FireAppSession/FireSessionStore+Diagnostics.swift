import Foundation

extension FireSessionStore {
    public func listLogFiles() async throws -> [LogFileSummaryState] {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(with: Result { try core.diagnostics().listLogFiles() })
            }
        }
    }

    public func readLogFile(relativePath: String) async throws -> LogFileDetailState {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(with: Result { try core.diagnostics().readLogFile(relativePath: relativePath) })
            }
        }
    }

    public func readLogFilePage(
        relativePath: String,
        cursor: UInt64? = nil,
        maxBytes: UInt64? = nil,
        direction: DiagnosticsPageDirectionState
    ) async throws -> LogFilePageState {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(
                    with: Result {
                        try core.diagnostics().readLogFilePage(
                            relativePath: relativePath,
                            cursor: cursor,
                            maxBytes: maxBytes,
                            direction: direction
                        )
                    }
                )
            }
        }
    }

    public func listNetworkTraces(limit: UInt64 = 200) throws -> [NetworkTraceSummaryState] {
        try core.diagnostics().listNetworkTraces(limit: limit)
    }

    public func networkTraceDetail(traceID: UInt64) throws -> NetworkTraceDetailState? {
        try core.diagnostics().networkTraceDetail(traceId: traceID)
    }

    public func networkTraceBodyPage(
        traceID: UInt64,
        cursor: UInt64? = nil,
        maxBytes: UInt64? = nil,
        direction: DiagnosticsPageDirectionState
    ) async throws -> NetworkTraceBodyPageState? {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(
                    with: Result {
                        try core.diagnostics().networkTraceBodyPage(
                            traceId: traceID,
                            cursor: cursor,
                            maxBytes: maxBytes,
                            direction: direction
                        )
                    }
                )
            }
        }
    }

    public func diagnosticSessionID() throws -> String {
        try core.diagnostics().diagnosticSessionId()
    }

    public func exportSupportBundle(
        platform: String,
        appVersion: String?,
        buildNumber: String?,
        scenePhase: String?
    ) async throws -> SupportBundleExportState {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(
                    with: Result {
                        try core.diagnostics().exportSupportBundle(
                            hostContext: SupportBundleHostContextState(
                                platform: platform,
                                appVersion: appVersion,
                                buildNumber: buildNumber,
                                scenePhase: scenePhase
                            )
                        )
                    }
                )
            }
        }
    }

    /// Redacted diagnostics package safe to leave the device (feedback share / upload).
    public func exportFeedbackBundle(
        platform: String,
        appVersion: String?,
        buildNumber: String?,
        scenePhase: String?
    ) async throws -> SupportBundleExportState {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        return try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(
                    with: Result {
                        try core.diagnostics().exportFeedbackBundle(
                            hostContext: SupportBundleHostContextState(
                                platform: platform,
                                appVersion: appVersion,
                                buildNumber: buildNumber,
                                scenePhase: scenePhase
                            )
                        )
                    }
                )
            }
        }
    }

    public func flushLogs(sync: Bool = true) async throws {
        let core = self.core
        let diagnosticsQueue = self.diagnosticsQueue
        try await withCheckedThrowingContinuation { continuation in
            diagnosticsQueue.async {
                continuation.resume(with: Result { try core.diagnostics().flushLogs(sync: sync) })
            }
        }
    }
}
