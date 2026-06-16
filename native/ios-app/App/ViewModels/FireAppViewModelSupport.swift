import Foundation

enum FireLoginPreparationError: LocalizedError {
    case invalidResponse
    case cloudflareVerificationIncomplete

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Unable to prepare login network access."
        case .cloudflareVerificationIncomplete:
            "Cloudflare verification did not complete. Try login again."
        }
    }
}

enum FireDiagnosticsAccessError: LocalizedError {
    case unavailable
    case traceNotFound

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Diagnostics are unavailable because the shared session store was not initialized."
        case .traceNotFound:
            "The selected network request trace is no longer available."
        }
    }
}

enum FireTopicInteractionError: LocalizedError {
    case unavailable
    case requiresAuthenticatedWrite
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "互动能力暂时不可用。"
        case .requiresAuthenticatedWrite:
            "当前登录会话还不能执行需要登录的写入操作。"
        case .emptyReply:
            "回复内容不能为空。"
        }
    }
}

enum FireAuthPresentationState: Identifiable, Equatable {
    case login

    var id: String {
        switch self {
        case .login:
            return "login"
        }
    }
}

struct FireCloudflareRecoveryCookieSnapshot: Equatable {
    let hasAuthCookies: Bool
    let authFingerprint: String
    let cfClearanceFingerprint: String?

    var hasCloudflareClearance: Bool {
        cfClearanceFingerprint != nil
    }

    func hasNewCloudflareClearance(comparedTo baseline: FireCloudflareRecoveryCookieSnapshot) -> Bool {
        guard let cfClearanceFingerprint else {
            return false
        }
        return cfClearanceFingerprint != baseline.cfClearanceFingerprint
    }

    var diagnosticSummary: String {
        let cfSummary = cfClearanceFingerprint.map { "present:\($0)" } ?? "missing"
        return "auth=\(hasAuthCookies) auth_fp=\(authFingerprint) cf_clearance=\(cfSummary)"
    }
}

final class FireAppStateRefreshCoordinator: AppStateRefreshHandler, @unchecked Sendable {
    private static let deliveryBatchSize = 4

    private let lock = NSLock()
    private let onEvent: (AppStateRefreshEventState) -> Void
    private var pendingEvents: [AppStateRefreshEventState] = []
    private var isDraining = false

    init(onEvent: @escaping (AppStateRefreshEventState) -> Void) {
        self.onEvent = onEvent
    }

    func onAppStateRefreshEvent(event: AppStateRefreshEventState) {
        let shouldScheduleDrain = lock.withLock {
            pendingEvents.append(event)
            guard !isDraining else {
                return false
            }
            isDraining = true
            return true
        }

        guard shouldScheduleDrain else {
            return
        }

        Task { [weak self] in
            await self?.drainPendingEvents()
        }
    }

    private func dequeueBatch() -> [AppStateRefreshEventState] {
        lock.withLock {
            guard !pendingEvents.isEmpty else {
                isDraining = false
                return []
            }

            let count = min(Self.deliveryBatchSize, pendingEvents.count)
            let batch = Array(pendingEvents.prefix(count))
            pendingEvents.removeFirst(count)
            return batch
        }
    }

    private func drainPendingEvents() async {
        while true {
            let batch = dequeueBatch()
            guard !batch.isEmpty else {
                return
            }

            let handler = onEvent
            await MainActor.run {
                for event in batch {
                    handler(event)
                }
            }
        }
    }
}

final class FireStateObserverCoordinator: StateObserver, @unchecked Sendable {
    private let onSession: @MainActor (SessionState) async -> Void
    private let onTopicList: @MainActor (TopicListState) async -> Void
    private let onNotificationCenter: @MainActor (NotificationCenterState) async -> Void

    init(
        onSession: @escaping @MainActor (SessionState) async -> Void,
        onTopicList: @escaping @MainActor (TopicListState) async -> Void,
        onNotificationCenter: @escaping @MainActor (NotificationCenterState) async -> Void
    ) {
        self.onSession = onSession
        self.onTopicList = onTopicList
        self.onNotificationCenter = onNotificationCenter
    }

    func onSessionSnapshot(snapshot: SessionState) {
        Task { @MainActor in
            await onSession(snapshot)
        }
    }

    func onTopicListSnapshot(snapshot: TopicListState) {
        Task { @MainActor in
            await onTopicList(snapshot)
        }
    }

    func onNotificationCenterSnapshot(snapshot: NotificationCenterState) {
        Task { @MainActor in
            await onNotificationCenter(snapshot)
        }
    }
}

struct CachedLoginSyncReadiness {
    let currentURL: String?
    let readiness: FireLoginSyncReadiness
}

struct FireTopicDetailWindowState {
    static let maxWindowSize = 200

    var anchorPostNumber: UInt32?
    var requestedRange: Range<Int>
    var loadedIndices: IndexSet
    var loadedPostNumbers: Set<UInt32> = []
    var exhaustedPostIDs: Set<UInt64> = []
    var pendingScrollTarget: UInt32?

    var activeAnchorPostNumber: UInt32? {
        pendingScrollTarget ?? anchorPostNumber
    }

    func clearingTransientAnchor() -> FireTopicDetailWindowState {
        var window = self
        window.anchorPostNumber = nil
        window.pendingScrollTarget = nil
        return window
    }
}

struct FireTopicDetailRequest: Equatable {
    enum Reason: Equatable {
        case initialOpen
        case routeAnchor
        case visibleRangeExpansion
        case userRefresh
        case messageBusRefresh
    }

    var anchorPostNumber: UInt32?
    var reason: Reason
    var forceNetwork: Bool = false
}

enum FireSearchScope: String, CaseIterable, Identifiable {
    case all
    case topic
    case post
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .topic: "话题"
        case .post: "帖子"
        case .user: "用户"
        }
    }

    var typeFilter: SearchTypeFilterState? {
        switch self {
        case .all: nil
        case .topic: .topic
        case .post: .post
        case .user: .user
        }
    }
}
