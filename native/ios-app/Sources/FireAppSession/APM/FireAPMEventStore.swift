import Foundation

actor FireAPMEventStore {
    private enum Constants {
        static let maxTotalBytes: UInt64 = 32 * 1024 * 1024
        static let retentionWindow: TimeInterval = 7 * 24 * 60 * 60
        static let exportRetentionWindow: TimeInterval = 24 * 60 * 60
        static let maxExportArchiveCount = 3
        static let staleTemporaryExportWindow: TimeInterval = 6 * 60 * 60
    }

    private let baseURL: URL
    private let exportBaseURL: URL
    private let buildInfo: FireAPMBuildInfo
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        buildInfo: FireAPMBuildInfo,
        baseURL: URL? = nil,
        exportBaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) async throws {
        self.buildInfo = buildInfo
        let resolvedBaseURL = try baseURL ?? Self.defaultBaseURL(fileManager: fileManager)
        self.baseURL = resolvedBaseURL
        self.exportBaseURL = exportBaseURL ?? Self.defaultExportBaseURL(baseURL: resolvedBaseURL)
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
        try ensureDirectories()
        try pruneIfNeeded()
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

    static func defaultExportBaseURL(baseURL: URL) -> URL {
        baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("ios-apm-exports", isDirectory: true)
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
        try data.write(to: runtimeStateURL(launchID: state.launchID), options: .atomic)
    }

    func runtimeState(launchID: String) throws -> FireAPMRuntimeState {
        if let state = try loadRuntimeState(forLaunchID: launchID) {
            return state
        }
        if let state = try latestRuntimeState(excludingLaunchID: nil) {
            return state
        }
        if let state = try legacyRuntimeState() {
            return state
        }
        return .empty(launchID: launchID)
    }

    func previousRuntimeState(excludingLaunchID launchID: String) throws -> FireAPMRuntimeState? {
        if let state = try latestRuntimeState(excludingLaunchID: launchID) {
            return state
        }
        return try legacyRuntimeState()
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
        let archiveRootName = "fire-ios-apm-\(timestamp).firesupportbundle"
        let fileName = "fire-ios-apm-\(timestamp).zip"
        let exportURL = exportBaseURL
            .appendingPathComponent(fileName, isDirectory: false)
        let stagingURL = temporaryExportDirectoryURL(rootName: archiveRootName)

        try pruneIfNeeded()

        if fileManager.fileExists(atPath: exportURL.path) {
            try fileManager.removeItem(at: exportURL)
        }
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        for component in ["events", "crashes", "metrickit"] {
            let source = baseURL.appendingPathComponent(component, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = stagingURL.appendingPathComponent(component, isDirectory: true)
            try fileManager.copyItem(at: source, to: destination)
        }

        if let rustSupportBundleURL, fileManager.fileExists(atPath: rustSupportBundleURL.path) {
            try fileManager.copyItem(
                at: rustSupportBundleURL,
                to: stagingURL.appendingPathComponent(rustSupportBundleURL.lastPathComponent)
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
            to: stagingURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        try FireZipArchiveWriter.createArchive(
            from: stagingURL,
            to: exportURL,
            fileManager: fileManager
        )
        if fileManager.fileExists(atPath: stagingURL.path) {
            try? fileManager.removeItem(at: stagingURL)
        }
        try pruneExportArchivesIfNeeded(
            at: exportBaseURL,
            preserving: [exportURL.standardizedFileURL]
        )
        try pruneExportArchivesIfNeeded(at: legacyExportsDirectoryURL())
        let sizeBytes = try Self.fileSize(at: exportURL, fileManager: fileManager)
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

    private func pruneIfNeeded(preservingExportURLs: Set<URL> = []) throws {
        try pruneCapturedArtifactsIfNeeded()
        try pruneTemporaryExportsIfNeeded()
        try pruneExportArchivesIfNeeded(
            at: exportBaseURL,
            preserving: preservingExportURLs
        )
        try pruneExportArchivesIfNeeded(at: legacyExportsDirectoryURL())
    }

    private func pruneCapturedArtifactsIfNeeded() throws {
        let expirationCutoff = Date().addingTimeInterval(-Constants.retentionWindow)
        let legacyExportsURL = legacyExportsDirectoryURL().standardizedFileURL
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
            let values = try item.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]
            )
            let standardizedItem = item.standardizedFileURL
            if standardizedItem == legacyExportsURL
                || standardizedItem.path.hasPrefix(legacyExportsURL.path + "/") {
                if values.isDirectory == true {
                    enumerator?.skipDescendants()
                }
                continue
            }
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

    private func pruneTemporaryExportsIfNeeded() throws {
        let tmpURL = baseURL.appendingPathComponent("tmp", isDirectory: true)
        let expirationCutoff = Date().addingTimeInterval(-Constants.staleTemporaryExportWindow)
        for item in try directoryContents(at: tmpURL) {
            guard item.lastPathComponent.hasPrefix("fire-ios-apm-") else {
                continue
            }
            let modifiedAt = try item.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate ?? .distantPast
            if modifiedAt < expirationCutoff {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private func pruneExportArchivesIfNeeded(
        at directoryURL: URL,
        preserving preservedURLs: Set<URL> = []
    ) throws {
        let preservedURLs = Set(preservedURLs.map(\.standardizedFileURL))
        let expirationCutoff = Date().addingTimeInterval(-Constants.exportRetentionWindow)
        let contents = try directoryContents(at: directoryURL)
        if contents.isEmpty {
            return
        }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for item in contents {
            let values = try item.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey]
            )
            guard values.isRegularFile == true || values.isDirectory == true else {
                continue
            }

            let standardizedURL = item.standardizedFileURL
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if !preservedURLs.contains(standardizedURL), modifiedAt < expirationCutoff {
                try? fileManager.removeItem(at: item)
                continue
            }

            candidates.append((standardizedURL, modifiedAt))
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }

        var allowedURLs = preservedURLs
        for candidate in sorted {
            if allowedURLs.contains(candidate.url) {
                continue
            }
            if allowedURLs.count >= Constants.maxExportArchiveCount {
                break
            }
            allowedURLs.insert(candidate.url)
        }

        for candidate in sorted where !allowedURLs.contains(candidate.url) {
            try? fileManager.removeItem(at: candidate.url)
        }
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        for component in ["events", "crashes", "metrickit", "runtime-states", "tmp"] {
            try fileManager.createDirectory(
                at: baseURL.appendingPathComponent(component, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try fileManager.createDirectory(at: exportBaseURL, withIntermediateDirectories: true)
    }

    private func runtimeStatesDirectoryURL() -> URL {
        baseURL.appendingPathComponent("runtime-states", isDirectory: true)
    }

    private func runtimeStateURL(launchID: String) -> URL {
        runtimeStatesDirectoryURL()
            .appendingPathComponent(launchID, isDirectory: false)
            .appendingPathExtension("json")
    }

    private func legacyRuntimeStateURL() -> URL {
        baseURL.appendingPathComponent("runtime-state.json", isDirectory: false)
    }

    private func legacyExportsDirectoryURL() -> URL {
        baseURL.appendingPathComponent("exports", isDirectory: true)
    }

    private func temporaryExportDirectoryURL(rootName: String) -> URL {
        baseURL
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent(rootName, isDirectory: true)
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

    private func directoryContents(at url: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }

    private func loadRuntimeState(forLaunchID launchID: String) throws -> FireAPMRuntimeState? {
        let url = runtimeStateURL(launchID: launchID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try loadRuntimeState(at: url)
    }

    private func latestRuntimeState(excludingLaunchID launchID: String?) throws -> FireAPMRuntimeState? {
        let files = try fileManager.contentsOfDirectory(
            at: runtimeStatesDirectoryURL(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .filter { launchID == nil || $0.deletingPathExtension().lastPathComponent != launchID }
        .sorted { lhs, rhs in
            let lhsDate = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let rhsDate = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if lhsDate != rhsDate {
                return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
            }
            return lhs.lastPathComponent > rhs.lastPathComponent
        }

        for file in files {
            if let state = try? loadRuntimeState(at: file) {
                return state
            }
        }
        return nil
    }

    private func legacyRuntimeState() throws -> FireAPMRuntimeState? {
        let url = legacyRuntimeStateURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try loadRuntimeState(at: url)
    }

    private func loadRuntimeState(at url: URL) throws -> FireAPMRuntimeState {
        try decoder.decode(FireAPMRuntimeState.self, from: Data(contentsOf: url))
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

private struct FireZipArchiveWriter {
    private struct Entry {
        let relativePath: String
        let contents: Data
        let modifiedAt: Date
        let crc32: UInt32

        var sizeBytes: UInt32 {
            UInt32(contents.count)
        }
    }

    private struct DOSTimestamp {
        let time: UInt16
        let date: UInt16
    }

    private enum ZipArchiveError: Error {
        case unsupportedEntrySize(String)
        case unsupportedEntryCount(Int)
        case unsupportedArchiveSize
    }

    private static let utf8Flag: UInt16 = 1 << 11
    private static let calendar = Calendar(identifier: .gregorian)
    private static let crc32Table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            if value & 1 == 1 {
                value = 0xEDB88320 ^ (value >> 1)
            } else {
                value >>= 1
            }
        }
        return value
    }

    static func createArchive(
        from directoryURL: URL,
        to archiveURL: URL,
        fileManager: FileManager
    ) throws {
        let entries = try makeEntries(from: directoryURL, fileManager: fileManager)
        guard entries.count <= Int(UInt16.max) else {
            throw ZipArchiveError.unsupportedEntryCount(entries.count)
        }

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        _ = fileManager.createFile(atPath: archiveURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: archiveURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? handle.close() }

        var centralDirectory = Data()
        var localHeaderOffset: UInt64 = 0

        for entry in entries {
            let fileNameData = Data(entry.relativePath.utf8)
            let timestamp = dosTimestamp(for: entry.modifiedAt)

            var localHeader = Data()
            localHeader.appendLittleEndian(UInt32(0x04034B50))
            localHeader.appendLittleEndian(UInt16(20))
            localHeader.appendLittleEndian(utf8Flag)
            localHeader.appendLittleEndian(UInt16(0))
            localHeader.appendLittleEndian(timestamp.time)
            localHeader.appendLittleEndian(timestamp.date)
            localHeader.appendLittleEndian(entry.crc32)
            localHeader.appendLittleEndian(entry.sizeBytes)
            localHeader.appendLittleEndian(entry.sizeBytes)
            localHeader.appendLittleEndian(UInt16(fileNameData.count))
            localHeader.appendLittleEndian(UInt16(0))
            localHeader.append(fileNameData)

            try handle.write(contentsOf: localHeader)
            try handle.write(contentsOf: entry.contents)

            guard let storedOffset = UInt32(exactly: localHeaderOffset) else {
                throw ZipArchiveError.unsupportedArchiveSize
            }

            var centralHeader = Data()
            centralHeader.appendLittleEndian(UInt32(0x02014B50))
            centralHeader.appendLittleEndian(UInt16(20))
            centralHeader.appendLittleEndian(UInt16(20))
            centralHeader.appendLittleEndian(utf8Flag)
            centralHeader.appendLittleEndian(UInt16(0))
            centralHeader.appendLittleEndian(timestamp.time)
            centralHeader.appendLittleEndian(timestamp.date)
            centralHeader.appendLittleEndian(entry.crc32)
            centralHeader.appendLittleEndian(entry.sizeBytes)
            centralHeader.appendLittleEndian(entry.sizeBytes)
            centralHeader.appendLittleEndian(UInt16(fileNameData.count))
            centralHeader.appendLittleEndian(UInt16(0))
            centralHeader.appendLittleEndian(UInt16(0))
            centralHeader.appendLittleEndian(UInt16(0))
            centralHeader.appendLittleEndian(UInt16(0))
            centralHeader.appendLittleEndian(UInt32(0))
            centralHeader.appendLittleEndian(storedOffset)
            centralHeader.append(fileNameData)
            centralDirectory.append(centralHeader)

            localHeaderOffset += UInt64(localHeader.count + entry.contents.count)
        }

        guard
            let centralDirectoryOffset = UInt32(exactly: localHeaderOffset),
            let centralDirectorySize = UInt32(exactly: centralDirectory.count)
        else {
            throw ZipArchiveError.unsupportedArchiveSize
        }

        try handle.write(contentsOf: centralDirectory)

        var endOfCentralDirectory = Data()
        endOfCentralDirectory.appendLittleEndian(UInt32(0x06054B50))
        endOfCentralDirectory.appendLittleEndian(UInt16(0))
        endOfCentralDirectory.appendLittleEndian(UInt16(0))
        endOfCentralDirectory.appendLittleEndian(UInt16(entries.count))
        endOfCentralDirectory.appendLittleEndian(UInt16(entries.count))
        endOfCentralDirectory.appendLittleEndian(centralDirectorySize)
        endOfCentralDirectory.appendLittleEndian(centralDirectoryOffset)
        endOfCentralDirectory.appendLittleEndian(UInt16(0))
        try handle.write(contentsOf: endOfCentralDirectory)
    }

    private static func makeEntries(
        from directoryURL: URL,
        fileManager: FileManager
    ) throws -> [Entry] {
        let rootName = directoryURL.lastPathComponent
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var entries: [Entry] = []
        while let item = enumerator?.nextObject() as? URL {
            let values = try item.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            )
            guard values.isRegularFile == true else {
                continue
            }

            let relativeComponent = item.path.replacingOccurrences(
                of: directoryURL.path + "/",
                with: ""
            )
            let relativePath = "\(rootName)/\(relativeComponent)"
            let contents = try Data(contentsOf: item)
            guard UInt32(exactly: contents.count) != nil else {
                throw ZipArchiveError.unsupportedEntrySize(relativePath)
            }

            entries.append(
                Entry(
                    relativePath: relativePath,
                    contents: contents,
                    modifiedAt: values.contentModificationDate ?? Date(),
                    crc32: crc32(contents)
                )
            )
        }

        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crc32Table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func dosTimestamp(for date: Date) -> DOSTimestamp {
        let components = calendar.dateComponents(
            in: TimeZone(secondsFromGMT: 0) ?? .current,
            from: date
        )
        let year = max(1980, min(components.year ?? 1980, 2107))
        let month = max(1, min(components.month ?? 1, 12))
        let day = max(1, min(components.day ?? 1, 31))
        let hour = max(0, min(components.hour ?? 0, 23))
        let minute = max(0, min(components.minute ?? 0, 59))
        let second = max(0, min(components.second ?? 0, 59))

        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return DOSTimestamp(time: dosTime, date: dosDate)
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(contentsOf: buffer)
        }
    }
}
