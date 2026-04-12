import XCTest
@testable import Fire

final class FireAPMEventStoreTests: XCTestCase {
    private let buildInfo = FireAPMBuildInfo(
        appVersion: "1.0.0",
        buildNumber: "42",
        bundleIdentifier: "com.fire.tests",
        gitSha: "deadbeef"
    )

    func testEventStorePersistsEventsAndBuildsSummary() async throws {
        let fileManager = FileManager.default
        let sandboxURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: sandboxURL) }

        let store = try await makeStore(
            fileManager: fileManager,
            baseURL: sandboxURL.appendingPathComponent("ios-apm", isDirectory: true),
            exportBaseURL: sandboxURL.appendingPathComponent("ios-apm-exports", isDirectory: true)
        )

        _ = try await store.record(
            eventType: .crash,
            launchID: "launch-1",
            diagnosticSessionID: "session-1",
            route: "topic.detail.1",
            scenePhase: "active",
            privacyTier: .diagnostic,
            payloadSummary: [
                "title": "Pending crash report",
                "signal_name": "SIGABRT"
            ],
            payloadData: Data("boom".utf8),
            payloadSubdirectory: "crashes",
            payloadFileName: "crash.plcrash"
        )
        _ = try await store.record(
            eventType: .stall,
            launchID: "launch-1",
            diagnosticSessionID: "session-1",
            route: "tab.home",
            scenePhase: "active",
            privacyTier: .summary,
            payloadSummary: [
                "title": "Main-thread stall",
                "duration_ms": "900"
            ]
        )

        let summary = try await store.diagnosticsSummary(currentSample: FireAPMResourceSample(
            timestampUnixMs: 1,
            cpuPercent: 12.5,
            residentSizeBytes: 1_024,
            physicalFootprintBytes: 2_048,
            thermalState: "nominal",
            batteryState: "charging",
            lowPowerModeEnabled: false
        ))

        XCTAssertEqual(summary.recentCrashes.count, 1)
        XCTAssertEqual(summary.recentStalls.count, 1)
        XCTAssertEqual(summary.currentSample?.physicalFootprintBytes, 2_048)
    }

    func testEventStoreRoundTripsRuntimeStateAndExportsBundle() async throws {
        let fileManager = FileManager.default
        let sandboxURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: sandboxURL) }
        let rootURL = sandboxURL.appendingPathComponent("ios-apm", isDirectory: true)
        let exportBaseURL = sandboxURL.appendingPathComponent("ios-apm-exports", isDirectory: true)

        let store = try await makeStore(
            fileManager: fileManager,
            baseURL: rootURL,
            exportBaseURL: exportBaseURL
        )

        let runtimeState = FireAPMRuntimeState(
            launchID: "launch-2",
            diagnosticSessionID: "session-2",
            currentRoute: "tab.home",
            scenePhase: "active",
            activeSpans: ["feed.latest.initial_load"],
            breadcrumbs: [
                FireAPMBreadcrumb(level: "info", target: "tests", message: "hello")
            ],
            lastUpdatedUnixMs: 2
        )
        try await store.updateRuntimeState(runtimeState)

        let restored = try await store.runtimeState(launchID: "unused")
        XCTAssertEqual(restored.launchID, "launch-2")
        XCTAssertEqual(restored.currentRoute, "tab.home")

        let export = try await store.exportBundle(
            rustSupportBundleURL: nil,
            runtimeState: restored,
            scenePhase: "active"
        )
        XCTAssertTrue(fileManager.fileExists(atPath: export.absoluteURL.path))
        XCTAssertGreaterThan(export.sizeBytes, 0)
        XCTAssertTrue(export.absoluteURL.path.hasPrefix(exportBaseURL.path + "/"))
        XCTAssertFalse(export.absoluteURL.path.hasPrefix(rootURL.path + "/"))
    }

    func testPreviousRuntimeStateSkipsCurrentLaunchState() async throws {
        let fileManager = FileManager.default
        let sandboxURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: sandboxURL) }

        let store = try await makeStore(
            fileManager: fileManager,
            baseURL: sandboxURL.appendingPathComponent("ios-apm", isDirectory: true),
            exportBaseURL: sandboxURL.appendingPathComponent("ios-apm-exports", isDirectory: true)
        )

        let previousState = FireAPMRuntimeState(
            launchID: "launch-prev",
            diagnosticSessionID: "session-prev",
            currentRoute: "tab.profile",
            scenePhase: "background",
            activeSpans: [],
            breadcrumbs: [],
            lastUpdatedUnixMs: 1
        )
        let currentState = FireAPMRuntimeState(
            launchID: "launch-current",
            diagnosticSessionID: "session-current",
            currentRoute: "tab.home",
            scenePhase: "active",
            activeSpans: [],
            breadcrumbs: [],
            lastUpdatedUnixMs: 2
        )

        try await store.updateRuntimeState(previousState)
        try await store.updateRuntimeState(currentState)

        let previousRuntimeState = try await store.previousRuntimeState(
            excludingLaunchID: "launch-current"
        )
        let restoredPrevious = try XCTUnwrap(previousRuntimeState)
        XCTAssertEqual(restoredPrevious.launchID, "launch-prev")
        XCTAssertEqual(restoredPrevious.diagnosticSessionID, "session-prev")
        XCTAssertEqual(restoredPrevious.currentRoute, "tab.profile")
    }

    func testExportBundleDoesNotPruneLiveDiagnosticsOrReturnedBundle() async throws {
        let fileManager = FileManager.default
        let sandboxURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: sandboxURL) }
        let rootURL = sandboxURL.appendingPathComponent("ios-apm", isDirectory: true)
        let exportBaseURL = sandboxURL.appendingPathComponent("ios-apm-exports", isDirectory: true)

        let store = try await makeStore(
            fileManager: fileManager,
            baseURL: rootURL,
            exportBaseURL: exportBaseURL
        )

        _ = try await store.record(
            eventType: .crash,
            launchID: "launch-3",
            diagnosticSessionID: "session-3",
            route: "topic.detail.3",
            scenePhase: "active",
            privacyTier: .diagnostic,
            payloadSummary: ["title": "Pending crash report"],
            payloadData: Data(repeating: 0x41, count: 15 * 1024 * 1024),
            payloadSubdirectory: "crashes",
            payloadFileName: "crash.plcrash"
        )
        _ = try await store.record(
            eventType: .metrickitDiagnostic,
            launchID: "launch-3",
            diagnosticSessionID: "session-3",
            route: "topic.detail.3",
            scenePhase: "active",
            privacyTier: .diagnostic,
            payloadSummary: ["title": "MetricKit payload"],
            payloadData: Data(repeating: 0x42, count: 14 * 1024 * 1024),
            payloadSubdirectory: "metrickit",
            payloadFileName: "metric.json"
        )

        let rustBundleURL = sandboxURL.appendingPathComponent("rust-support.firesupportbundle")
        try Data(repeating: 0x43, count: 10 * 1024 * 1024).write(to: rustBundleURL, options: .atomic)

        let export = try await store.exportBundle(
            rustSupportBundleURL: rustBundleURL,
            runtimeState: nil,
            scenePhase: "active"
        )

        XCTAssertTrue(fileManager.fileExists(atPath: rootURL.appendingPathComponent("crashes/crash.plcrash").path))
        XCTAssertTrue(fileManager.fileExists(atPath: rootURL.appendingPathComponent("metrickit/metric.json").path))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: export.absoluteURL.appendingPathComponent("crashes/crash.plcrash").path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: export.absoluteURL.appendingPathComponent("metrickit/metric.json").path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: export.absoluteURL.appendingPathComponent(rustBundleURL.lastPathComponent).path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: export.absoluteURL.appendingPathComponent("manifest.json").path
            )
        )
    }

    private func makeStore(
        fileManager: FileManager,
        baseURL: URL,
        exportBaseURL: URL
    ) async throws -> FireAPMEventStore {
        try await FireAPMEventStore(
            buildInfo: buildInfo,
            baseURL: baseURL,
            exportBaseURL: exportBaseURL,
            fileManager: fileManager
        )
    }
}
