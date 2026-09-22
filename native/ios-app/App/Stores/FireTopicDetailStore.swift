import Foundation
import Combine

@MainActor
final class FireTopicDetailStore: ObservableObject {
    @Published private(set) var snapshots: [UInt64: TopicDetailUiSnapshotState] = [:]

    private let appViewModel: FireAppViewModel
    private var handles: [String: TopicDetailSessionHandle] = [:]
    private var sinks: [UInt64: FireTopicDetailSnapshotSink] = [:]
    private var appliedGeneration: [UInt64: UInt64] = [:]
    private var ownersByTopic: [UInt64: Set<String>] = [:]

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func snapshot(for topicId: UInt64) -> TopicDetailUiSnapshotState? {
        snapshots[topicId]
    }

    func ownedTopicIDs() -> Set<UInt64> {
        Set(ownersByTopic.keys)
    }

    func isMutatingPost(postId: UInt64) -> Bool {
        snapshots.values.contains { snapshot in
            snapshot.rows.contains { $0.postId == postId && $0.isMutating }
        }
    }

    func open(
        topicId: UInt64,
        ownerToken: String,
        slug: String?,
        targetPostNumber: UInt32?,
        bypassCache: Bool,
        forceLoad: Bool,
        trackVisit: Bool,
        allowSuggestedUnreadRoot: Bool
    ) {
        guard let sessionStore = appViewModel.currentSessionStore() else {
            return
        }
        let sink = sinks[topicId] ?? FireTopicDetailSnapshotSink()
        sink.store = self
        sinks[topicId] = sink
        let request = TopicDetailOpenRequestState(
            topicId: topicId,
            ownerToken: ownerToken,
            slugHint: slug,
            targetPostNumber: targetPostNumber,
            bypassCache: bypassCache,
            forceLoad: forceLoad,
            trackVisit: trackVisit,
            allowSuggestedUnreadRoot: allowSuggestedUnreadRoot
        )
        guard let handle = try? sessionStore.openTopicDetail(request: request, observer: sink) else {
            return
        }
        handles[handleKey(topicId: topicId, ownerToken: ownerToken)] = handle
        ownersByTopic[topicId, default: []].insert(ownerToken)
    }

    func close(topicId: UInt64, ownerToken: String) {
        let key = handleKey(topicId: topicId, ownerToken: ownerToken)
        handles.removeValue(forKey: key)?.release()
        ownersByTopic[topicId]?.remove(ownerToken)
        if ownersByTopic[topicId]?.isEmpty != false {
            ownersByTopic[topicId] = nil
        }
    }

    func reload(
        topicId: UInt64,
        targetPostNumber: UInt32?,
        forceLoad: Bool,
        trackVisit: Bool,
        allowSuggestedUnreadRoot: Bool
    ) {
        handle(for: topicId)?.reload(
            targetPostNumber: targetPostNumber,
            forceLoad: forceLoad,
            trackVisit: trackVisit,
            allowSuggestedUnreadRoot: allowSuggestedUnreadRoot
        )
    }

    func loadMore(topicId: UInt64) {
        handle(for: topicId)?.loadMore()
    }

    func noteVisiblePosts(topicId: UInt64, postNumbers: Set<UInt32>) {
        handle(for: topicId)?.noteVisiblePosts(postNumbers: Array(postNumbers))
    }

    func noteFilteredFeedTail(topicId: UInt64, itemCount: Int, visibleMaxItem: Int?) {
        handle(for: topicId)?.noteFilteredFeedTail(
            itemCount: UInt32(clamping: itemCount),
            visibleMaxItem: visibleMaxItem.map { UInt32(clamping: $0) }
        )
    }

    func applySession(_ session: SessionState) {
        if session.readiness.canReadAuthenticatedApi {
            return
        }
        let loggedOut = !session.readiness.hasLoginCookie && !session.readiness.hasCurrentUser
        if loggedOut {
            for handle in handles.values {
                handle.release()
            }
            handles.removeAll()
            ownersByTopic.removeAll()
            sinks.removeAll()
            appliedGeneration.removeAll()
            snapshots.removeAll()
            return
        }
        appViewModel.currentSessionStore()?.cancelTopicDetailHttp()
    }

    func noteScrollInteraction(topicId: UInt64, active: Bool) {
        handle(for: topicId)?.noteScrollInteraction(active: active)
    }

    func acknowledgeScrollTarget(topicId: UInt64, postNumber: UInt32) {
        handle(for: topicId)?.acknowledgeScrollTarget(postNumber: postNumber)
    }

    func clearScrollTarget(topicId: UInt64) {
        handle(for: topicId)?.clearScrollTarget()
    }

    func beginReplyTyping(topicId: UInt64) {
        handle(for: topicId)?.beginReplyTyping()
    }

    func endReplyTyping(topicId: UInt64) {
        handle(for: topicId)?.endReplyTyping()
    }

    func reloadAiSummary(topicId: UInt64, skipAgeCheck: Bool) {
        handle(for: topicId)?.reloadAiSummary(skipAgeCheck: skipAgeCheck)
    }

    func loadReplyContext(topicId: UInt64, postId: UInt64) {
        handle(for: topicId)?.loadReplyContext(postId: postId)
    }

