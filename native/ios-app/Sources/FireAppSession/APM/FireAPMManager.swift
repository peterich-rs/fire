import Foundation
import MetricKit
import UIKit
import os.log
import os.signpost
import CrashReporter

@MainActor
final class FireAPMManager: NSObject {
    private struct ActiveSpan {
        let id: String
        let span: FireAPMSpanName
        let signpostID: OSSignpostID
        let startedAtUnixMs: UInt64
        let metadata: [String: String]
    }

    static let shared = FireAPMManager()

    private let buildInfo = FireAPMBuildInfo.current()
    private lazy var storeTask = Task {
        try await FireAPMEventStore(buildInfo: buildInfo)
    }
    private lazy var signpostLog = MXMetricManager.makeLogHandle(category: "fire.apm")
    private lazy var metricSubscriber = FireAPMMetricSubscriber(
        onMetricPayloads: { payloads in
            Task { @MainActor in
                await FireAPMManager.shared.handleMetricPayloads(payloads)
            }
        },
        onDiagnosticPayloads: { payloads in
            Task { @MainActor in
                await FireAPMManager.shared.handleDiagnosticPayloads(payloads)
            }
        }
    )
    private lazy var resourceSampler = FireAPMResourceSampler { sample in
        Task { @MainActor in
            await FireAPMManager.shared.handleResourceSample(sample)
        }
    }
    private lazy var stallMonitor = FireAPMMainThreadStallMonitor { durationMs, severe in
        Task { @MainActor in
            await FireAPMManager.shared.handleMainThreadStall(
                durationMs: durationMs,
                severe: severe
            )
        }
    }

    private var started = false
    private var sessionLogger: FireHostLogger?
    private var crashReporter: PLCrashReporter?
    private var observers: [NSObjectProtocol] = []
    private var runtimeState = FireAPMRuntimeState.empty(launchID: UUID().uuidString.lowercased())
    private var latestResourceSample: FireAPMResourceSample?
    private var lastRecordedResourceSampleAtUnixMs: UInt64 = 0
    private var activeSpans: [String: ActiveSpan] = [:]
    private var extendedLaunchTaskActive = false
    private let launchMeasurementTaskID: MXLaunchTaskID = MXLaunchTaskID(rawValue: "app.launch.restore_session")

    func start() {
        guard !started else { return }
        started = true

        Task {
            await bootstrap()
        }
    }

    func attachSessionStore(_ sessionStore: FireSessionStore) async {
        sessionLogger = sessionStore.makeLogger(target: "ios.apm")
        let diagnosticSessionID = try? await sessionStore.diagnosticSessionID()
        if runtimeState.diagnosticSessionID != diagnosticSessionID {
            runtimeState.diagnosticSessionID = diagnosticSessionID
            await persistRuntimeState()
            await recordEvent(
                type: .sessionLink,
                privacy: .summary,
                summary: [
                    "title": "Attached shared diagnostics session",
                    "diagnostic_session_id": diagnosticSessionID ?? "unknown"
                ]
            )
        }
    }

    func setScenePhase(_ phase: String) {
        guard runtimeState.scenePhase != phase else { return }
        runtimeState.scenePhase = phase
        resourceSampler.setSceneActive(phase == "active")
        stallMonitor.setSceneActive(phase == "active")
        if phase == "active" {
            resourceSampler.boostSamplingWindow(duration: 20)
        }
        Task {
            await persistRuntimeState()
            await recordEvent(
                type: .scenePhase,
                privacy: .summary,
                summary: [
                    "title": "Scene phase changed",
                    "phase": phase
                ]
            )
        }
    }

    func setCurrentRoute(_ route: String?) {
        guard runtimeState.currentRoute != route else { return }
        runtimeState.currentRoute = route
        Task {
            await persistRuntimeState()
            await recordEvent(
                type: .route,
                privacy: .summary,
                summary: [
                    "title": "Route changed",
                    "route": route ?? "unknown"
                ]
            )
        }
    }

    func recordBreadcrumb(level: String = "info", target: String, message: String) {
        let breadcrumb = FireAPMBreadcrumb(level: level, target: target, message: message)
        runtimeState.breadcrumbs.append(breadcrumb)
        runtimeState.breadcrumbs = Array(runtimeState.breadcrumbs.suffix(50))
        sessionLogger?.info("[\(level)] \(target): \(message)")
        Task {
            await persistRuntimeState()
            await recordEvent(
                type: .breadcrumb,
                privacy: .summary,
                summary: [
                    "title": message,
                    "target": target,
                    "level": level
                ]
            )
        }
    }

