import AsyncDisplayKit
import UIKit

@MainActor
extension FireTopicDetailFeedController {
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
            let key = makeLayoutKey(
                for: postContext,
                canWriteInteractions: configuration.canWriteInteractions,
                isReactionPickerExpanded: configuration.isReactionPickerExpanded(postContext.post.id),
                trait: trait
            )
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

            let key = makeLayoutKey(
                for: postContext,
                canWriteInteractions: configuration.canWriteInteractions,
                isReactionPickerExpanded: configuration.isReactionPickerExpanded(postContext.post.id),
                trait: trait
            )
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

    func makeLayoutKey(
        for context: FireTopicDetailRuntimePostContext,
        canWriteInteractions: Bool,
        isReactionPickerExpanded: Bool,
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
            isReplyThreadExpanded: context.isReplyThreadExpanded,
            showsInlineActions: {
                guard context.allowsInlineOverflowActions else { return false }
                let post = context.post
                return canWriteInteractions && !post.hidden
                    || post.canEdit
                    || post.canRecover
                    || (post.canDelete && !post.hidden)
            }(),
            primaryActionSlotCount: {
                guard context.allowsInlineOverflowActions else { return 0 }
                let post = context.post
                let canWrite = canWriteInteractions && !post.hidden
                var slots = 0
                if canWrite {
                    slots += 2 // reply + react
                    if post.canBoost {
                        slots += 1
                    }
                }
                let hasSecondary = canWrite
                    || post.canEdit
                    || post.canRecover
                    || (post.canDelete && !post.hidden)
                if hasSecondary {
                    slots += 1 // overflow
                }
                return slots
            }(),
            isReactionPickerExpanded: isReactionPickerExpanded,
            textExpansionState: context.textExpansionState,
            acceptedAnswer: context.post.acceptedAnswer,
            hasAuthorMetadata: FirePostAuthorMetadataDisplay.hasVisibleMetadata(context.post),
            trait: trait
        )
    }


    static func makeCollectionLayout() -> UICollectionViewFlowLayout {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.estimatedItemSize = .zero
        return flowLayout
    }

    func configureTextureRanges() {
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
}
