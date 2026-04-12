import Foundation

actor FireAPMEventStore {
    private enum Constants {
        static let maxTotalBytes: UInt64 = 32 * 1024 * 1024
        static let retentionWindow: TimeInterval = 7 * 24 * 60 * 60
    }

    private let baseURL: URL
    private let buildInfo: FireAPMBuildInfo
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        buildInfo: FireAPMBuildInfo,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) async throws {
        self.buildInfo = buildInfo
        self.baseURL = try baseURL ?? Self.defaultBaseURL(fileManager: fileManager)
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
        try ensureDirectories()
    }

    static func defaultBaseURL(fileManager: FileManager = .default) throws -> URL {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportURL
            .appendingPathComponent("Fire", isDirectory: true)
            .appendingPathComponent("ios-apm", isDirectory: true)
    }

    func baseDirectoryURL() -> URL {
        baseURL
    }

    func record(
        eventType: FireAPMEventType,
        launchID: String?,
        diagnosticSessionID: String?,
        route: String?,
        scenePhase: String?,
        privacyTier: FireAPMPrivacyTier,
        payloadSummary: [String: String],
        payloadData: Data? = nil,
        payloadSubdirectory: String? = nil,
        payloadFileName: String? = nil
    ) async throws -> FireAPMEventEnvelope {
        let payloadPath: String?
        if let payloadData, let payloadSubdirectory, let payloadFileName {
            payloadPath = try persistAttachment(
                data: payloadData,
                subdirectory: payloadSubdirectory,
                fileName: payloadFileName
            )
        } else {
            payloadPath = nil
        }

        let envelope = FireAPMEventEnvelope(
            eventID: UUID().uuidString.lowercased(),
            eventType: eventType,
            capturedAtUnixMs: FireAPMClock.nowUnixMs(),
            launchID: launchID,
            diagnosticSessionID: diagnosticSessionID,
            appVersion: buildInfo.appVersion,
            buildNumber: buildInfo.buildNumber,
            gitSha: buildInfo.gitSha,
            route: route,
            scenePhase: scenePhase,
            privacyTier: privacyTier,
            payloadPath: payloadPath,
            payloadSummary: payloadSummary
        )
        try appendEvent(envelope)
        try pruneIfNeeded()
        return envelope
    }

    func updateRuntimeState(_ state: FireAPMRuntimeState) throws {
        try ensureDirectories()
        let data = try encoder.encode(state)
        try data.write(to: runtimeStateURL(), options: .atomic)
    }

    func runtimeState(launchID: String) throws -> FireAPMRuntimeState {
        let url = runtimeStateURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty(launchID: launchID)
        }
        return try decoder.decode(FireAPMRuntimeState.self, from: Data(contentsOf: url))
    }

    func recentEvents(
        limit: Int,
        matching types: Set<FireAPMEventType>? = nil
    ) throws -> [FireAPMEventEnvelope] {
        let events = try loadAllEvents()
        let filtered = events.filter { envelope in
            guard let types else { return true }
            return types.contains(envelope.eventType)
        }
        return Array(filtered.sorted { $0.capturedAtUnixMs > $1.capturedAtUnixMs }.prefix(limit))
    }

    func diagnosticsSummary(currentSample: FireAPMResourceSample?) throws -> FireAPMDiagnosticsSummary {
        let recent = try recentEvents(limit: 24)
        return FireAPMDiagnosticsSummary(
            currentSample: currentSample,
            recentCrashes: recentEvents(
                from: recent,
                matching: [.crash]
            ),
            recentMetricPayloads: recentEvents(
                from: recent,
                matching: [.metrickitMetric]
            ),
            recentDiagnostics: recentEvents(
                from: recent,
                matching: [.metrickitDiagnostic]
            ),
            recentStalls: recentEvents(
                from: recent,
                matching: [.stall]
            ),
            recentEvents: recent.map(Self.makeRecentEvent)
        )
    }

    func exportBundle(
        rustSupportBundleURL: URL?,
        runtimeState: FireAPMRuntimeState?,
        scenePhase: String?
    ) throws -> FireAPMSupportBundleExport {
        let timestamp = FireAPMClock.nowUnixMs()
        let fileName = "fire-ios-apm-\(timestamp).firesupportbundle"
        let exportURL = baseURL
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: true)

        if fileManager.fileExists(atPath: exportURL.path) {
            try fileManager.removeItem(at: exportURL)
        }
        try fileManager.createDirectory(at: exportURL, withIntermediateDirectories: true)

        for component in ["events", "crashes", "metrickit"] {
            let source = baseURL.appendingPathComponent(component, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = exportURL.appendingPathComponent(component, isDirectory: true)
            try fileManager.copyItem(at: source, to: destination)
        }

        if let rustSupportBundleURL, fileManager.fileExists(atPath: rustSupportBundleURL.path) {
            try fileManager.copyItem(
                at: rustSupportBundleURL,
                to: exportURL.appendingPathComponent(rustSupportBundleURL.lastPathComponent)
            )
        }

        let manifest = FireAPMSupportBundleManifest(
            exportedAtUnixMs: timestamp,
            scenePhase: scenePhase,
            buildInfo: buildInfo,
            runtimeState: runtimeState,
            rustSupportBundleFileName: rustSupportBundleURL?.lastPathComponent
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(
            to: exportURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let sizeBytes = try Self.directorySize(at: exportURL, fileManager: fileManager)
        try pruneIfNeeded()
        return FireAPMSupportBundleExport(
            fileName: fileName,
            absoluteURL: exportURL,
            sizeBytes: sizeBytes,
            createdAtUnixMs: timestamp
        )
    }

    private func appendEvent(_ envelope: FireAPMEventEnvelope) throws {
        try ensureDirectories()
        let eventURL = todayEventsURL()
        if !fileManager.fileExists(atPath: eventURL.path) {
            fileManager.createFile(atPath: eventURL.path, contents: nil)
        }
        let data = try encoder.encode(envelope)
        guard let handle = try? FileHandle(forWritingTo: eventURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0A]))
    }

    private func persistAttachment(
        data: Data,
        subdirectory: String,
        fileName: String
    ) throws -> String {
        try ensureDirectories()
        let directory = baseURL.appendingPathComponent(subdirectory, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url.path.replacingOccurrences(of: "\(baseURL.path)/", with: "")
    }

    private func loadAllEvents() throws -> [FireAPMEventEnvelope] {
        let eventFiles = try fileManager.contentsOfDirectory(
            at: baseURL.appendingPathComponent("events", isDirectory: true),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var events: [FireAPMEventEnvelope] = []
        for url in eventFiles where url.pathExtension == "ndjson" {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { continue }
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            for line in lines {
                guard let lineData = line.data(using: .utf8) else { continue }
                if let event = try? decoder.decode(FireAPMEventEnvelope.self, from: lineData) {
                    events.append(event)
                }
            }
        }
        return events
    }

    private func pruneIfNeeded() throws {
        let expirationCutoff = Date().addingTimeInterval(-Constants.retentionWindow)
        let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
                .isDirectoryKey
            ]
        )

        var files: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            if let modifiedAt = values.contentModificationDate, modifiedAt < expirationCutoff {
                try? fileManager.removeItem(at: item)
                continue
            }
            files.append(item)
        }

        var totalBytes = try files.reduce(UInt64.zero) { partialResult, url in
            partialResult + (try Self.fileSize(at: url, fileManager: fileManager))
        }
        guard totalBytes > Constants.maxTotalBytes else { return }

        let sorted = try files.sorted {
            let lhs = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhs = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhs < rhs
        }

        for file in sorted where totalBytes > Constants.maxTotalBytes {
            let fileBytes = try Self.fileSize(at: file, fileManager: fileManager)
            try? fileManager.removeItem(at: file)
            totalBytes = totalBytes > fileBytes ? totalBytes - fileBytes : 0
        }
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        for component in ["events", "crashes", "metrickit", "exports", "tmp"] {
            try fileManager.createDirectory(
                at: baseURL.appendingPathComponent(component, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func runtimeStateURL() -> URL {
        baseURL.appendingPathComponent("runtime-state.json", isDirectory: false)
    }

    private func todayEventsURL() -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(formatter.string(from: Date())).ndjson"
        return baseURL
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func directorySize(at url: URL, fileManager: FileManager) throws -> UInt64 {
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
        var total: UInt64 = 0
        while let item = enumerator?.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
    }

    private static func fileSize(at url: URL, fileManager: FileManager) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }

    private func recentEvents(
        from events: [FireAPMEventEnvelope],
        matching types: Set<FireAPMEventType>
    ) -> [FireAPMRecentEvent] {
        events.filter { types.contains($0.eventType) }.prefix(4).map(Self.makeRecentEvent)
    }

    private static func makeRecentEvent(_ envelope: FireAPMEventEnvelope) -> FireAPMRecentEvent {
        let title = envelope.payloadSummary["title"]
            ?? envelope.payloadSummary["name"]
            ?? envelope.eventType.rawValue
        let subtitle = envelope.payloadSummary["subtitle"]
            ?? envelope.payloadSummary["reason"]
            ?? envelope.payloadSummary["error"]
            ?? envelope.route
        return FireAPMRecentEvent(
            id: envelope.eventID,
            type: envelope.eventType,
            title: title,
            subtitle: subtitle,
            timestampUnixMs: envelope.capturedAtUnixMs
        )
    }
}

private struct FireAPMSupportBundleManifest: Codable {
    let exportedAtUnixMs: UInt64
    let scenePhase: String?
    let buildInfo: FireAPMBuildInfo
    let runtimeState: FireAPMRuntimeState?
    let rustSupportBundleFileName: String?
}