    func withSpan<T>(
        _ span: FireAPMSpanName,
        metadata: [String: String] = [:],
        operation: () async throws -> T
    ) async rethrows -> T {
        let token = beginSpan(span, metadata: metadata)
        do {
            let value = try await operation()
            endSpan(token, outcome: "succeeded", errorMessage: nil)
            return value
        } catch {
            endSpan(token, outcome: "failed", errorMessage: error.localizedDescription)
            throw error
        }
    }

    func diagnosticsSummary() async throws -> FireAPMDiagnosticsSummary {
        let store = try await storeValue()
        return try await store.diagnosticsSummary(currentSample: latestResourceSample)
    }

    func exportSupportBundle(
        rustSupportBundleURL: URL?,
        scenePhase: String?
    ) async throws -> FireAPMSupportBundleExport {
        let store = try await storeValue()
        return try await store.exportBundle(
            rustSupportBundleURL: rustSupportBundleURL,
            runtimeState: runtimeState,
            scenePhase: scenePhase
        )
    }

    private func bootstrap() async {
        let previousState: FireAPMRuntimeState
        do {
            previousState = try await storeValue().runtimeState(launchID: runtimeState.launchID)
        } catch {
            previousState = .empty(launchID: runtimeState.launchID)
        }

        await harvestPendingCrashReportIfNeeded(previousState: previousState)

        runtimeState = .empty(launchID: UUID().uuidString.lowercased())
        await persistRuntimeState()

        registerObservers()
        metricSubscriber.start()
        resourceSampler.start()
        stallMonitor.start()
        startExtendedLaunchMeasurementIfNeeded()

        recordBreadcrumb(target: "ios.apm", message: "APM runtime started")
        await recordEvent(
            type: .launch,
            privacy: .summary,
            summary: [
                "title": "APM launch started",
                "bundle_id": buildInfo.bundleIdentifier,
                "git_sha": buildInfo.gitSha
            ]
        )
        installCrashReporterIfNeeded()
    }

    private func beginSpan(
        _ span: FireAPMSpanName,
        metadata: [String: String]
    ) -> ActiveSpan {
        let active = ActiveSpan(
            id: UUID().uuidString.lowercased(),
            span: span,
            signpostID: OSSignpostID(log: signpostLog),
            startedAtUnixMs: FireAPMClock.nowUnixMs(),
            metadata: metadata
        )
        activeSpans[active.id] = active
        runtimeState.activeSpans = activeSpans.values.map(\.span.rawValue).sorted()
        resourceSampler.boostSamplingWindow()
        os_signpost(.begin, log: signpostLog, name: span.signpostName, signpostID: active.signpostID)
        Task {
            await persistRuntimeState()
        }
        return active
    }

    private func endSpan(
        _ active: ActiveSpan,
        outcome: String,
        errorMessage: String?
    ) {
        os_signpost(.end, log: signpostLog, name: active.span.signpostName, signpostID: active.signpostID)
        activeSpans.removeValue(forKey: active.id)
        runtimeState.activeSpans = activeSpans.values.map(\.span.rawValue).sorted()
        Task {
            await persistRuntimeState()
            var summary = active.metadata
            summary["title"] = active.span.rawValue
            summary["name"] = active.span.rawValue
            summary["outcome"] = outcome
            summary["duration_ms"] = String(FireAPMClock.nowUnixMs().saturatingSubtract(active.startedAtUnixMs))
            if let errorMessage, !errorMessage.isEmpty {
                summary["error"] = errorMessage
            }
            await recordEvent(type: .span, privacy: .summary, summary: summary)
            if active.span == .appLaunchRestoreSession {
                finishExtendedLaunchMeasurementIfNeeded()
            }
        }
    }

    private func handleResourceSample(_ sample: FireAPMResourceSample) async {
        latestResourceSample = sample
        let shouldPersist = sample.timestampUnixMs.saturatingSubtract(lastRecordedResourceSampleAtUnixMs) >= 30_000
            || (sample.cpuPercent ?? 0) >= 80
            || (sample.physicalFootprintBytes ?? 0) >= 350 * 1024 * 1024
        guard shouldPersist else { return }
        lastRecordedResourceSampleAtUnixMs = sample.timestampUnixMs
        await recordEvent(
            type: .resourceSample,
            privacy: .summary,
            summary: [
                "title": "Resource sample",
                "cpu_percent": sample.cpuPercent.map { String(format: "%.1f", $0) } ?? "unknown",
                "resident_bytes": sample.residentSizeBytes.map(String.init) ?? "unknown",
                "physical_footprint_bytes": sample.physicalFootprintBytes.map(String.init) ?? "unknown",
                "thermal_state": sample.thermalState
            ]
        )
    }

