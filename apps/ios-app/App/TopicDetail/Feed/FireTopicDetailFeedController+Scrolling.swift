import AsyncDisplayKit
import UIKit

@MainActor
extension FireTopicDetailFeedController {
    func handlePendingScrollTarget(
        _ target: UInt32?,
        handledTarget: inout UInt32?,
        onScrollTargetHandled: (UInt32) -> Void
    ) {
        guard let target,
              handledTarget != target,
              let index = currentItems.firstIndex(where: { $0.postNumber == target }) else {
            return
        }
        handledTarget = target
        collectionNode.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredVertically,
            animated: true
        )
        onScrollTargetHandled(target)
    }

    var visibleMaxItem: Int? {
        collectionNode.indexPathsForVisibleItems.map(\.item).max()
    }

    var visibleIndexPaths: Set<IndexPath> {
        Set(collectionNode.indexPathsForVisibleItems)
    }

    var isScrollInteractionActive: Bool {
        collectionNode.view.isDragging
            || collectionNode.view.isDecelerating
            || collectionNode.view.isTracking
    }

    var isViewAttached: Bool {
        collectionNode.view.window != nil
    }

    var contentFitsWithoutScrolling: Bool {
        let visibleHeight = collectionNode.view.bounds.height
            - collectionNode.view.adjustedContentInset.top
            - collectionNode.view.adjustedContentInset.bottom
        guard visibleHeight > 0 else { return false }
        return collectionNode.view.contentSize.height <= visibleHeight + 1
    }

    func replyFooterState(in items: [FireTopicDetailRuntimeItem]) -> FireTopicDetailRuntimeReplyFooterState? {
        guard let item = items.first(where: { $0.kind == .replyFooter }),
              let token = item.contentToken.base as? String else {
            return nil
        }
        return FireTopicDetailRuntimeReplyFooterState.fromContentToken(token)
    }

    func currentVisiblePostNumbers(items: [FireTopicDetailRuntimeItem]) -> Set<UInt32> {
        Set(collectionNode.indexPathsForVisibleItems.compactMap { indexPath -> UInt32? in
            guard indexPath.item < items.count else { return nil }
            return items[indexPath.item].postNumber
        })
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        publishScrollInteractionStateIfNeeded()
        publishTitlePinStateIfNeeded()
        reevaluateVisibleState(forceLoadMoreEvaluation: false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        publishScrollInteractionStateIfNeeded()
        publishTitlePinStateIfNeeded()
        if !decelerate {
            scheduleDeferredScrollIdleCheck()
            reevaluateVisibleState(forceLoadMoreEvaluation: true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        publishScrollInteractionStateIfNeeded()
        publishTitlePinStateIfNeeded()
        scheduleDeferredScrollIdleCheck()
        reevaluateVisibleState(forceLoadMoreEvaluation: true)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        deferredIdleCheckGeneration &+= 1
        publishScrollInteractionStateIfNeeded()
        publishTitlePinStateIfNeeded()
        teardownVisibleTextSelection()
    }

    func performPullToRefresh() {
        Task { [weak self] in
            await self?.onRefresh?()
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Data reload rebuilds Texture nodes; re-assert shell so dark→light
                // never leaves a pure-black collection/root after PTR.
                self.assertFeedShellAppearance()
                self.collectionNode.view.refreshControl?.endRefreshing()
            }
        }
    }

    private func reevaluateVisibleState(forceLoadMoreEvaluation: Bool) {
        visibilityCoordinator?.publishIfChanged(items: currentItems)
        if fireTopicDetailShouldEvaluatePagination(
            forceLoadMoreEvaluation: forceLoadMoreEvaluation,
            isScrollInteractionActive: isScrollInteractionActive
        ) {
            paginationCoordinator?.loadMoreIfNeeded(
                itemCount: currentItems.count,
                visibleMaxItem: visibleMaxItem,
                forceEvaluation: forceLoadMoreEvaluation
            )
        }
        updateVisibleBoostAnimationState()
    }

    private func publishScrollInteractionStateIfNeeded() {
        let isActive = isScrollInteractionActive
        guard lastPublishedScrollInteractionActive != isActive else { return }
        lastPublishedScrollInteractionActive = isActive
        onScrollInteractionChanged?(isActive)
        updateVisibleBoostAnimationState()
    }

    func publishTitlePinStateIfNeeded() {
        let pinned = resolveIsTitlePinned()
        guard lastPublishedTitlePinned != pinned else { return }
        lastPublishedTitlePinned = pinned
        onTitlePinStateChanged?(pinned)
    }

    func resolveIsTitlePinned() -> Bool {
        let scrollView = collectionNode.view
        let visibleTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let headerFrame: CGRect?
        if let headerIndex = currentItems.firstIndex(where: { $0.kind == .header }) {
            headerFrame = collectionNode.collectionViewLayout
                .layoutAttributesForItem(at: IndexPath(item: headerIndex, section: 0))?
                .frame
        } else {
            headerFrame = nil
        }
        return FireTopicDetailToolbarChromeMetrics.isTitlePinned(
            headerFrame: headerFrame,
            visibleTop: visibleTop
        )
    }

    private func scheduleDeferredScrollIdleCheck() {
        deferredIdleCheckGeneration &+= 1
        let generation = deferredIdleCheckGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.deferredIdleCheckGeneration == generation else {
                return
            }
            self.publishScrollInteractionStateIfNeeded()
            self.publishTitlePinStateIfNeeded()
            self.updateVisibleBoostAnimationState()
        }
    }

    private func updateVisibleBoostAnimationState() {
        let enabled = !isScrollInteractionActive
        for indexPath in visibleIndexPaths {
            guard let node = collectionNode.nodeForItem(at: indexPath) as? FirePostCellNode else {
                continue
            }
            node.setBoostAnimationsEnabled(enabled)
        }
    }

    func teardownVisibleTextSelection() {
        for indexPath in visibleIndexPaths {
            (collectionNode.nodeForItem(at: indexPath) as? FirePostCellNode)?.teardownTextSelection()
        }
    }

    @objc
    func handleBackgroundTap() {
        onBackgroundTap?()
        teardownVisibleTextSelection()
    }
}