    func prepareEdit(topicId: UInt64, postId: UInt64) async throws -> String {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        return try await handle.prepareEdit(postId: postId)
    }

    func submitReply(
        topicId: UInt64,
        raw: String,
        replyToPostNumber: UInt32?,
        scrollToCreated: Bool
    ) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.submitReply(
            raw: raw,
            replyToPostNumber: replyToPostNumber,
            scrollToCreated: scrollToCreated
        )
    }

    func setPostLiked(topicId: UInt64, postId: UInt64, liked: Bool) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.setLiked(postId: postId, liked: liked)
    }

    func togglePostReaction(topicId: UInt64, postId: UInt64, reactionId: String) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.toggleReaction(postId: postId, reactionId: reactionId)
    }

    func votePoll(topicId: UInt64, postId: UInt64, pollName: String, options: [String]) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.votePoll(postId: postId, pollName: pollName, options: options)
    }

    func unvotePoll(topicId: UInt64, postId: UInt64, pollName: String) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.unvotePoll(postId: postId, pollName: pollName)
    }

    func voteTopic(topicId: UInt64, voted: Bool) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.voteTopic(voted: voted)
    }

    func updatePost(topicId: UInt64, postId: UInt64, raw: String, editReason: String?) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.updatePost(postId: postId, raw: raw, editReason: editReason)
    }

    func deletePost(topicId: UInt64, postId: UInt64) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.deletePost(postId: postId)
    }

    func recoverPost(topicId: UInt64, postId: UInt64) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.recoverPost(postId: postId)
    }

    func flagPost(topicId: UInt64, postId: UInt64, flagTypeId: UInt32, message: String?) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.flagPost(postId: postId, flagTypeId: flagTypeId, message: message)
    }

    func ensureFlagTypes(topicId: UInt64) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.ensureFlagTypes()
    }

    func createBookmark(
        topicId: UInt64,
        bookmarkableId: UInt64,
        bookmarkableType: String,
        name: String?,
        reminderAt: String?,
        autoDeletePreference: Int32?
    ) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.createBookmark(
            bookmarkableId: bookmarkableId,
            bookmarkableType: bookmarkableType,
            name: name,
            reminderAt: reminderAt,
            autoDeletePreference: autoDeletePreference
        )
    }

    func updateBookmark(
        topicId: UInt64,
        bookmarkId: UInt64,
        name: String?,
        reminderAt: String?,
        autoDeletePreference: Int32?
    ) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.updateBookmark(
            bookmarkId: bookmarkId,
            name: name,
            reminderAt: reminderAt,
            autoDeletePreference: autoDeletePreference
        )
    }

    func deleteBookmark(topicId: UInt64, bookmarkId: UInt64) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.deleteBookmark(bookmarkId: bookmarkId)
    }

    func setNotificationLevel(topicId: UInt64, level: Int32) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.setNotificationLevel(level: level)
    }

    func updateTopic(topicId: UInt64, title: String, categoryId: UInt64, tags: [String]) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.updateTopic(title: title, categoryId: categoryId, tags: tags)
    }

    func acceptSolution(topicId: UInt64, postId: UInt64, accepted: Bool) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.acceptSolution(postId: postId, accepted: accepted)
    }

    func createBoost(topicId: UInt64, postId: UInt64, raw: String) async throws {
        guard let handle = handle(for: topicId) else {
            throw FireTopicInteractionError.unavailable
        }
        try await handle.createBoost(postId: postId, raw: raw)
    }

    func reportTimings(topicId: UInt64, topicTimeMs: UInt32, timings: [UInt32: UInt32]) async -> Bool {
        guard let handle = handle(for: topicId) else {
            return false
        }
        let entries = timings.map { TopicTimingEntryState(postNumber: $0.key, milliseconds: $0.value) }
        return (try? await handle.reportTimings(topicTimeMs: topicTimeMs, timings: entries)) ?? false
    }

    func reset() {
        appViewModel.currentSessionStore()?.closeAllTopicDetailSessions()
        handles.removeAll()
        ownersByTopic.removeAll()
        sinks.removeAll()
        appliedGeneration.removeAll()
        snapshots.removeAll()
    }

    func apply(_ snapshot: TopicDetailUiSnapshotState) {
        let applied = appliedGeneration[snapshot.topicId] ?? 0
        guard snapshot.generation >= applied else {
            return
        }
        appliedGeneration[snapshot.topicId] = snapshot.generation
        snapshots[snapshot.topicId] = snapshot
        if let patch = snapshot.homeRowPatch {
            appViewModel.applyHomeRowCountPatch(patch)
        }
    }

    private func handle(for topicId: UInt64) -> TopicDetailSessionHandle? {
        guard let owner = ownersByTopic[topicId]?.first else {
            return nil
        }
        return handles[handleKey(topicId: topicId, ownerToken: owner)]
    }

    private func handleKey(topicId: UInt64, ownerToken: String) -> String {
        "\(topicId)|\(ownerToken)"
    }
}

final class FireTopicDetailSnapshotSink: TopicDetailObserver, @unchecked Sendable {
    weak var store: FireTopicDetailStore?

    func onSnapshot(snapshot: TopicDetailUiSnapshotState) {
        let store = store
        Task { @MainActor in
            store?.apply(snapshot)
        }
    }
}
