import Foundation

struct FireTopicListRefreshScope: Equatable {
    let kind: TopicListKindState
    let categoryId: UInt64?
    let tags: [String]

    var supportsIncrementalMessageBusRefresh: Bool {
        kind == .latest && categoryId == nil && tags.isEmpty
    }
}

enum FireTopicListMessageBusRefreshMode: Equatable {
    case full
    case incremental(topicIDs: [UInt64])
}

struct FireTopicListMessageBusRefreshController {
    static let debounceDelay: Duration = .seconds(1.5)
    static let minimumInterval: Duration = .seconds(30)

    private(set) var scope: FireTopicListRefreshScope?
    private(set) var lastRefreshAt: ContinuousClock.Instant?
    private var pendingTopicIDs: Set<UInt64> = []
    private var requiresFullRefresh = false

    mutating func prepare(for scope: FireTopicListRefreshScope) {
        guard self.scope != scope else { return }
        self.scope = scope
        lastRefreshAt = nil
        pendingTopicIDs.removeAll()
        requiresFullRefresh = false
    }

    mutating func reset() {
        scope = nil
        lastRefreshAt = nil
        pendingTopicIDs.removeAll()
        requiresFullRefresh = false
    }

    mutating func clearPending(for scope: FireTopicListRefreshScope) {
        prepare(for: scope)
        pendingTopicIDs.removeAll()
        requiresFullRefresh = false
    }

    mutating func register(
        event: MessageBusEventState,
        for scope: FireTopicListRefreshScope,
        now: ContinuousClock.Instant,
        allowIncremental: Bool
    ) -> Duration? {
        prepare(for: scope)
        guard event.kind == .topicList, event.topicListKind == scope.kind else {
            return nil
        }

        if shouldIncrementallyRefresh(
            event: event,
            scope: scope,
            allowIncremental: allowIncremental
        ) {
            if let topicID = event.topicId {
                pendingTopicIDs.insert(topicID)
            } else {
                requiresFullRefresh = true
            }
        } else {
            requiresFullRefresh = true
        }

        return scheduledDelay(now: now)
    }

    mutating func takePendingRefresh(
        for scope: FireTopicListRefreshScope
    ) -> FireTopicListMessageBusRefreshMode? {
        prepare(for: scope)

        if requiresFullRefresh {
            requiresFullRefresh = false
            pendingTopicIDs.removeAll()
            return .full
        }

        guard !pendingTopicIDs.isEmpty else {
            return nil
        }

        let topicIDs = pendingTopicIDs.sorted()
        pendingTopicIDs.removeAll()
        return .incremental(topicIDs: topicIDs)
    }

    mutating func markRefreshCompleted(
        for scope: FireTopicListRefreshScope,
        at now: ContinuousClock.Instant
    ) {
        prepare(for: scope)
        lastRefreshAt = now
    }

    private func shouldIncrementallyRefresh(
        event: MessageBusEventState,
        scope: FireTopicListRefreshScope,
        allowIncremental: Bool
    ) -> Bool {
        guard allowIncremental, scope.supportsIncrementalMessageBusRefresh else {
            return false
        }
        guard let topicID = event.topicId, topicID > 0 else {
            return false
        }
        return event.messageType?.lowercased() == "latest"
    }

    private func scheduledDelay(now: ContinuousClock.Instant) -> Duration {
        guard let lastRefreshAt else {
            return Self.debounceDelay
        }

        let elapsed = lastRefreshAt.duration(to: now)
        return max(Self.debounceDelay, Self.minimumInterval - elapsed)
    }
}

enum FireTopicListMessageBusRefreshMerger {
    static func merge(
        existing: [TopicRowState],
        incoming: [TopicRowState]
    ) -> [TopicRowState] {
        guard !incoming.isEmpty else {
            return existing
        }

        let incomingIDs = Set(incoming.map(\.topic.id))
        let remaining = existing.filter { !incomingIDs.contains($0.topic.id) }
        return incoming + remaining
    }
}
