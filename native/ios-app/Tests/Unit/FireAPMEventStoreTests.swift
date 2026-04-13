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

    func testEventStoreRoundTripsRuntimeStateAndExportsZipBundle() async throws {
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
        XCTAssertEqual(export.absoluteURL.pathExtension, "zip")

        let entryNames = try zipEntryNames(at: export.absoluteURL)
        XCTAssertTrue(entryNames.contains { $0.hasSuffix("/manifest.json") })
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

    func testExportBundleDoesNotPruneLiveDiagnosticsAndPackagesArtifactsIntoZip() async throws {
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
        XCTAssertEqual(export.absoluteURL.pathExtension, "zip")

        let entryNames = try zipEntryNames(at: export.absoluteURL)
        XCTAssertTrue(entryNames.contains { $0.hasSuffix("/crashes/crash.plcrash") })
        XCTAssertTrue(entryNames.contains { $0.hasSuffix("/metrickit/metric.json") })
        XCTAssertTrue(entryNames.contains { $0.hasSuffix("/\(rustBundleURL.lastPathComponent)") })
        XCTAssertTrue(entryNames.contains { $0.hasSuffix("/manifest.json") })
    }

    func testExportBundlePrunesExpiredAndExcessArchives() async throws {
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

        let now = Date()
        for index in 0..<4 {
            let archiveURL = exportBaseURL.appendingPathComponent("recent-\(index).zip", isDirectory: false)
            try Data("recent-\(index)".utf8).write(to: archiveURL, options: .atomic)
            try fileManager.setAttributes(
                [.modificationDate: now.addingTimeInterval(TimeInterval(-(index + 1) * 60))],
                ofItemAtPath: archiveURL.path
            )
        }

        let expiredArchiveURL = exportBaseURL.appendingPathComponent("expired.zip", isDirectory: false)
        try Data("expired".utf8).write(to: expiredArchiveURL, options: .atomic)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-(26 * 60 * 60))],
            ofItemAtPath: expiredArchiveURL.path
        )

        let legacyArchiveURL = rootURL
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent("legacy.firesupportbundle", isDirectory: true)
        try fileManager.createDirectory(at: legacyArchiveURL, withIntermediateDirectories: true)
        let legacyManifestURL = legacyArchiveURL.appendingPathComponent("manifest.json", isDirectory: false)
        try Data("{}".utf8).write(to: legacyManifestURL, options: .atomic)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-(26 * 60 * 60))],
            ofItemAtPath: legacyArchiveURL.path
        )
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-(26 * 60 * 60))],
            ofItemAtPath: legacyManifestURL.path
        )

        let export = try await store.exportBundle(
            rustSupportBundleURL: nil,
            runtimeState: nil,
            scenePhase: "active"
        )

        let remainingExports = try fileManager.contentsOfDirectory(
            at: exportBaseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        XCTAssertEqual(remainingExports.count, 3)
        XCTAssertTrue(remainingExports.contains(export.absoluteURL))
        XCTAssertFalse(fileManager.fileExists(atPath: expiredArchiveURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyArchiveURL.path))
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

    private func zipEntryNames(at url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        let endOfCentralDirectorySignature = Data([0x50, 0x4B, 0x05, 0x06])
        guard let endRecordRange = data.range(
            of: endOfCentralDirectorySignature,
            options: .backwards
        ) else {
            XCTFail("Missing end of central directory record")
            return []
        }

        let endRecordOffset = endRecordRange.lowerBound
        let entryCount = Int(readUInt16LE(data, at: endRecordOffset + 10))
        let centralDirectoryOffset = Int(readUInt32LE(data, at: endRecordOffset + 16))

        var cursor = centralDirectoryOffset
        var entryNames: [String] = []

        for _ in 0..<entryCount {
            XCTAssertEqual(readUInt32LE(data, at: cursor), 0x02014B50)
            let nameLength = Int(readUInt16LE(data, at: cursor + 28))
            let extraLength = Int(readUInt16LE(data, at: cursor + 30))
            let commentLength = Int(readUInt16LE(data, at: cursor + 32))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            let nameData = data.subdata(in: nameStart..<nameEnd)
            entryNames.append(String(decoding: nameData, as: UTF8.self))
            cursor = nameEnd + extraLength + commentLength
        }

        return entryNames
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
