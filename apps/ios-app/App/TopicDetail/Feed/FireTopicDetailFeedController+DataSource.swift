import AsyncDisplayKit
import UIKit

@MainActor
extension FireTopicDetailFeedController {
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
        // Capture appearance snapshot on the main thread before Texture may run this block off-main.
        let capturedAppearance = currentAppearanceSnapshot()
        let capturedPostContext = configuration.postContext(for: item)
        let capturedLayoutKey = capturedPostContext.map {
            makeLayoutKey(
                for: $0,
                canWriteInteractions: configuration.canWriteInteractions,
                isReactionPickerExpanded: configuration.isReactionPickerExpanded($0.post.id),
                trait: capturedTrait
            )
        }
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
                        isReplyThreadExpanded: postContext.isReplyThreadExpanded,
                        isLoadingReplyContext: postContext.isLoadingReplyContext,
                        textExpansionState: postContext.textExpansionState,
                        isSearchHighlighted: capturedConfiguration.isSearchHighlighted(postID: postContext.post.id),
                        showsDivider: postContext.showsDivider,
                        layoutWidth: capturedLayoutWidth,
                        boostAnimationsEnabled: capturedBoostAnimationsEnabled,
                        isReactionPickerExpanded: capturedConfiguration.isReactionPickerExpanded(postContext.post.id),
                        quickReactionOptions: capturedConfiguration.quickReactionOptions,
                        layout: capturedLayoutKey.flatMap { capturedLayoutManager?.cachedLayout(forKey: $0) },
                        layoutKey: capturedLayoutKey,
                        appearance: capturedAppearance
                    ),
                    callbacks: capturedCallbacks,
                    depth: postContext.depth,
                    showsThreadLine: postContext.showsThreadLine,
                    showsDivider: postContext.showsDivider
                )
                return node
            }
            // Capture layout width on the main thread above. Texture may execute this
            // node block off-main, so cell factories must not touch UIKit here.
            return capturedCellFactory.makeCellNode(
                for: item,
                configuration: capturedConfiguration,
                layoutWidth: capturedLayoutWidth,
                appearance: capturedAppearance
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
}
