import AsyncDisplayKit
import UIKit

@MainActor
extension FireTopicDetailFeedController {
    func applyCollectionUpdate(
        updatePlan: FireTopicDetailCollectionUpdatePlan,
        previousItems: [FireTopicDetailRuntimeItem],
        nextItems: [FireTopicDetailRuntimeItem],
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        latestItems = nextItems
        commitStagedItems(
            updatePlan: updatePlan,
            previousItems: previousItems,
            nextItems: nextItems,
            animated: animated,
            completion: completion
        )
    }

    func commitIfPossible() {
        guard let latestItems else { return }
        let decision = fireTopicDetailCommitDecision(
            committed: currentItems,
            latest: latestItems,
            isCommitting: isCommittingCollectionUpdate
        )
        switch decision {
        case .noOp:
            adoptCommittedItems(latestItems)
            self.latestItems = nil
        case .applyInPlace:
            adoptCommittedItems(latestItems)
            self.latestItems = nil
        case .holdWhileBusy:
            schedulePendingCollectionUpdateDrain()
        case .commitBatch(let plan):
            let animated = fireTopicDetailAllowsAnimatedUpdate(
                isViewAttached: isViewAttached,
                isScrollInteractionActive: isScrollInteractionActive,
                hasCurrentItems: !currentItems.isEmpty,
                itemDelta: latestItems.count - currentItems.count
            )
            let completion = pendingCommitCompletion
            pendingCommitCompletion = nil
            commitStagedItems(
                updatePlan: plan,
                previousItems: currentItems,
                nextItems: latestItems,
                animated: animated,
                completion: completion ?? {}
            )
        }
    }

