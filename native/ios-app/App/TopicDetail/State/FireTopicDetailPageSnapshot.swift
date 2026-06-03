import Foundation

struct FireTopicDetailToolbarState: Equatable {
    let title: String
    let shareURL: URL?
    let isBookmarked: Bool
    let canWriteInteractions: Bool
    let canEditTopic: Bool
    let isPrivateMessageThread: Bool
    let currentNotificationLevel: FireTopicNotificationLevelOption
}

struct FireTopicDetailQuickReplyState: Equatable {
    let isVisible: Bool
    let typingSummary: String?
    let targetSummary: String?
    let placeholder: String
    let draft: String
    let isSubmitting: Bool
    let validationMessage: String?
}

/// Immutable render snapshot for the topic-detail page.
///
/// Produced by `FireTopicDetailSnapshotAssembler` from `FireTopicDetailPageState`.
/// Consumed by `FireTopicDetailFeedController` to drive the `ASCollectionNode`.
///
/// One snapshot instance represents a complete, stable rendering decision for
/// all feed items and page-owned chrome state at a particular moment in time.
struct FireTopicDetailPageSnapshot {

    // MARK: - Feed Items

    /// Ordered list of all feed items in the current snapshot.
    let items: [FireTopicDetailRuntimeItem]

    /// Lookup from post ID to its position in `items` for quick scroll target resolution.
    let replyIndexByPostID: [UInt64: Int]

    // MARK: - Chrome State

    /// Whether the quick reply bar should be visible.
    let canWriteInteractions: Bool

    /// Whether the topic has been fully loaded.
    let hasDetail: Bool

    /// Toolbar chrome rendered by the controller.
    let toolbarState: FireTopicDetailToolbarState

    /// Quick reply chrome rendered by the root node.
    let quickReplyState: FireTopicDetailQuickReplyState

    /// Pending post-number scroll target, or `nil` if none is pending.
    let pendingScrollTarget: UInt32?

    // MARK: - Invalidation Token

    /// Opaque token that changes when any structural feed content changes.
    /// The feed pipeline uses this to skip updates on identical snapshots.
    let invalidationToken: AnyHashable
}

// MARK: - Snapshot Comparison

extension FireTopicDetailPageSnapshot {

    /// Returns `true` if the structural feed items are identical to `other`.
    /// Used by the feed pipeline to choose between no-op and update modes.
    func hasIdenticalItems(to other: FireTopicDetailPageSnapshot) -> Bool {
        guard items.count == other.items.count else { return false }
        return zip(items, other.items).allSatisfy { lhs, rhs in
            lhs.hasSameRenderedContent(as: rhs)
        }
    }

    /// Returns the item IDs that have changed `inPlaceUpdateToken` values
    /// compared to `other`, indicating visible-node reconfiguration is needed.
    func itemIDsNeedingInPlaceUpdate(comparedTo other: FireTopicDetailPageSnapshot) -> Set<String> {
        let selfByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var changed = Set<String>()
        for otherItem in other.items {
            if let selfItem = selfByID[otherItem.id],
               selfItem.needsVisibleNodeUpdate(comparedTo: otherItem) {
                changed.insert(otherItem.id)
            }
        }
        return changed
    }
}
