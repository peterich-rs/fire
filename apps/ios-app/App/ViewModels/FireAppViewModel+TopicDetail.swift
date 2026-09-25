import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func openTopicDetail(
        topicId: UInt64,
        ownerToken: String,
        topicSlug: String? = nil,
        targetPostNumber: UInt32? = nil,
        bypassCache: Bool,
        forceLoad: Bool,
        trackVisit: Bool,
        allowSuggestedUnreadRoot: Bool
    ) {
        topicDetailStore?.open(
            topicId: topicId,
            ownerToken: ownerToken,
            slug: topicSlug,
            targetPostNumber: targetPostNumber,
            bypassCache: bypassCache,
            forceLoad: forceLoad,
            trackVisit: trackVisit,
            allowSuggestedUnreadRoot: allowSuggestedUnreadRoot
        )
    }

    func clearTopicDetailAnchor(topicId: UInt64) {
        topicDetailStore?.clearScrollTarget(topicId: topicId)
    }

    func topicDetail(for topicId: UInt64) -> TopicDetailUiSnapshotState? {
        topicDetailStore?.snapshot(for: topicId)
    }

    func topicPresenceUsers(for topicId: UInt64) -> [TopicDetailTypingUserState] {
        topicDetailStore?.snapshot(for: topicId)?.composer.typingUsers ?? []
    }

    func isLoadingTopic(topicId: UInt64) -> Bool {
        topicDetailStore?.snapshot(for: topicId)?.phase == .loading
    }

    func isLoadingMoreTopicPosts(topicId: UInt64) -> Bool {
        topicDetailStore?.snapshot(for: topicId)?.isLoadingMore ?? false
    }

    func hasMoreTopicPosts(topicId: UInt64) -> Bool {
        topicDetailStore?.snapshot(for: topicId)?.hasMore ?? false
    }

    func beginTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        topicDetailStore?.open(
            topicId: topicId,
            ownerToken: ownerToken,
            slug: nil,
            targetPostNumber: nil,
            bypassCache: false,
            forceLoad: false,
            trackVisit: true,
            allowSuggestedUnreadRoot: topicDetailStore?.snapshot(for: topicId)?.phase != .ready
        )
    }

    func endTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        topicDetailStore?.close(topicId: topicId, ownerToken: ownerToken)
    }

    func retainedTopicDetailIDs(visibleTopicIDs: Set<UInt64>) -> Set<UInt64> {
        // Owner refcount is the retention source of truth; keep any still-visible
        // list rows so hosts can avoid premature eviction while scrolling.
        (topicDetailStore?.ownedTopicIDs() ?? []).union(visibleTopicIDs)
    }

    // MARK: - Topic detail MessageBus subscription

    func maintainTopicDetailSubscription(topicId: UInt64, ownerToken: String) async {
        _ = (topicId, ownerToken)
    }

    // MARK: - Write interactions

    func isSubmittingReply(topicId: UInt64) -> Bool {
        topicDetailStore?.snapshot(for: topicId)?.composer.isSubmitting ?? false
    }

    func isMutatingPost(postId: UInt64) -> Bool {
        topicDetailStore?.isMutatingPost(postId: postId) ?? false
    }

    func pruneTopicDetailState(retainingVisibleTopicIDs visibleTopicIDs: Set<UInt64>) {
        _ = visibleTopicIDs
    }

    func currentVisibleTopicIDs() -> Set<UInt64> {
        homeFeedStore?.visibleTopicIDs ?? []
    }
}
