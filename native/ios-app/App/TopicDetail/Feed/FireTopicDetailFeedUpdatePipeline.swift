import Foundation
import UIKit

let fireTopicDetailAnimatedUpdateItemDeltaLimit = 4

struct FireTopicDetailCollectionUpdatePlan: Equatable {
    let deletions: [IndexPath]
    let insertions: [IndexPath]
    let reloads: [IndexPath]
    let postUpdateReloads: [IndexPath]

    init(
        deletions: [IndexPath],
        insertions: [IndexPath],
        reloads: [IndexPath],
        postUpdateReloads: [IndexPath] = []
    ) {
        self.deletions = deletions
        self.insertions = insertions
        self.reloads = reloads
        self.postUpdateReloads = postUpdateReloads
    }

    var hasBatchUpdates: Bool {
        !deletions.isEmpty || !insertions.isEmpty || !reloads.isEmpty
    }

    var isEmpty: Bool {
        !hasBatchUpdates && postUpdateReloads.isEmpty
    }
}

func fireTopicDetailCollectionUpdatePlan(
    from current: [FireTopicDetailRuntimeItem],
    to next: [FireTopicDetailRuntimeItem]
) -> FireTopicDetailCollectionUpdatePlan {
    let currentIDs = current.map(\.id)
    let nextIDs = next.map(\.id)
    let difference = nextIDs.difference(from: currentIDs)

    let deletions = difference.compactMap { change -> IndexPath? in
        guard case .remove(let offset, _, _) = change else {
            return nil
        }
        return IndexPath(item: offset, section: 0)
    }
    .sorted()

    let insertions = difference.compactMap { change -> IndexPath? in
        guard case .insert(let offset, _, _) = change else {
            return nil
        }
        return IndexPath(item: offset, section: 0)
    }
    .sorted()

    let currentByID = Dictionary(
        uniqueKeysWithValues: current.enumerated().map { index, item in
            (item.id, (index: index, item: item))
        }
    )
    let insertedItems = Set(insertions.map(\.item))
    var reloads: [IndexPath] = []
    var postUpdateReloads: [IndexPath] = []
    for (index, item) in next.enumerated() {
        guard insertedItems.contains(index) == false,
              let previous = currentByID[item.id],
              previous.item.hasSameRenderedContent(as: item) == false else {
            continue
        }

        if previous.index == index {
            reloads.append(IndexPath(item: previous.index, section: 0))
        } else {
            postUpdateReloads.append(IndexPath(item: index, section: 0))
        }
    }

    return FireTopicDetailCollectionUpdatePlan(
        deletions: deletions,
        insertions: insertions,
        reloads: reloads,
        postUpdateReloads: postUpdateReloads
    )
}

struct FireTopicDetailLoadMoreProbe: Equatable {
    let itemCount: Int
    let visibleMaxItem: Int?
}

func fireTopicDetailLoadMoreProbe(
    itemCount: Int,
    visibleMaxItem: Int?
) -> FireTopicDetailLoadMoreProbe {
    FireTopicDetailLoadMoreProbe(
        itemCount: itemCount,
        visibleMaxItem: visibleMaxItem
    )
}

func fireTopicDetailShouldLoadMore(
    itemCount: Int,
    visibleMaxItem: Int?,
    trailingThreshold: Int = 5
) -> Bool {
    guard itemCount > 0, let visibleMaxItem else {
        return false
    }
    return itemCount - visibleMaxItem <= trailingThreshold
}

func fireTopicDetailShouldEvaluatePagination(
    forceLoadMoreEvaluation: Bool,
    isScrollInteractionActive: Bool
) -> Bool {
    forceLoadMoreEvaluation || isScrollInteractionActive
}

func fireTopicDetailVisibleNodeUpdateIndices(
    from current: [FireTopicDetailRuntimeItem],
    to next: [FireTopicDetailRuntimeItem]
) -> [Int] {
    guard current.count == next.count else {
        return []
    }
    return zip(current.indices, zip(current, next)).compactMap { index, pair in
        pair.1.needsVisibleNodeUpdate(comparedTo: pair.0) ? index : nil
    }
}

func fireTopicDetailVisiblePostRelayoutIndexPaths(
    reloads: [IndexPath],
    nextItems: [FireTopicDetailRuntimeItem],
    visibleIndexPaths: Set<IndexPath>,
    isPostNode: (IndexPath) -> Bool
) -> [IndexPath] {
    reloads.filter { indexPath in
        guard visibleIndexPaths.contains(indexPath),
              indexPath.item >= 0,
              indexPath.item < nextItems.count,
              isPostNode(indexPath) else {
            return false
        }
        switch nextItems[indexPath.item].kind {
        case .originalPost, .reply:
            return true
        default:
            return false
        }
    }
}

