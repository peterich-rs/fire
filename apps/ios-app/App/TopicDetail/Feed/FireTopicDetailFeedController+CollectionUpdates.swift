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
            || changeCount >= fireTopicDetailCollectionUpdateDiagnosticChangeThreshold
            || abs(itemDelta) >= fireTopicDetailCollectionUpdateDiagnosticChangeThreshold
        if shouldLogDiagnostics {
            diagnosticsLogger?.debug(
                "topic detail feed controller apply collection update start topic_id=\(topicId) deletions=\(updatePlan.deletions.count) insertions=\(updatePlan.insertions.count) reloads=\(updatePlan.reloads.count) previous_item_count=\(previousItems.count) next_item_count=\(nextItems.count) animated=\(animated) is_processing_updates=\(collectionNode.isProcessingUpdates) is_view_attached=\(isViewAttached)"
            )
        }
        guard updatePlan.hasBatchUpdates else {
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

        guard collectionNode.isProcessingUpdates == false else {
            diagnosticsLogger?.debug("topic detail feed controller enqueue pending update topic_id=\(topicId)")
            enqueuePendingCollectionUpdate(
                updatePlan: updatePlan,
                previousItems: previousItems,
                nextItems: nextItems,
                animated: animated,
                completion: completion
            )
            return
        }

        if shouldLogDiagnostics {
            diagnosticsLogger?.debug("topic detail feed controller performBatch dispatch topic_id=\(topicId)")
        }
        collectionNode.performBatch(animated: animated, updates: { [self] in
            if shouldLogDiagnostics {
                diagnosticsLogger?.debug("topic detail feed controller performBatch updates start topic_id=\(topicId)")
            }
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
            if shouldLogDiagnostics {
                self?.diagnosticsLogger?.debug("topic detail feed controller performBatch completion topic_id=\(topicId)")
            }
            self?.drainPendingCollectionUpdateIfPossible()
            completion()
        })
    }

    private func enqueuePendingCollectionUpdate(
        updatePlan: FireTopicDetailCollectionUpdatePlan,
        previousItems: [FireTopicDetailRuntimeItem],
        nextItems: [FireTopicDetailRuntimeItem],
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        pendingCollectionUpdate = PendingCollectionUpdate(
            updatePlan: updatePlan,
            previousItems: previousItems,
            nextItems: nextItems,
            animated: animated,
            completion: completion
        )
        pendingCollectionUpdateAttempts = 0
        schedulePendingCollectionUpdateDrain()
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

    private func drainPendingCollectionUpdateIfPossible() {
        guard let pendingCollectionUpdate else {
            pendingCollectionUpdateAttempts = 0
            return
        }

        guard collectionNode.isProcessingUpdates == false else {
            pendingCollectionUpdateAttempts += 1
            guard pendingCollectionUpdateAttempts < Self.maxPendingCollectionUpdateAttempts else {
                self.pendingCollectionUpdate = nil
                self.pendingCollectionUpdateAttempts = 0
                reloadDataCompletingOnNextRunLoop(completion: pendingCollectionUpdate.completion)
                return
            }
            schedulePendingCollectionUpdateDrain()
            return
        }

        self.pendingCollectionUpdate = nil
        self.pendingCollectionUpdateAttempts = 0
        applyCollectionUpdate(
            updatePlan: pendingCollectionUpdate.updatePlan,
            previousItems: pendingCollectionUpdate.previousItems,
            nextItems: pendingCollectionUpdate.nextItems,
            animated: pendingCollectionUpdate.animated,
            completion: pendingCollectionUpdate.completion
        )
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
