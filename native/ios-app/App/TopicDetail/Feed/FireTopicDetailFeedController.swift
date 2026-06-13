import AsyncDisplayKit
import UIKit

@MainActor
final class FireTopicDetailFeedController: NSObject,
    @preconcurrency ASCollectionDataSource,
    @preconcurrency ASCollectionDelegate,
    UIScrollViewDelegate
{
    private struct PendingCollectionUpdate {
        let updatePlan: FireTopicDetailCollectionUpdatePlan
        let previousItems: [FireTopicDetailRuntimeItem]
        let nextItems: [FireTopicDetailRuntimeItem]
        let animated: Bool
        let completion: () -> Void
    }

    private static let collectionUpdateRetryDelay: TimeInterval = 0.05
    private static let maxPendingCollectionUpdateAttempts = 8
    private static let maxReplyFooterReloadAttempts = 8

    let collectionNode = ASCollectionNode(
        collectionViewLayout: FireTopicDetailFeedController.makeCollectionLayout()
    )

    private(set) var currentItems: [FireTopicDetailRuntimeItem] = []
    private var currentConfiguration: FireTopicDetailRuntimeConfiguration?
    private var lastLayoutContentWidth: CGFloat?
    private var pendingCollectionUpdate: PendingCollectionUpdate?
    private var pendingCollectionUpdateAttempts = 0
    private var isPendingCollectionUpdateDrainScheduled = false
    private let cellFactory = FireTopicDetailFeedCellFactory()
    private lazy var dismissKeyboardTapGestureRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleBackgroundTap)
    )

    weak var paginationCoordinator: FireTopicDetailPaginationCoordinator?
    weak var visibilityCoordinator: FireTopicDetailVisibilityCoordinator?
    var layoutManager: FirePostLayoutManager?
    var diagnosticsLogger: FireHostLogger?

    var onRefresh: (() async -> Void)?
    var onBackgroundTap: (() -> Void)?
    var onScrollInteractionChanged: ((Bool) -> Void)?
    private var lastPublishedScrollInteractionActive = false
    private var deferredIdleCheckGeneration: UInt64 = 0

    func setup() {
        collectionNode.dataSource = self
        collectionNode.delegate = self
        configureTextureRanges()

        collectionNode.backgroundColor = .systemBackground
        collectionNode.view.backgroundColor = .systemBackground
        collectionNode.view.alwaysBounceVertical = true
        collectionNode.view.showsVerticalScrollIndicator = false
        collectionNode.view.showsHorizontalScrollIndicator = false
        collectionNode.view.keyboardDismissMode = .interactive
        dismissKeyboardTapGestureRecognizer.cancelsTouchesInView = false
        collectionNode.view.addGestureRecognizer(dismissKeyboardTapGestureRecognizer)

        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.performPullToRefresh()
        }, for: .valueChanged)
        collectionNode.view.refreshControl = refreshControl

        cellFactory.layoutWidthProvider = { [weak self] in
            self?.layoutContentWidth() ?? 1
        }
        cellFactory.onRequestLoadMore = { [weak self] in
            guard let self else { return }
            self.paginationCoordinator?.requestLoadMore(
                forceEvaluation: true,
                allowRetry: true
            )
        }
    }

    func layoutContentWidth(proposedWidth: CGFloat? = nil) -> CGFloat {
        let adjustedBoundsWidth = collectionNode.view.bounds.width
            - collectionNode.view.adjustedContentInset.left
            - collectionNode.view.adjustedContentInset.right
        if adjustedBoundsWidth > 0 {
            return adjustedBoundsWidth
        }
        return max(proposedWidth ?? collectionNode.view.bounds.width, 1)
    }

    func invalidateLayoutIfWidthChanged() {
        let width = layoutContentWidth()
        guard width > 1 else { return }
        if let lastLayoutContentWidth,
           abs(lastLayoutContentWidth - width) < 0.5 {
            return
        }
        let hadMeasuredWidth = lastLayoutContentWidth != nil
        lastLayoutContentWidth = width
        collectionNode.view.collectionViewLayout.invalidateLayout()
        if let layoutManager {
            layoutManager.updateTraitSignature(
                FirePostLayoutTraitSignature(
                    contentWidthPixels: Int(width.rounded(.toNearestOrEven)),
                    contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue
                )
            )
        }
        if hadMeasuredWidth, !currentItems.isEmpty {
            collectionNode.reloadData()
        }
    }

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

    func applyVisibleNodeUpdates(
        at indices: [Int],
        nextItems: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        for index in indices {
            guard index < nextItems.count,
                  let postContext = configuration.postContext(for: nextItems[index]),
                  let node = collectionNode.nodeForItem(at: IndexPath(item: index, section: 0)) as? FirePostCellNode else {
                continue
            }
            configurePostCellNode(node, with: postContext, configuration: configuration)
            node.invalidateCalculatedLayout()
            node.setNeedsLayout()
        }
    }

    func applyVisiblePostRelayouts(
        at indexPaths: [IndexPath],
        items: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        for indexPath in indexPaths {
            guard indexPath.item >= 0,
                  indexPath.item < items.count,
                  let postContext = configuration.postContext(for: items[indexPath.item]),
                  let node = collectionNode.nodeForItem(at: indexPath) as? FirePostCellNode else {
                continue
            }
            configurePostCellNode(node, with: postContext, configuration: configuration)
            node.invalidateCalculatedLayout()
            node.setNeedsLayout()
        }
    }

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

    func reloadReplyFooterIfNeeded(items: [FireTopicDetailRuntimeItem], completion: (() -> Void)? = nil) {
        reloadReplyFooterIfNeeded(items: items, attempt: 0, completion: completion)
    }

    func reloadItemsIfNeeded(at indexPaths: [IndexPath], completion: (() -> Void)? = nil) {
        reloadItemsIfNeeded(at: indexPaths, attempt: 0, completion: completion)
    }

    private func reloadReplyFooterIfNeeded(
        items: [FireTopicDetailRuntimeItem],
        attempt: Int,
        completion: (() -> Void)?
    ) {
        guard let indexPath = replyFooterIndexPath(in: items) else {
            completion?()
            return
        }
        if collectionNode.isProcessingUpdates {
            guard attempt < Self.maxReplyFooterReloadAttempts else {
                collectionNode.reloadData(completion: completion)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.collectionUpdateRetryDelay) { [weak self] in
                self?.reloadReplyFooterIfNeeded(
                    items: items,
                    attempt: attempt + 1,
                    completion: completion
                )
            }
            return
        }
        collectionNode.reloadItems(at: [indexPath])
        completion?()
    }

    private func reloadItemsIfNeeded(
        at indexPaths: [IndexPath],
        attempt: Int,
        completion: (() -> Void)?
    ) {
        let validIndexPaths = Array(Set(indexPaths.filter { indexPath in
            indexPath.section == 0
                && indexPath.item >= 0
                && indexPath.item < currentItems.count
        })).sorted()

        guard !validIndexPaths.isEmpty,
              collectionNode.view.window != nil else {
            completion?()
            return
        }

        if collectionNode.isProcessingUpdates {
            guard attempt < Self.maxReplyFooterReloadAttempts else {
                collectionNode.reloadData(completion: completion)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.collectionUpdateRetryDelay) { [weak self] in
                self?.reloadItemsIfNeeded(
                    at: validIndexPaths,
                    attempt: attempt + 1,
                    completion: completion
                )
            }
            return
        }

        collectionNode.reloadItems(at: validIndexPaths)
        completion?()
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

    func prepareLayoutsIfNeeded(
        items: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration,
        pendingScrollTarget: UInt32?
    ) {
        guard let layoutManager else { return }

        let width = layoutContentWidth()
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: Int(width.rounded(.toNearestOrEven)),
            contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue
        )
        layoutManager.updateTraitSignature(trait)

        let visibleIndices = collectionNode.indexPathsForVisibleItems.map(\.item)
        var candidateIndices = Set<Int>()
        for visibleIndex in visibleIndices {
            let lowerBound = max(visibleIndex - 6, 0)
            let upperBound = min(visibleIndex + 6, items.count - 1)
            for index in lowerBound...upperBound {
                candidateIndices.insert(index)
            }
        }
        if candidateIndices.isEmpty {
            for index in items.indices.prefix(12) {
                candidateIndices.insert(index)
            }
        }
        if let pendingScrollTarget,
           let targetIndex = items.firstIndex(where: { $0.postNumber == pendingScrollTarget }) {
            candidateIndices.insert(targetIndex)
        }

        for index in candidateIndices.sorted() {
            guard index >= 0,
                  index < items.count,
                  let postContext = configuration.postContext(for: items[index]) else {
                continue
            }
            let key = makeLayoutKey(for: postContext, trait: trait)
            layoutManager.enqueueCalculation(
                key: key,
                attributedText: postContext.renderContent.attributedText,
                plainText: postContext.renderContent.plainText,
                images: postContext.renderContent.imageAttachments,
                polls: FirePostPollRenderModel.models(from: postContext.post.polls),
                boostLines: FirePostBoostDisplay.fixedDisplayLines(
                    for: postContext.post.boosts,
                    depth: postContext.depth,
                    textExpansionState: postContext.textExpansionState,
                    hasBodyTextTarget: postContext.renderContent.hasBoostBarrageTextTarget
                ),
                trait: trait
            )
        }
    }

    func applyPublishedLayoutRevision(
        publishedKeys: Set<FirePostCellLayoutKey>,
        items: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        guard let layoutManager, !publishedKeys.isEmpty else { return }

        let width = layoutContentWidth()
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: Int(width.rounded(.toNearestOrEven)),
            contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue
        )

        for indexPath in visibleIndexPaths {
            guard indexPath.item >= 0,
                  indexPath.item < items.count,
                  let postContext = configuration.postContext(for: items[indexPath.item]) else {
                continue
            }

            let key = makeLayoutKey(for: postContext, trait: trait)
            guard publishedKeys.contains(key),
                  layoutManager.cachedLayout(forKey: key) != nil,
                  let node = collectionNode.nodeForItem(at: indexPath) as? FirePostCellNode else {
                continue
            }

            configurePostCellNode(node, with: postContext, configuration: configuration)
            node.invalidateCalculatedLayout()
            node.setNeedsLayout()
        }
    }

    func numberOfSections(in collectionNode: ASCollectionNode) -> Int { 1 }

    func collectionNode(
        _ collectionNode: ASCollectionNode,
        numberOfItemsInSection section: Int
    ) -> Int {
        currentItems.count
    }

    func collectionNode(
        _ collectionNode: ASCollectionNode,
        nodeBlockForItemAt indexPath: IndexPath
    ) -> ASCellNodeBlock {
        guard indexPath.item < currentItems.count else {
            return { ASCellNode() }
        }

        let item = currentItems[indexPath.item]
        guard let configuration = currentConfiguration else {
            return { ASCellNode() }
        }

        let capturedLayoutWidth = layoutContentWidth()
        let capturedTrait = FirePostLayoutTraitSignature(
            contentWidthPixels: Int(capturedLayoutWidth.rounded(.toNearestOrEven)),
            contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue
        )
        let capturedPostContext = configuration.postContext(for: item)
        let capturedLayoutKey = capturedPostContext.map { makeLayoutKey(for: $0, trait: capturedTrait) }
        let capturedCallbacks = postCallbacks(configuration: configuration)
        let capturedConfiguration = configuration
        let capturedLayoutManager = layoutManager
        let capturedCellFactory = cellFactory
        let capturedBoostAnimationsEnabled = !isScrollInteractionActive

        return {
            if let postContext = capturedPostContext {
                let node = FirePostCellNode()
                node.configure(
                    payload: FirePostCellRenderPayload(
                        post: postContext.post,
                        renderContent: postContext.renderContent,
                        baseURLString: capturedConfiguration.baseURLString,
                        canWriteInteractions: capturedConfiguration.canWriteInteractions,
                        isMutating: capturedConfiguration.isMutatingPost(postContext.post.id),
                        replyContext: postContext.replyContext,
                        replyTargetPostNumber: postContext.replyTargetPostNumber,
                        replyShortcutCount: postContext.replyShortcutCount,
                        isLoadingReplyContext: postContext.isLoadingReplyContext,
                        textExpansionState: postContext.textExpansionState,
                        isSearchHighlighted: capturedConfiguration.isSearchHighlighted(postID: postContext.post.id),
                        showsDivider: postContext.showsDivider,
                        layoutWidth: capturedLayoutWidth,
                        boostAnimationsEnabled: capturedBoostAnimationsEnabled,
                        layout: capturedLayoutKey.flatMap { capturedLayoutManager?.cachedLayout(forKey: $0) },
                        layoutKey: capturedLayoutKey
                    ),
                    callbacks: capturedCallbacks,
                    depth: postContext.depth,
                    showsThreadLine: postContext.showsThreadLine,
                    showsDivider: postContext.showsDivider
                )
                return node
            }
            return capturedCellFactory.makeCellNode(
                for: item,
                configuration: capturedConfiguration
            )
        }
    }

    func collectionNode(
        _ collectionNode: ASCollectionNode,
        constrainedSizeForItemAt indexPath: IndexPath
    ) -> ASSizeRange {
        let width = layoutContentWidth()
        return ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
    }

    func collectionNode(
        _ collectionNode: ASCollectionNode,
        willBeginBatchFetchWith context: ASBatchContext
    ) {
        context.completeBatchFetching(true)
    }

    func shouldBatchFetch(for collectionNode: ASCollectionNode) -> Bool {
        return false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        publishScrollInteractionStateIfNeeded()
        reevaluateVisibleState(forceLoadMoreEvaluation: false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        publishScrollInteractionStateIfNeeded()
        if !decelerate {
            scheduleDeferredScrollIdleCheck()
            reevaluateVisibleState(forceLoadMoreEvaluation: true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        publishScrollInteractionStateIfNeeded()
        scheduleDeferredScrollIdleCheck()
        reevaluateVisibleState(forceLoadMoreEvaluation: true)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        deferredIdleCheckGeneration &+= 1
        publishScrollInteractionStateIfNeeded()
    }

    func applyItems(
        _ items: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        currentItems = items
        currentConfiguration = configuration
        cellFactory.configuration = configuration
    }

    private func postCallbacks(configuration: FireTopicDetailRuntimeConfiguration) -> FirePostCellCallbacks {
        FirePostCellCallbacks(
            onLinkTapped: configuration.onLinkTapped,
            onOpenProfile: configuration.onOpenProfile,
            onOpenImage: configuration.onOpenImage,
            onToggleLike: configuration.onToggleLike,
            onSelectReaction: configuration.onSelectReaction,
            onOpenReactionPicker: configuration.onOpenReactionPicker,
            onQuotePost: configuration.onQuotePost,
            onEditPost: configuration.onEditPost,
            onBookmarkPost: configuration.onBookmarkPost,
            onDeletePost: configuration.onDeletePost,
            onRecoverPost: configuration.onRecoverPost,
            onFlagPost: configuration.onFlagPost,
            onOpenReplyTarget: configuration.onOpenPostNumber,
            onOpenReplies: configuration.onOpenPostReplies,
            onExpandText: configuration.onExpandPostText,
            onVotePoll: configuration.onVotePoll,
            onUnvotePoll: configuration.onUnvotePoll,
            onSwipeReply: { post in
                configuration.onOpenComposer(post)
            }
        )
    }

    private func configurePostCellNode(
        _ node: FirePostCellNode,
        with context: FireTopicDetailRuntimePostContext,
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        let width = layoutContentWidth()
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: Int(width.rounded(.toNearestOrEven)),
            contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue
        )
        let layoutKey = makeLayoutKey(for: context, trait: trait)
        node.configure(
            payload: FirePostCellRenderPayload(
                post: context.post,
                renderContent: context.renderContent,
                baseURLString: configuration.baseURLString,
                canWriteInteractions: configuration.canWriteInteractions,
                isMutating: configuration.isMutatingPost(context.post.id),
                replyContext: context.replyContext,
                replyTargetPostNumber: context.replyTargetPostNumber,
                replyShortcutCount: context.replyShortcutCount,
                isLoadingReplyContext: context.isLoadingReplyContext,
                textExpansionState: context.textExpansionState,
                isSearchHighlighted: configuration.isSearchHighlighted(postID: context.post.id),
                showsDivider: context.showsDivider,
                layoutWidth: width,
                boostAnimationsEnabled: !isScrollInteractionActive,
                layout: layoutManager?.cachedLayout(forKey: layoutKey),
                layoutKey: layoutKey
            ),
            callbacks: postCallbacks(configuration: configuration),
            depth: context.depth,
            showsThreadLine: context.showsThreadLine,
            showsDivider: context.showsDivider
        )
    }

    private func makeLayoutKey(
        for context: FireTopicDetailRuntimePostContext,
        trait: FirePostLayoutTraitSignature
    ) -> FirePostCellLayoutKey {
        let textContentID = [
            String(context.post.id),
            context.renderContent.signature.token,
            String(context.textExpansionState.isExpanded),
            String(context.textExpansionState.isCollapsible),
        ].joined(separator: "\u{1F}")

        let pollSignature = FirePostPollRenderModel.models(from: context.post.polls)
            .map(\.signature)
        let boostSignature = context.post.boosts.map { boost in
            [
                String(boost.id),
                boost.user.username,
                boost.user.name ?? "",
                boost.displayText,
            ].joined(separator: "\u{1E}")
        }

        return FirePostCellLayoutKey(
            postID: context.post.id,
            depth: context.depth,
            showsThreadLine: context.showsThreadLine,
            showsDivider: context.showsDivider,
            replyTargetPostNumber: context.replyTargetPostNumber,
            replyContext: context.replyContext,
            textContentID: textContentID,
            imageSignature: context.renderContent.segments.map(\.signatureToken),
            pollSignature: pollSignature,
            boostSignature: boostSignature,
            hasReactions: !context.post.reactions.isEmpty,
            replyShortcutCount: context.replyShortcutCount,
            textExpansionState: context.textExpansionState,
            acceptedAnswer: context.post.acceptedAnswer,
            hasAuthorMetadata: FirePostAuthorMetadataDisplay.hasVisibleMetadata(context.post),
            trait: trait
        )
    }

    private func replyFooterIndexPath(in items: [FireTopicDetailRuntimeItem]) -> IndexPath? {
        guard let index = items.firstIndex(where: { $0.kind == .replyFooter }) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    private func performPullToRefresh() {
        Task { [weak self] in
            await self?.onRefresh?()
            await MainActor.run { [weak self] in
                self?.collectionNode.view.refreshControl?.endRefreshing()
            }
        }
    }

    private static func makeCollectionLayout() -> UICollectionViewFlowLayout {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.estimatedItemSize = .zero
        return flowLayout
    }

    private func configureTextureRanges() {
        collectionNode.leadingScreensForBatching = 1.5

        var displayTuning = ASRangeTuningParameters()
        displayTuning.leadingBufferScreenfuls = 1.0
        displayTuning.trailingBufferScreenfuls = 0.5
        collectionNode.setTuningParameters(displayTuning, for: .display)

        var preloadTuning = ASRangeTuningParameters()
        preloadTuning.leadingBufferScreenfuls = 1.5
        preloadTuning.trailingBufferScreenfuls = 1.0
        collectionNode.setTuningParameters(preloadTuning, for: .preload)
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
        if let configuration = currentConfiguration {
            prepareLayoutsIfNeeded(
                items: currentItems,
                configuration: configuration,
                pendingScrollTarget: configuration.pendingScrollTarget
            )
        }
        updateVisibleBoostAnimationState()
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

    private func publishScrollInteractionStateIfNeeded() {
        let isActive = isScrollInteractionActive
        guard lastPublishedScrollInteractionActive != isActive else { return }
        lastPublishedScrollInteractionActive = isActive
        onScrollInteractionChanged?(isActive)
        updateVisibleBoostAnimationState()
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

    @objc
    private func handleBackgroundTap() {
        onBackgroundTap?()
    }
}

private final class FireTopicDetailFeedCellFactory: NSObject {
    var configuration: FireTopicDetailRuntimeConfiguration?
    var layoutWidthProvider: (() -> CGFloat)?
    var onRequestLoadMore: (() -> Void)?

    func makeCellNode(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> ASCellNode {
        switch item.kind {
        case .header:
            return FireTopicDetailHeaderCellNode(configuration: configuration)
        case .aiSummary:
            return FireTopicDetailAISummaryCellNode(configuration: configuration)
        case .stats:
            return makeStatsCellNode(configuration: configuration)
        case .topicVote:
            return makeTopicVoteCellNode(configuration: configuration)
        case .repliesHeader:
            return makeRepliesHeaderCellNode(configuration: configuration)
        case .replyFooter:
            return makeReplyFooterCellNode(for: item, configuration: configuration)
        case .bodyState:
            return makeBodyStateCellNode(configuration: configuration)
        case .notice:
            return makeTextCellNode(for: item, configuration: configuration)
        case .originalPost, .reply:
            return makeMissingPostCellNode()
        }
    }

    @objc
    private func handleToggleTopicVote() {
        guard let configuration else { return }
        Task { await configuration.onToggleTopicVote() }
    }

    @objc
    private func handleShowTopicVoters() {
        guard let configuration else { return }
        Task { await configuration.onShowTopicVoters() }
    }

    @objc
    private func handleLoadMoreReplies() {
        onRequestLoadMore?()
    }

    @objc
    private func handleLoadTopicDetail() {
        guard let configuration else { return }
        Task { await configuration.onLoadTopicDetail() }
    }

    private func makeStatsCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true

        let dividerNode = ASDisplayNode()
        dividerNode.backgroundColor = .separator
        dividerNode.style.preferredSize = CGSize(width: max(layoutWidthProvider?() ?? 1, 1), height: 0.5)

        let replyNode = makeStatNode(value: "\(configuration.displayedReplyCount)", label: "回复")
        let viewNode = makeStatNode(value: "\(configuration.displayedViewsCount)", label: "浏览")
        let interactionNode = makeStatNode(
            value: configuration.displayedInteractionCount.map(String.init) ?? "...",
            label: "互动"
        )
        [replyNode, viewNode, interactionNode].forEach {
            $0.style.flexGrow = 1.0
            $0.style.flexShrink = 1.0
        }

        node.layoutSpecBlock = { _, _ in
            let stack = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 0,
                justifyContent: .start,
                alignItems: .stretch,
                children: [replyNode, viewNode, interactionNode]
            )
            stack.style.flexGrow = 1.0
            let rootStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 0,
                justifyContent: .start,
                alignItems: .stretch,
                children: [dividerNode, stack]
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 12, left: 16, bottom: 8, right: 16),
                child: rootStack
            )
        }
        return node
    }

    private func makeStatNode(value: String, label: String) -> ASDisplayNode {
        let valueNode = ASTextNode()
        let captionFont = UIFont.preferredFont(forTextStyle: .subheadline)
        valueNode.attributedText = NSAttributedString(
            string: value,
            attributes: [
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                    for: UIFont.monospacedDigitSystemFont(ofSize: captionFont.pointSize, weight: .semibold)
                ),
                .foregroundColor: UIColor.label,
            ]
        )

        let labelNode = ASTextNode()
        labelNode.attributedText = NSAttributedString(
            string: label,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption2),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )

        let wrapper = ASDisplayNode()
        wrapper.automaticallyManagesSubnodes = true
        wrapper.layoutSpecBlock = { _, _ in
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 2,
                justifyContent: .start,
                alignItems: .center,
                children: [valueNode, labelNode]
            )
            stack.style.flexGrow = 1.0
            return stack
        }
        return wrapper
    }

    private func makeTopicVoteCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        guard let detail = configuration.detail else { return ASCellNode() }

        let wrapperNode = ASCellNode()
        wrapperNode.automaticallyManagesSubnodes = true
        wrapperNode.backgroundColor = .systemBackground

        let containerNode = ASDisplayNode()
        containerNode.backgroundColor = .secondarySystemBackground
        containerNode.cornerRadius = 8
        containerNode.automaticallyManagesSubnodes = true

        let titleNode = ASTextNode()
        titleNode.attributedText = NSAttributedString(
            string: "\(detail.voteCount) 票",
            attributes: [
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                    for: UIFont.systemFont(
                        ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                        weight: .semibold
                    )
                ),
                .foregroundColor: FireTopicDetailCellColors.accent,
            ]
        )

        let statusNode = ASTextNode()
        if detail.userVoted {
            statusNode.attributedText = NSAttributedString(
                string: "你已投票",
                attributes: [
                    .font: UIFontMetrics(forTextStyle: .caption1).scaledFont(
                        for: UIFont.systemFont(
                            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                            weight: .semibold
                        )
                    ),
                    .foregroundColor: UIColor.systemGreen,
                ]
            )
        }
        statusNode.isHidden = !detail.userVoted
        statusNode.style.flexShrink = 1.0

        let toggleNode = ASButtonNode()
        toggleNode.setTitle(
            detail.userVoted ? "取消投票" : "投一票",
            with: UIFont.preferredFont(forTextStyle: .caption1),
            with: detail.userVoted ? .label : .white,
            for: .normal
        )
        toggleNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        toggleNode.backgroundColor = detail.userVoted ? .tertiarySystemFill : FireTopicDetailCellColors.accent
        toggleNode.cornerRadius = 16
        toggleNode.clipsToBounds = true
        toggleNode.isEnabled = configuration.canWriteInteractions
        toggleNode.addTarget(self, action: #selector(handleToggleTopicVote), forControlEvents: .touchUpInside)

        let votersNode = ASButtonNode()
        votersNode.setImage(UIImage(systemName: "person.3"), for: .normal)
        votersNode.setTitle(
            "查看投票用户",
            with: UIFont.preferredFont(forTextStyle: .caption1),
            with: FireTopicDetailCellColors.accent,
            for: .normal
        )
        votersNode.contentSpacing = 6
        votersNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        votersNode.addTarget(self, action: #selector(handleShowTopicVoters), forControlEvents: .touchUpInside)

        containerNode.layoutSpecBlock = { _, _ in
            let spacer = ASLayoutSpec()
            spacer.style.flexGrow = 1.0
            let headerChildren: [ASLayoutElement] = detail.userVoted
                ? [titleNode, spacer, statusNode]
                : [titleNode, spacer]
            let headerRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 10,
                justifyContent: .start,
                alignItems: .center,
                children: headerChildren
            )
            let buttonRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 10,
                justifyContent: .start,
                alignItems: .center,
                children: [toggleNode, votersNode]
            )
            let innerStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 10,
                justifyContent: .start,
                alignItems: .stretch,
                children: [headerRow, buttonRow]
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14),
                child: innerStack
            )
        }

        wrapperNode.layoutSpecBlock = { _, _ in
            ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 8, left: 16, bottom: 4, right: 16),
                child: containerNode
            )
        }
        return wrapperNode
    }

    private func makeRepliesHeaderCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let titleNode = ASTextNode()
        titleNode.attributedText = NSAttributedString(
            string: "回复",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.label,
            ]
        )

        let countNode = ASTextNode()
        let countText: String
        if configuration.detail != nil {
            if configuration.loadedReplyCount < configuration.totalReplyCount {
                countText = "已加载 \(configuration.loadedReplyCount) / \(configuration.totalReplyCount) 条"
            } else {
                countText = "\(configuration.totalReplyCount) 条 · \(configuration.displayedFloorCount) 楼"
            }
        } else {
            countText = ""
        }
        countNode.attributedText = NSAttributedString(
            string: countText,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )
        countNode.style.flexShrink = 1.0

        node.layoutSpecBlock = { _, _ in
            let spacer = ASLayoutSpec()
            spacer.style.flexGrow = 1.0
            let stack = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 12,
                justifyContent: .start,
                alignItems: .center,
                children: [titleNode, spacer, countNode]
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 18, left: 16, bottom: 14, right: 16),
                child: stack
            )
        }
        return node
    }

    private func makeReplyFooterCellNode(
        for item: FireTopicDetailRuntimeItem,
        configuration _: FireTopicDetailRuntimeConfiguration
    ) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let state = (item.contentToken.base as? String)
            .flatMap(FireTopicDetailRuntimeReplyFooterState.fromContentToken(_:))
            ?? .none

        let childElement: ASLayoutElement?
        switch state {
        case .none:
            childElement = nil
        case .loadMoreAvailable:
            let buttonNode = ASButtonNode()
            buttonNode.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
            buttonNode.setTitle(
                "加载更多回复",
                with: UIFont.preferredFont(forTextStyle: .subheadline),
                with: FireTopicDetailCellColors.accent,
                for: .normal
            )
            buttonNode.contentSpacing = 6
            buttonNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            buttonNode.isEnabled = true
            buttonNode.addTarget(self, action: #selector(handleLoadMoreReplies), forControlEvents: .touchUpInside)
            childElement = buttonNode
        case .emptyPrompt:
            let label = ASTextNode()
            label.attributedText = NSAttributedString(
                string: "还没有回复，发表你的看法吧",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
            childElement = label
        case .endReached:
            let label = ASTextNode()
            label.attributedText = NSAttributedString(
                string: "---- 到底了 ----",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.tertiaryLabel,
                ]
            )
            childElement = label
        case .loadFailed(_):
            let buttonNode = ASButtonNode()
            buttonNode.setImage(UIImage(systemName: "arrow.clockwise.circle"), for: .normal)
            buttonNode.setTitle(
                "加载更多回复失败，点击重试",
                with: UIFont.preferredFont(forTextStyle: .subheadline),
                with: FireTopicDetailCellColors.accent,
                for: .normal
            )
            buttonNode.contentSpacing = 6
            buttonNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            buttonNode.isEnabled = true
            buttonNode.addTarget(self, action: #selector(handleLoadMoreReplies), forControlEvents: .touchUpInside)
            childElement = buttonNode
        case .loadingFooter:
            let label = ASTextNode()
            label.attributedText = NSAttributedString(
                string: "正在加载更多回复...",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
            let indicator = ASDisplayNode(viewBlock: {
                let view = UIActivityIndicatorView(style: .medium)
                view.startAnimating()
                return view
            })
            indicator.style.preferredSize = CGSize(width: 20, height: 20)
            childElement = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 8,
                justifyContent: .center,
                alignItems: .center,
                children: [indicator, label]
            )
        }

        node.layoutSpecBlock = { _, constrainedSize in
            let height = max(constrainedSize.min.height, 44)
            let child = childElement ?? ASLayoutSpec()
            let sized = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 0,
                justifyContent: .center,
                alignItems: .center,
                children: [child]
            )
            sized.style.preferredSize = CGSize(width: constrainedSize.max.width, height: height)
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16),
                child: sized
            )
        }
        return node
    }

    private func makeBodyStateCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let stackChildren: [ASLayoutElement]
        if configuration.isLoadingTopic {
            let label = ASTextNode()
            label.attributedText = NSAttributedString(
                string: "加载中...",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .caption1),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
            stackChildren = [label]
        } else {
            let messageNode = ASTextNode()
            messageNode.attributedText = NSAttributedString(
                string: configuration.detailError ?? "加载帖子",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .caption1),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
            messageNode.maximumNumberOfLines = 0

            let buttonNode = ASButtonNode()
            buttonNode.setTitle(
                configuration.detailError == nil ? "加载" : "重试",
                with: UIFont.preferredFont(forTextStyle: .subheadline),
                with: FireTopicDetailCellColors.accent,
                for: .normal
            )
            buttonNode.addTarget(self, action: #selector(handleLoadTopicDetail), forControlEvents: .touchUpInside)

            stackChildren = [messageNode, buttonNode]
        }

        node.layoutSpecBlock = { _, constrainedSize in
            let height = max(constrainedSize.min.height, 96)
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 8,
                justifyContent: .center,
                alignItems: .center,
                children: stackChildren
            )
            let sized = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 8,
                justifyContent: .center,
                alignItems: .center,
                children: [stack]
            )
            sized.style.preferredSize = CGSize(width: constrainedSize.max.width, height: height)
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
                child: sized
            )
        }
        return node
    }

    private func makeTextCellNode(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let titleNode = ASTextNode()
        titleNode.maximumNumberOfLines = 0
        let bodyNode = ASTextNode()
        bodyNode.maximumNumberOfLines = 0

        switch item.kind {
        case .header:
            let status = configuration.row.statusLabels.joined(separator: " · ")
            titleNode.attributedText = NSAttributedString(
                string: configuration.displayedTopicTitle,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: UIColor.label,
                ]
            )
            bodyNode.attributedText = status.isEmpty ? nil : NSAttributedString(
                string: status,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
        case .aiSummary:
            let title = "AI 摘要"
            let body: String
            if let summary = configuration.topicAiSummary {
                body = summary.summarizedText
            } else if configuration.isLoadingTopicAiSummary {
                body = "正在加载摘要..."
            } else {
                body = configuration.topicAiSummaryError ?? "加载失败"
            }
            titleNode.attributedText = NSAttributedString(
                string: title,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: UIColor.label,
                ]
            )
            bodyNode.attributedText = NSAttributedString(
                string: body,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
        case .notice:
            let statusMessage = item.statusMessage
            let title = statusMessage?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTitle = (title?.isEmpty == false) ? title : nil
            let messageColor = statusMessage?.emphasizesError == true ? UIColor.systemRed : UIColor.secondaryLabel
            bodyNode.attributedText = NSAttributedString(
                string: statusMessage?.message ?? "正在显示缓存内容",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: messageColor,
                ]
            )
            if let trimmedTitle {
                titleNode.attributedText = NSAttributedString(
                    string: trimmedTitle,
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .headline),
                        .foregroundColor: statusMessage?.emphasizesError == true ? UIColor.systemRed : UIColor.label,
                    ]
                )
            }
        default:
            break
        }

        var children: [ASLayoutElement] = [
            titleNode.attributedText != nil ? titleNode : nil,
            bodyNode.attributedText != nil ? bodyNode : nil,
        ].compactMap { $0 }

        if item.kind == .notice, item.statusMessage?.retryable == true {
            let buttonNode = ASButtonNode()
            buttonNode.setTitle(
                "重试",
                with: UIFont.preferredFont(forTextStyle: .subheadline),
                with: FireTopicDetailCellColors.accent,
                for: .normal
            )
            buttonNode.addTarget(self, action: #selector(handleLoadTopicDetail), forControlEvents: .touchUpInside)
            children.append(buttonNode)
        }

        node.layoutSpecBlock = { _, _ in
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 8,
                justifyContent: .start,
                alignItems: .stretch,
                children: children
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                child: stack
            )
        }
        return node
    }

    private func makeMissingPostCellNode() -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let textNode = ASTextNode()
        textNode.attributedText = NSAttributedString(
            string: "帖子内容加载中...",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )

        node.layoutSpecBlock = { _, _ in
            ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                child: textNode
            )
        }
        return node
    }
}