func fireTopicDetailItemsHaveSameRenderedContent(
    _ lhs: [FireTopicDetailRuntimeItem],
    _ rhs: [FireTopicDetailRuntimeItem]
) -> Bool {
    lhs.count == rhs.count
        && zip(lhs, rhs).allSatisfy { $0.hasSameRenderedContent(as: $1) }
}

func fireTopicDetailCanReuseCurrentSnapshot(
    previousInvalidationToken: AnyHashable?,
    nextInvalidationToken: AnyHashable,
    hasCurrentItems: Bool,
    itemsHaveSameRenderedContent: Bool = true
) -> Bool {
    hasCurrentItems
        && previousInvalidationToken == nextInvalidationToken
        && itemsHaveSameRenderedContent
}

func fireTopicDetailAllowsAnimatedUpdate(
    isViewAttached: Bool,
    isScrollInteractionActive: Bool,
    hasCurrentItems: Bool,
    itemDelta: Int
) -> Bool {
    let absoluteItemDelta = abs(itemDelta)
    return isViewAttached
        && !isScrollInteractionActive
        && hasCurrentItems
        && absoluteItemDelta <= fireTopicDetailAnimatedUpdateItemDeltaLimit
}

@MainActor
final class FireTopicDetailFeedUpdatePipeline {
    private weak var feedController: FireTopicDetailFeedController?
    private weak var paginationCoordinator: FireTopicDetailPaginationCoordinator?
    private weak var visibilityCoordinator: FireTopicDetailVisibilityCoordinator?

    private(set) var currentSnapshot: FireTopicDetailPageSnapshot?
    private(set) var currentConfiguration: FireTopicDetailRuntimeConfiguration?

    init(
        feedController: FireTopicDetailFeedController,
        paginationCoordinator: FireTopicDetailPaginationCoordinator,
        visibilityCoordinator: FireTopicDetailVisibilityCoordinator
    ) {
        self.feedController = feedController
        self.paginationCoordinator = paginationCoordinator
        self.visibilityCoordinator = visibilityCoordinator
    }

    func apply(
        snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        guard let feedController else { return }

        let previousSnapshot = currentSnapshot
        let previousItems = feedController.currentItems
        let previousInvalidationToken = previousSnapshot?.invalidationToken

        paginationCoordinator?.configuration = configuration
        paginationCoordinator?.resetRejectedProbeIfNeeded(
            previousInvalidationToken: previousInvalidationToken,
            nextInvalidationToken: snapshot.invalidationToken
        )

        feedController.applyItems(snapshot.items, configuration: configuration)
        currentSnapshot = snapshot
        currentConfiguration = configuration

        if fireTopicDetailCanReuseCurrentSnapshot(
            previousInvalidationToken: previousInvalidationToken,
            nextInvalidationToken: snapshot.invalidationToken,
            hasCurrentItems: !previousItems.isEmpty,
            itemsHaveSameRenderedContent: previousSnapshot?.hasIdenticalItems(to: snapshot) ?? false
        ) {
            visibilityCoordinator?.handlePendingScrollTargetIfNeeded(
                snapshot.pendingScrollTarget,
                items: snapshot.items
            )
            feedController.prepareLayoutsIfNeeded(
                items: snapshot.items,
                configuration: configuration,
                pendingScrollTarget: snapshot.pendingScrollTarget
            )
            evaluatePaginationAfterSnapshotUpdate(configuration: configuration)
            return
        }

        if let previousSnapshot,
           previousSnapshot.hasIdenticalItems(to: snapshot) {
            let indices = fireTopicDetailVisibleNodeUpdateIndices(
                from: previousItems,
                to: snapshot.items
            )
            if !indices.isEmpty {
                feedController.applyVisibleNodeUpdates(
                    at: indices,
                    nextItems: snapshot.items,
                    configuration: configuration
                )
            }
            visibilityCoordinator?.handlePendingScrollTargetIfNeeded(
                snapshot.pendingScrollTarget,
                items: snapshot.items
            )
            visibilityCoordinator?.publishIfChanged(items: snapshot.items)
            feedController.prepareLayoutsIfNeeded(
                items: snapshot.items,
                configuration: configuration,
                pendingScrollTarget: snapshot.pendingScrollTarget
            )
            evaluatePaginationAfterSnapshotUpdate(configuration: configuration)
            return
        }

        applyCollectionUpdate(
            previousItems: previousItems,
            snapshot: snapshot,
            configuration: configuration
        )
    }