    private func handleMainThreadStall(durationMs: UInt64, severe: Bool) async {
        await recordEvent(
            type: .stall,
            privacy: .summary,
            summary: [
                "title": severe ? "Severe main-thread stall" : "Main-thread stall",
                "duration_ms": String(durationMs),
                "severity": severe ? "severe" : "stall",
                "route": runtimeState.currentRoute ?? "unknown"
            ]
        )
    }

    private func handleMetricPayloads(_ payloads: [MXMetricPayload]) async {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            let fileName = "metric-\(FireAPMClock.nowUnixMs())-\(UUID().uuidString.lowercased()).json"
            await recordEvent(
                type: .metrickitMetric,
                privacy: .diagnostic,
                summary: [
                    "title": "MetricKit metric payload",
                    "time_begin": ISO8601DateFormatter().string(from: payload.timeStampBegin),
                    "time_end": ISO8601DateFormatter().string(from: payload.timeStampEnd),
                    "latest_application_version": payload.latestApplicationVersion,
                    "includes_multiple_application_versions": payload.includesMultipleApplicationVersions ? "true" : "false"
                ],
                payloadData: data,
                payloadSubdirectory: "metrickit",
                payloadFileName: fileName
            )
        }
    }

    private func handleDiagnosticPayloads(_ payloads: [MXDiagnosticPayload]) async {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            let fileName = "diagnostic-\(FireAPMClock.nowUnixMs())-\(UUID().uuidString.lowercased()).json"
            await recordEvent(
                type: .metrickitDiagnostic,
                privacy: .diagnostic,
                summary: [
                    "title": "MetricKit diagnostic payload",
                    "hang_count": payload.hangDiagnostics?.count.description ?? "0",
                    "crash_count": payload.crashDiagnostics?.count.description ?? "0",
                    "cpu_exception_count": payload.cpuExceptionDiagnostics?.count.description ?? "0",
                    "disk_write_exception_count": payload.diskWriteExceptionDiagnostics?.count.description ?? "0"
                ],
                payloadData: data,
                payloadSubdirectory: "metrickit",
                payloadFileName: fileName
            )
        }
    }

    private func installCrashReporterIfNeeded() {
        guard isCrashReporterEnabled else { return }
        guard crashReporter == nil else { return }

        let config = PLCrashReporterConfig(
            signalHandlerType: .mach,
            symbolicationStrategy: [],
            shouldRegisterUncaughtExceptionHandler: true,
            basePath: crashBasePath(),
            maxReportBytes: 512 * 1024
        )
        guard let reporter = PLCrashReporter(configuration: config) else {
            sessionLogger?.error("Failed to create PLCrashReporter instance")
            return
        }
        do {
            try reporter.enableAndReturnError()
            crashReporter = reporter
            sessionLogger?.info("PLCrashReporter enabled")
        } catch {
            sessionLogger?.error("Failed to enable PLCrashReporter: \(error.localizedDescription)")
        }
    }

    private func harvestPendingCrashReportIfNeeded(previousState: FireAPMRuntimeState) async {
        guard isCrashReporterEnabled else { return }
        let config = PLCrashReporterConfig(
            signalHandlerType: .mach,
            symbolicationStrategy: [],
            shouldRegisterUncaughtExceptionHandler: true,
            basePath: crashBasePath(),
            maxReportBytes: 512 * 1024
        )
        guard let reporter = PLCrashReporter(configuration: config) else {
            return
        }
        guard reporter.hasPendingCrashReport() else { return }

        do {
            let data = try reporter.loadPendingCrashReportDataAndReturnError()
            let report = try PLCrashReport(data: data)
            let fileName = "crash-\(FireAPMClock.nowUnixMs())-\(UUID().uuidString.lowercased()).plcrash"
            let summary = makeCrashSummary(report: report, previousState: previousState)
            await recordEvent(
                type: .crash,
                privacy: .diagnostic,
                launchID: previousState.launchID,
                diagnosticSessionID: previousState.diagnosticSessionID,
                route: previousState.currentRoute,
                scenePhase: previousState.scenePhase,
                summary: summary,
                payloadData: data,
                payloadSubdirectory: "crashes",
                payloadFileName: fileName
            )
            try reporter.purgePendingCrashReportAndReturnError()
        } catch {
            await recordEvent(
                type: .crash,
                privacy: .summary,
                launchID: previousState.launchID,
                diagnosticSessionID: previousState.diagnosticSessionID,
                route: previousState.currentRoute,
                scenePhase: previousState.scenePhase,
                summary: [
                    "title": "Pending crash report could not be decoded",
                    "error": error.localizedDescription
                ]
            )
        }
    }

    private func makeCrashSummary(
        report: PLCrashReport,
        previousState: FireAPMRuntimeState
    ) -> [String: String] {
        var summary: [String: String] = [
            "title": "Pending crash report",
            "signal_name": report.signalInfo.name,
            "signal_code": String(report.signalInfo.code),
            "threads": String(report.threads.count),
            "route": previousState.currentRoute ?? "unknown",
            "breadcrumbs": String(previousState.breadcrumbs.count)
        ]
        if report.hasExceptionInfo {
            summary["exception_name"] = report.exceptionInfo.exceptionName
        }
        return summary
    }

    private func persistRuntimeState() async {
        runtimeState.lastUpdatedUnixMs = FireAPMClock.nowUnixMs()
        do {
            try await storeValue().updateRuntimeState(runtimeState)
        } catch {
            sessionLogger?.error("Failed to persist APM runtime state: \(error.localizedDescription)")
        }
    }

    private func recordEvent(
        type: FireAPMEventType,
        privacy: FireAPMPrivacyTier,
        launchID: String? = nil,
        diagnosticSessionID: String? = nil,
        route: String? = nil,
        scenePhase: String? = nil,
        summary: [String: String],
        payloadData: Data? = nil,
        payloadSubdirectory: String? = nil,
        payloadFileName: String? = nil
    ) async {
        do {
            _ = try await storeValue().record(
                eventType: type,
                launchID: launchID ?? runtimeState.launchID,
                diagnosticSessionID: diagnosticSessionID ?? runtimeState.diagnosticSessionID,
                route: route ?? runtimeState.currentRoute,
                scenePhase: scenePhase ?? runtimeState.scenePhase,
                privacyTier: privacy,
                payloadSummary: summary,
                payloadData: payloadData,
                payloadSubdirectory: payloadSubdirectory,
                payloadFileName: payloadFileName
            )
        } catch {
            sessionLogger?.error("Failed to record APM event \(type.rawValue): \(error.localizedDescription)")
        }
    }

    private func registerObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil
            ) { _ in
                Task { @MainActor in
                    await FireAPMManager.shared.handleLowMemoryWarning()
                }
            }
        )
    }

    private func handleLowMemoryWarning() async {
        resourceSampler.boostSamplingWindow(duration: 30)
        await recordEvent(
            type: .memoryWarning,
            privacy: .summary,
            summary: [
                "title": "UIApplication memory warning",
                "route": runtimeState.currentRoute ?? "unknown"
            ]
        )
    }

    private func storeValue() async throws -> FireAPMEventStore {
        try await storeTask.value
    }

    private func startExtendedLaunchMeasurementIfNeeded() {
        guard !extendedLaunchTaskActive else { return }
        do {
            try MXMetricManager.extendLaunchMeasurement(forTaskID: launchMeasurementTaskID)
            extendedLaunchTaskActive = true
        } catch {
            sessionLogger?.warning("Failed to extend launch measurement: \(error.localizedDescription)")
        }
    }

    private func finishExtendedLaunchMeasurementIfNeeded() {
        guard extendedLaunchTaskActive else { return }
        do {
            try MXMetricManager.finishExtendedLaunchMeasurement(forTaskID: launchMeasurementTaskID)
        } catch {
            sessionLogger?.warning("Failed to finish launch measurement: \(error.localizedDescription)")
        }
        extendedLaunchTaskActive = false
    }

    private func crashBasePath() -> String {
        (try? FireAPMEventStore.defaultBaseURL().appendingPathComponent("tmp", isDirectory: true).path)
            ?? NSTemporaryDirectory()
    }

    private var isCrashReporterEnabled: Bool {
        #if DEBUG
        return false
        #else
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        #endif
    }
}

private final class FireAPMMetricSubscriber: NSObject, MXMetricManagerSubscriber {
    private let onMetricPayloads: @Sendable ([MXMetricPayload]) -> Void
    private let onDiagnosticPayloads: @Sendable ([MXDiagnosticPayload]) -> Void
    private var started = false

    init(
        onMetricPayloads: @escaping @Sendable ([MXMetricPayload]) -> Void,
        onDiagnosticPayloads: @escaping @Sendable ([MXDiagnosticPayload]) -> Void
    ) {
        self.onMetricPayloads = onMetricPayloads
        self.onDiagnosticPayloads = onDiagnosticPayloads
    }

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        onMetricPayloads(payloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        onDiagnosticPayloads(payloads)
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