    private func commitStagedItems(
        updatePlan: FireTopicDetailCollectionUpdatePlan,
        previousItems: [FireTopicDetailRuntimeItem],
        nextItems: [FireTopicDetailRuntimeItem],
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        let topicId = diagnosticTopicId
        let itemDelta = nextItems.count - previousItems.count
        let changeCount =
            updatePlan.deletions.count
            + updatePlan.insertions.count
            + updatePlan.reloads.count
            + updatePlan.postUpdateReloads.count
        let shouldLogDiagnostics =
            previousItems.isEmpty
            || !isViewAttached
            || collectionNode.isProcessingUpdates
            || isCommittingCollectionUpdate
            || changeCount >= fireTopicDetailCollectionUpdateDiagnosticChangeThreshold
            || abs(itemDelta) >= fireTopicDetailCollectionUpdateDiagnosticChangeThreshold
        if shouldLogDiagnostics {
            diagnosticsLogger?.debug(
                "topic detail feed controller apply collection update start topic_id=\(topicId) deletions=\(updatePlan.deletions.count) insertions=\(updatePlan.insertions.count) reloads=\(updatePlan.reloads.count) previous_item_count=\(previousItems.count) next_item_count=\(nextItems.count) animated=\(animated) is_processing_updates=\(collectionNode.isProcessingUpdates) is_view_attached=\(isViewAttached) is_committing=\(isCommittingCollectionUpdate)"
            )
        }

        switch fireTopicDetailCommitDecision(
            committed: previousItems,
            latest: nextItems,
            isCommitting: isCommittingCollectionUpdate || collectionNode.isProcessingUpdates
        ) {
        case .noOp:
            adoptCommittedItems(nextItems)
            latestItems = nil
            completion()
            return
        case .applyInPlace:
            adoptCommittedItems(nextItems)
            latestItems = nil
            completion()
            return
        case .holdWhileBusy:
            latestItems = nextItems
            pendingCommitCompletion = completion
            if shouldLogDiagnostics {
                diagnosticsLogger?.debug("topic detail feed controller enqueue coalesced update topic_id=\(topicId)")
            }
            schedulePendingCollectionUpdateDrain()
            return
        case .commitBatch:
            break
        }

        guard updatePlan.hasBatchUpdates else {
            adoptCommittedItems(nextItems)
            latestItems = nil
            if shouldLogDiagnostics {
                diagnosticsLogger?.debug("topic detail feed controller apply collection update no_batch topic_id=\(topicId)")
            }
            completion()
            return
        }

        if fireTopicDetailShouldBypassTextureReloadCompletion(
            previousItemsIsEmpty: previousItems.isEmpty,
            isViewAttached: collectionNode.view.window != nil
        ) {
            if shouldLogDiagnostics {
                diagnosticsLogger?.debug(
                    "topic detail feed controller reloadData bypass start topic_id=\(topicId) previous_items_empty=\(previousItems.isEmpty) is_view_attached=\(isViewAttached)"
                )
            }
            adoptCommittedItems(nextItems)
            latestItems = nil
            reloadDataCompletingOnNextRunLoop { [weak self] in
                if shouldLogDiagnostics {
                    self?.diagnosticsLogger?.debug(
                        "topic detail feed controller reloadData bypass completion topic_id=\(topicId)"
                    )
                }
                self?.drainPendingCollectionUpdateIfPossible()
                completion()
            }
            return
        }

        if shouldLogDiagnostics {
            diagnosticsLogger?.debug("topic detail feed controller performBatch dispatch topic_id=\(topicId)")
        }
        isCommittingCollectionUpdate = true
        collectionNode.performBatch(animated: animated, updates: { [self] in
            if shouldLogDiagnostics {
                diagnosticsLogger?.debug("topic detail feed controller performBatch updates start topic_id=\(topicId)")
            }
            adoptCommittedItems(nextItems)
            if !updatePlan.deletions.isEmpty {
                collectionNode.deleteItems(at: updatePlan.deletions)
            }
            if !updatePlan.insertions.isEmpty {
                collectionNode.insertItems(at: updatePlan.insertions)
            }
            if !updatePlan.reloads.isEmpty {
                collectionNode.reloadItems(at: updatePlan.reloads)
            }
            if shouldLogDiagnostics {
                diagnosticsLogger?.debug("topic detail feed controller performBatch updates complete topic_id=\(topicId)")
            }
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.isCommittingCollectionUpdate = false
            if shouldLogDiagnostics {
                self.diagnosticsLogger?.debug("topic detail feed controller performBatch completion topic_id=\(topicId)")
            }
            if self.latestItems == nil || self.latestItems?.map(\.id) == nextItems.map(\.id) {
                self.latestItems = nil
            }
            self.drainPendingCollectionUpdateIfPossible()
            completion()
        })
    }

    private func adoptCommittedItems(_ items: [FireTopicDetailRuntimeItem]) {
        currentItems = items
        DispatchQueue.main.async { [weak self] in
            self?.publishTitlePinStateIfNeeded()
        }
    }

    private func schedulePendingCollectionUpdateDrain() {
        guard !isPendingCollectionUpdateDrainScheduled else { return }
        isPendingCollectionUpdateDrainScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collectionUpdateRetryDelay) { [weak self] in
            guard let self else { return }
            self.isPendingCollectionUpdateDrainScheduled = false
            self.drainPendingCollectionUpdateIfPossible()
        }
    }

    func drainPendingCollectionUpdateIfPossible() {
        guard let latestItems else {
            pendingCollectionUpdateAttempts = 0
            return
        }
        guard !isCommittingCollectionUpdate, collectionNode.isProcessingUpdates == false else {
            pendingCollectionUpdateAttempts += 1
            schedulePendingCollectionUpdateDrain()
            return
        }
        pendingCollectionUpdateAttempts = 0
        commitIfPossible()
    }

    private func reloadDataCompletingOnNextRunLoop(completion: @escaping () -> Void) {
        let topicId = diagnosticTopicId
        diagnosticsLogger?.debug("topic detail feed controller reloadData call start topic_id=\(topicId)")
        collectionNode.reloadData()
        diagnosticsLogger?.debug("topic detail feed controller reloadData call returned topic_id=\(topicId)")
        DispatchQueue.main.async {
            completion()
        }
    }

    private var diagnosticTopicId: UInt64 {
        currentConfiguration?.row.topic.id ?? 0
    }
}
