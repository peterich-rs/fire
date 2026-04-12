import XCTest
@testable import Fire

final class FireAPMEventStoreTests: XCTestCase {
    func testEventStorePersistsEventsAndBuildsSummary() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let store = try await FireAPMEventStore(
            buildInfo: FireAPMBuildInfo(
                appVersion: "1.0.0",
                buildNumber: "42",
                bundleIdentifier: "com.fire.tests",
                gitSha: "deadbeef"
            ),
            baseURL: rootURL,
            fileManager: fileManager
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
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let store = try await FireAPMEventStore(
            buildInfo: FireAPMBuildInfo(
                appVersion: "1.0.0",
                buildNumber: "42",
                bundleIdentifier: "com.fire.tests",
                gitSha: "deadbeef"
            ),
            baseURL: rootURL,
            fileManager: fileManager
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
    }
}
