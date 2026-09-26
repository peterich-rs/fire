import AsyncDisplayKit
import UIKit

@MainActor
extension FireTopicDetailFeedController {
    func applyVisibleNodeUpdates(
        at indices: [Int],
        previousItems: [FireTopicDetailRuntimeItem],
        nextItems: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        let targets = fireTopicDetailVisibleNodeUpdateTargets(from: previousItems, to: nextItems)
        let requested = Set(indices)
        let previousByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
        for target in targets where requested.contains(target.committedIndex) {
            applyVisibleNodeUpdate(
                target: target,
                previousItem: previousByID[target.item.id],
                configuration: configuration,
                relayout: false
            )
        }
    }

    func applyVisiblePostRelayouts(
        at indexPaths: [IndexPath],
        previousItems: [FireTopicDetailRuntimeItem],
        items: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        let previousByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
        let nextByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for indexPath in indexPaths {
            guard indexPath.item >= 0,
                  indexPath.item < currentItems.count else {
                continue
            }
            let committed = currentItems[indexPath.item]
            guard let nextItem = nextByID[committed.id],
                  let postContext = configuration.postContext(for: nextItem),
                  let node = collectionNode.nodeForItem(at: indexPath) as? FirePostCellNode else {
                continue
            }
            let bands = previousByID[committed.id].map { nextItem.changedMessageBands(from: $0) }
                ?? Set(FireTopicDetailMessageBand.allCases)
            applyPostCellNode(
                node,
                with: postContext,
                configuration: configuration,
                mode: .bands(bands, relayout: true)
            )
        }
    }

    private func applyVisibleNodeUpdate(
        target: FireTopicDetailVisibleNodeUpdateTarget,
        previousItem: FireTopicDetailRuntimeItem?,
        configuration: FireTopicDetailRuntimeConfiguration,
        relayout: Bool
    ) {
        guard let postContext = configuration.postContext(for: target.item),
              let node = collectionNode.nodeForItem(
                  at: IndexPath(item: target.committedIndex, section: 0)
              ) as? FirePostCellNode else {
            return
        }
        let bands = previousItem.map { target.item.changedMessageBands(from: $0) }
            ?? Set(FireTopicDetailMessageBand.allCases)
        applyPostCellNode(
            node,
            with: postContext,
            configuration: configuration,
            mode: .bands(bands, relayout: relayout)
        )
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

    func stageItems(
        _ items: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        latestItems = items
        currentConfiguration = configuration
        cellFactory.configuration = configuration
        if fireTopicDetailItemsHaveSameRenderedContent(currentItems, items) {
            currentItems = items
            latestItems = nil
            DispatchQueue.main.async { [weak self] in
                self?.publishTitlePinStateIfNeeded()
            }
        }
    }

    func applyItems(
        _ items: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        stageItems(items, configuration: configuration)
    }

    func postCallbacks(configuration: FireTopicDetailRuntimeConfiguration) -> FirePostCellCallbacks {
        FirePostCellCallbacks(
            onLinkTapped: configuration.onLinkTapped,
            onOpenProfile: configuration.onOpenProfile,
            onOpenImage: configuration.onOpenImage,
            onToggleLike: configuration.onToggleLike,
            onSelectReaction: configuration.onSelectReaction,
            onToggleReactionPicker: configuration.onToggleReactionPicker,
            onReplyPost: { post in
                configuration.onOpenComposer(post)
            },
            onBoostPost: configuration.onBoostPost,
            onAcceptSolution: configuration.onAcceptSolution,
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

    private enum FirePostCellApplyMode {
        case configure
        case bands(Set<FireTopicDetailMessageBand>, relayout: Bool)
    }

    func configurePostCellNode(
        _ node: FirePostCellNode,
        with context: FireTopicDetailRuntimePostContext,
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        applyPostCellNode(node, with: context, configuration: configuration, mode: .configure)
    }

    private func applyPostCellNode(
        _ node: FirePostCellNode,
        with context: FireTopicDetailRuntimePostContext,
        configuration: FireTopicDetailRuntimeConfiguration,
        mode: FirePostCellApplyMode
    ) {
        let width = layoutContentWidth()
        let payload = FirePostCellRenderPayload(
            post: context.post,
            renderContent: context.renderContent,
            baseURLString: configuration.baseURLString,
            canWriteInteractions: configuration.canWriteInteractions,
            isMutating: configuration.isMutatingPost(context.post.id),
            replyContext: context.replyContext,
            replyTargetPostNumber: context.replyTargetPostNumber,
            replyShortcutCount: context.replyShortcutCount,
            isReplyThreadExpanded: context.isReplyThreadExpanded,
            isLoadingReplyContext: context.isLoadingReplyContext,
            textExpansionState: context.textExpansionState,
            isSearchHighlighted: configuration.isSearchHighlighted(postID: context.post.id),
            showsDivider: context.showsDivider,
            layoutWidth: width,
            boostAnimationsEnabled: !isScrollInteractionActive,
            isReactionPickerExpanded: configuration.isReactionPickerExpanded(context.post.id),
            quickReactionOptions: configuration.quickReactionOptions,
            appearance: currentAppearanceSnapshot()
        )
        let callbacks = postCallbacks(configuration: configuration)
        switch mode {
        case .configure:
            node.configure(
                payload: payload,
                callbacks: callbacks,
                depth: context.depth,
                showsThreadLine: context.showsThreadLine,
                showsDivider: context.showsDivider
            )
        case .bands(let bands, let relayout):
            node.applyBands(
                bands,
                payload: payload,
                callbacks: callbacks,
                showsThreadLine: context.showsThreadLine,
                relayout: relayout
            )
            if relayout {
                node.invalidateCalculatedLayout()
            }
        }
    }

    private func replyFooterIndexPath(in items: [FireTopicDetailRuntimeItem]) -> IndexPath? {
        guard let index = items.firstIndex(where: { $0.kind == .replyFooter }) else { return nil }
        return IndexPath(item: index, section: 0)
    }
}
