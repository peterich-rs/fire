import Foundation

enum FireAPMPrivacyTier: String, Codable {
    case summary
    case diagnostic
}

enum FireAPMEventType: String, Codable, CaseIterable {
    case launch = "launch"
    case sessionLink = "session_link"
    case scenePhase = "scene_phase"
    case route = "route"
    case breadcrumb = "breadcrumb"
    case span = "span"
    case crash = "crash"
    case metrickitMetric = "metrickit_metric"
    case metrickitDiagnostic = "metrickit_diagnostic"
    case resourceSample = "resource_sample"
    case memoryWarning = "memory_warning"
    case stall = "stall"
}

struct FireAPMBuildInfo: Codable, Equatable {
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String
    let gitSha: String

    static func current(bundle: Bundle = .main) -> FireAPMBuildInfo {
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
            ?? "unknown"
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
        let gitSha = bundle.object(forInfoDictionaryKey: "FireGitSha") as? String
            ?? "unknown"
        return FireAPMBuildInfo(
            appVersion: appVersion,
            buildNumber: buildNumber,
            bundleIdentifier: bundleIdentifier,
            gitSha: gitSha
        )
    }
}

struct FireAPMEventEnvelope: Codable, Identifiable, Equatable {
    let eventID: String
    let eventType: FireAPMEventType
    let capturedAtUnixMs: UInt64
    let launchID: String?
    let diagnosticSessionID: String?
    let appVersion: String
    let buildNumber: String
    let gitSha: String
    let route: String?
    let scenePhase: String?
    let privacyTier: FireAPMPrivacyTier
    let payloadPath: String?
    let payloadSummary: [String: String]

    var id: String { eventID }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case eventType = "event_type"
        case capturedAtUnixMs = "captured_at_unix_ms"
        case launchID = "launch_id"
        case diagnosticSessionID = "diagnostic_session_id"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case gitSha = "git_sha"
        case route
        case scenePhase = "scene_phase"
        case privacyTier = "privacy_tier"
        case payloadPath = "payload_path"
        case payloadSummary = "payload_summary"
    }
}

struct FireAPMBreadcrumb: Codable, Equatable, Identifiable {
    let id: String
    let timestampUnixMs: UInt64
    let level: String
    let target: String
    let message: String

    init(
        id: String = UUID().uuidString.lowercased(),
        timestampUnixMs: UInt64 = FireAPMClock.nowUnixMs(),
        level: String,
        target: String,
        message: String
    ) {
        self.id = id
        self.timestampUnixMs = timestampUnixMs
        self.level = level
        self.target = target
        self.message = message
    }
}

struct FireAPMRuntimeState: Codable, Equatable {
    var launchID: String
    var diagnosticSessionID: String?
    var currentRoute: String?
    var scenePhase: String?
    var activeSpans: [String]
    var breadcrumbs: [FireAPMBreadcrumb]
    var lastUpdatedUnixMs: UInt64

    static func empty(launchID: String) -> FireAPMRuntimeState {
        FireAPMRuntimeState(
            launchID: launchID,
            diagnosticSessionID: nil,
            currentRoute: nil,
            scenePhase: nil,
            activeSpans: [],
            breadcrumbs: [],
            lastUpdatedUnixMs: FireAPMClock.nowUnixMs()
        )
    }
}

struct FireAPMResourceSample: Codable, Equatable {
    let timestampUnixMs: UInt64
    let cpuPercent: Double?
    let residentSizeBytes: UInt64?
    let physicalFootprintBytes: UInt64?
    let thermalState: String
    let batteryState: String
    let lowPowerModeEnabled: Bool
}

struct FireAPMRecentEvent: Identifiable, Equatable {
    let id: String
    let type: FireAPMEventType
    let title: String
    let subtitle: String?
    let timestampUnixMs: UInt64
}

struct FireAPMDiagnosticsSummary: Equatable {
    let currentSample: FireAPMResourceSample?
    let recentCrashes: [FireAPMRecentEvent]
    let recentMetricPayloads: [FireAPMRecentEvent]
    let recentDiagnostics: [FireAPMRecentEvent]
    let recentStalls: [FireAPMRecentEvent]
    let recentEvents: [FireAPMRecentEvent]

    static let empty = FireAPMDiagnosticsSummary(
        currentSample: nil,
        recentCrashes: [],
        recentMetricPayloads: [],
        recentDiagnostics: [],
        recentStalls: [],
        recentEvents: []
    )
}

struct FireAPMSupportBundleExport: Equatable {
    let fileName: String
    let absoluteURL: URL
    let sizeBytes: UInt64
    let createdAtUnixMs: UInt64
}

enum FireAPMSpanName: String, CaseIterable {
    case appLaunchRestoreSession = "app.launch.restore_session"
    case authLoginSync = "auth.login.sync"
    case bootstrapRefresh = "bootstrap.refresh"
    case feedLatestInitialLoad = "feed.latest.initial_load"
    case topicDetailInitialLoad = "topic.detail.initial_load"
    case topicReplySubmit = "topic.reply.submit"
    case notificationsRefresh = "notifications.refresh"
    case messageBusStart = "messagebus.start"

    var signpostName: StaticString {
        switch self {
        case .appLaunchRestoreSession:
            "app.launch.restore_session"
        case .authLoginSync:
            "auth.login.sync"
        case .bootstrapRefresh:
            "bootstrap.refresh"
        case .feedLatestInitialLoad:
            "feed.latest.initial_load"
        case .topicDetailInitialLoad:
            "topic.detail.initial_load"
        case .topicReplySubmit:
            "topic.reply.submit"
        case .notificationsRefresh:
            "notifications.refresh"
        case .messageBusStart:
            "messagebus.start"
        }
    }
}

enum FireAPMClock {
    static func nowUnixMs(date: Date = Date()) -> UInt64 {
        UInt64(max(date.timeIntervalSince1970 * 1_000, 0))
    }
}