    private func applyCollectionUpdate(
        previousItems: [FireTopicDetailRuntimeItem],
        snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        guard let feedController else { return }

        var updatePlan = fireTopicDetailCollectionUpdatePlan(
            from: previousItems,
            to: snapshot.items
        )

        let inPlacePostRelayouts = fireTopicDetailVisiblePostRelayoutIndexPaths(
            reloads: updatePlan.reloads,
            nextItems: snapshot.items,
            visibleIndexPaths: feedController.visibleIndexPaths,
            isPostNode: { feedController.collectionNode.nodeForItem(at: $0) is FirePostCellNode }
        )
        if !inPlacePostRelayouts.isEmpty {
            let relayoutSet = Set(inPlacePostRelayouts)
            updatePlan = FireTopicDetailCollectionUpdatePlan(
                deletions: updatePlan.deletions,
                insertions: updatePlan.insertions,
                reloads: updatePlan.reloads.filter { !relayoutSet.contains($0) },
                postUpdateReloads: updatePlan.postUpdateReloads
            )
        }

        let finishSnapshotUpdate = { [weak self] in
            guard let self,
                  let feedController = self.feedController else { return }

            if !inPlacePostRelayouts.isEmpty {
                feedController.applyVisiblePostRelayouts(
                    at: inPlacePostRelayouts,
                    items: snapshot.items,
                    configuration: configuration
                )
            }

            self.visibilityCoordinator?.handlePendingScrollTargetIfNeeded(
                snapshot.pendingScrollTarget,
                items: snapshot.items
            )
            self.visibilityCoordinator?.publishIfChanged(
                items: snapshot.items,
                force: previousItems.isEmpty
            )
            self.paginationCoordinator?.recordCollectionUpdateCompleted()
            self.feedController?.prepareLayoutsIfNeeded(
                items: snapshot.items,
                configuration: configuration,
                pendingScrollTarget: snapshot.pendingScrollTarget
            )
            self.evaluatePaginationAfterSnapshotUpdate(configuration: configuration)
        }

        let completion = { [weak feedController] in
            guard !updatePlan.postUpdateReloads.isEmpty else {
                finishSnapshotUpdate()
                return
            }
            guard let feedController else {
                finishSnapshotUpdate()
                return
            }
            feedController.reloadItemsIfNeeded(at: updatePlan.postUpdateReloads) {
                finishSnapshotUpdate()
            }
        }

        guard !updatePlan.isEmpty else {
            completion()
            return
        }

        guard updatePlan.hasBatchUpdates else {
            completion()
            return
        }

        if updatePlan.deletions.isEmpty,
           updatePlan.insertions.isEmpty,
           updatePlan.postUpdateReloads.isEmpty,
           updatePlan.reloads.count == 1,
           let reloadIndexPath = updatePlan.reloads.first,
           reloadIndexPath.item >= 0,
           reloadIndexPath.item < snapshot.items.count,
           snapshot.items[reloadIndexPath.item].kind == .replyFooter {
            feedController.reloadReplyFooterIfNeeded(items: snapshot.items) {
                completion()
            }
            return
        }

        let animated = fireTopicDetailAllowsAnimatedUpdate(
            isViewAttached: feedController.isViewAttached,
            isScrollInteractionActive: feedController.isScrollInteractionActive,
            hasCurrentItems: !previousItems.isEmpty,
            itemDelta: snapshot.items.count - previousItems.count
        )

        feedController.applyCollectionUpdate(
            updatePlan: updatePlan,
            previousItems: previousItems,
            nextItems: snapshot.items,
            animated: animated,
            completion: completion
        )
    }

    private func evaluatePaginationAfterSnapshotUpdate(
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        guard let feedController else { return }
        if configuration.hasMoreTopicPosts,
           !configuration.isLoadingMoreTopicPosts,
           configuration.loadMoreTopicPostsError == nil,
           feedController.contentFitsWithoutScrolling {
            paginationCoordinator?.requestLoadMore(
                forceEvaluation: true,
                allowRetry: false
            )
            return
        }
        paginationCoordinator?.loadMoreIfNeeded(
            itemCount: feedController.currentItems.count,
            visibleMaxItem: feedController.visibleMaxItem,
            forceEvaluation: false
        )
    }
}
