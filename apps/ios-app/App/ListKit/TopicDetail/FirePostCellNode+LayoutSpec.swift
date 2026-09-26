import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let vd = FirePostCellLayoutCalculator.visualDepth(for: currentDepth)
        let indent = CGFloat(min(vd, FirePostCellLayoutCalculator.maxVisualDepth)) * FirePostCellLayoutCalculator.indentWidthPerDepth
        let avatarSz = currentAvatarSize
        let avatarSp = currentAvatarSpacing
        let outerPadding = FirePostCellLayoutCalculator.outerHorizontalPadding
        let totalWidth = constrainedSize.max.width.isFinite ? constrainedSize.max.width : currentLayoutWidth
        let rowAvailableWidth = max(totalWidth - outerPadding * 2 - indent, 1)
        let bodyAvailableWidth = Self.availableContentWidth(
            totalWidth: totalWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let headerAvailableWidth = max(rowAvailableWidth - avatarSz - avatarSp, 1)
        let shouldSuppressAttachments: Bool
        if let currentResolvedLayout {
            shouldSuppressAttachments = currentResolvedLayout.textExpansionFrame != nil
        } else {
            let hasImageSegments = currentPayload?.renderContent.segments.contains(where: \.isImage) ?? false
            shouldSuppressAttachments = (hasImageSegments || !pollContainerNode.isHidden)
                && Self.shouldSuppressAttachmentsForCollapsedText(
                    plainText: currentPayload?.renderContent.plainText ?? "",
                    hasAttributedText: currentPayload?.renderContent.attributedText != nil,
                    textExpansionState: currentPayload?.textExpansionState ?? .disabled,
                    totalWidth: totalWidth,
                    depth: currentDepth,
                    avatarSize: currentAvatarSize,
                    avatarSpacing: currentAvatarSpacing,
                    contentSizeCategory: currentContentSizeCategory
                )
        }

        let avatarColumn = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarContainerNode]
        )
        avatarColumn.style.minWidth = ASDimensionMake(avatarSz)
        avatarColumn.style.maxWidth = ASDimensionMake(avatarSz)
        avatarColumn.style.flexShrink = 0.0

        // Meta row: display name + "回复 @user" share the first line; @handle/tags stay below.
        var authorChildren: [ASLayoutElement] = [usernameNode]
        if !replyContextNode.isHidden {
            replyContextNode.style.flexShrink = 1.0
            authorChildren.append(replyContextNode)
        }
        if !authorBadgeNode.isHidden {
            authorChildren.append(authorBadgeNode)
        }
        if !acceptedAnswerNode.isHidden {
            authorChildren.append(acceptedAnswerNode)
        }
        if !menuNode.isHidden {
            menuNode.style.preferredSize = CGSize(width: 20, height: 20)
            authorChildren.append(menuNode)
        }
        let authorRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 5,
            justifyContent: .start,
            alignItems: .center,
            children: authorChildren
        )
        authorRow.style.flexShrink = 1.0
        authorRow.style.flexGrow = 0.0

        let firstLineSpacer = ASLayoutSpec()
        firstLineSpacer.style.flexGrow = 1.0

        let metaChildren: [ASLayoutElement] = [authorRow, firstLineSpacer, timestampNode]
        let metaRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 6,
            justifyContent: .start,
            alignItems: .center,
            children: metaChildren
        )
        metaRow.style.flexShrink = 1.0

        // Header stays to the right of the avatar; body content uses the full row width below it.
        var headerChildren: [ASLayoutElement] = [metaRow]
        var didAttachBoostBarrage = false
        var secondaryChildren: [ASLayoutElement] = []
        if !authorMetadataNode.isHidden {
            secondaryChildren.append(authorMetadataNode)
        }
        if !secondaryChildren.isEmpty {
            let secondarySpacer = ASLayoutSpec()
            secondarySpacer.style.flexGrow = 1.0
            secondaryChildren.append(secondarySpacer)
            secondaryChildren.append(postNumberNode)
            let secondaryRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 6,
                justifyContent: .start,
                alignItems: .center,
                children: secondaryChildren
            )
            secondaryRow.style.flexShrink = 1.0
            headerChildren.append(secondaryRow)
        } else {
            let secondarySpacer = ASLayoutSpec()
            secondarySpacer.style.flexGrow = 1.0
            let postNumberRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 0,
                justifyContent: .start,
                alignItems: .center,
                children: [secondarySpacer, postNumberNode]
            )
            headerChildren.append(postNumberRow)
        }

        let headerContentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: FirePostCellLayoutCalculator.headerStackSpacing,
            justifyContent: .start,
            alignItems: .stretch,
            children: headerChildren
        )
        headerContentStack.style.flexGrow = 1.0
        headerContentStack.style.flexShrink = 1.0
        headerContentStack.style.minWidth = ASDimensionMake(headerAvailableWidth)
        headerContentStack.style.maxWidth = ASDimensionMake(headerAvailableWidth)

        var bodyChildren: [ASLayoutElement] = []

        if !bodyTextNode.isHidden {
            bodyChildren.append(bodyElement(bodyTextNode, didAttachBoostBarrage: &didAttachBoostBarrage))
        }
        if !bodySelectableTextNode.isHidden {
            bodyChildren.append(bodyElement(bodySelectableTextNode, didAttachBoostBarrage: &didAttachBoostBarrage))
        }

        if !shouldSuppressAttachments {
            for segmentNode in contentSegmentNodes {
                bodyChildren.append(bodyElement(segmentNode, didAttachBoostBarrage: &didAttachBoostBarrage))
            }

            // Poll container
            if !pollContainerNode.isHidden {
                bodyChildren.append(pollContainerNode)
            }
        }

        // Footer chrome:
        // [bubble?] [reply react boost ...]
        // [quick reaction strip when expanded]
        // [existing reaction chips full width]
        var actionRowChildren: [ASLayoutElement] = []
        if !replyShortcutNode.isHidden {
            replyShortcutNode.style.flexGrow = 0
            replyShortcutNode.style.flexShrink = 0
            actionRowChildren.append(replyShortcutNode)
        }

        let primaryCluster = [
            actionReplyNode,
            actionReactNode,
            actionBoostNode,
            overflowNode,
        ].filter { !$0.isHidden }
        for node in primaryCluster {
            node.style.flexGrow = 0
            node.style.flexShrink = 0
            actionRowChildren.append(node)
        }

        let overflowCluster = [
            actionQuoteNode,
            actionBookmarkNode,
            actionFlagNode,
            actionEditNode,
        ].filter { !$0.isHidden }
        actionRowChildren.append(contentsOf: overflowCluster)

        var footerChildren: [ASLayoutElement] = []
        if !actionRowChildren.isEmpty {
            let actionRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: FirePostCellLayoutCalculator.actionIconSpacing,
                justifyContent: .start,
                alignItems: .center,
                children: actionRowChildren
            )
            actionRow.style.flexShrink = 1.0
            actionRow.style.minHeight = ASDimensionMake(FirePostCellLayoutCalculator.actionRowHeight)
            footerChildren.append(actionRow)
        }

        if !reactionPickerScrollNode.isHidden, !reactionPickerButtons.isEmpty {
            reactionPickerScrollNode.style.flexGrow = 1
            reactionPickerScrollNode.style.flexShrink = 1
            reactionPickerScrollNode.style.minHeight = ASDimensionMake(
                FirePostCellLayoutCalculator.reactionPickerStripHeight
            )
            reactionPickerScrollNode.style.maxHeight = ASDimensionMake(
                FirePostCellLayoutCalculator.reactionPickerStripHeight
            )
            footerChildren.append(reactionPickerScrollNode)
        }

        if !reactionContainerNode.isHidden, !reactionButtons.isEmpty {
            let reactionRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: FirePostCellLayoutCalculator.reactionChipHorizontalSpacing,
                justifyContent: .start,
                alignItems: .center,
                children: reactionButtons
            )
            reactionRow.style.flexShrink = 1.0
            reactionRow.style.minHeight = ASDimensionMake(
                FirePostCellLayoutCalculator.reactionChipHeight
            )
            footerChildren.append(reactionRow)
        }

        let actionElement: ASLayoutElement?
        if footerChildren.isEmpty {
            actionElement = nil
        } else if footerChildren.count == 1 {
            actionElement = footerChildren[0]
        } else {
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: FirePostCellLayoutCalculator.reactionTopSpacing,
                justifyContent: .start,
                alignItems: .stretch,
                children: footerChildren
            )
            actionElement = stack
        }

        let boostElement: ASLayoutElement? = !shouldSuppressAttachments && !boostContainerNode.isHidden
            ? boostContainerNode
            : nil
        if let boostElement, let actionElement {
            let footerStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 0,
                justifyContent: .start,
                alignItems: .stretch,
                children: [boostElement, actionElement]
            )
            footerStack.style.flexShrink = 1.0
            bodyChildren.append(footerStack)
        } else if let boostElement {
            bodyChildren.append(boostElement)
        } else if let actionElement {
            bodyChildren.append(actionElement)
        }

        let rootStack: ASLayoutSpec
        if FirePostCellLayoutCalculator.usesFullWidthBody(for: currentDepth) {
            let headerRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: avatarSp,
                justifyContent: .start,
                alignItems: .start,
                children: [avatarColumn, headerContentStack]
            )
            headerRow.style.flexShrink = 1.0

            let contentChildren: [ASLayoutElement] = [headerRow] + bodyChildren
            let contentStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: FirePostCellLayoutCalculator.headerToBodySpacing,
                justifyContent: .start,
                alignItems: .stretch,
                children: contentChildren
            )
            contentStack.style.flexGrow = 1.0
            contentStack.style.flexShrink = 1.0
            contentStack.style.minWidth = ASDimensionMake(max(rowAvailableWidth, 1))
            contentStack.style.maxWidth = ASDimensionMake(max(rowAvailableWidth, 1))
            rootStack = contentStack
        } else {
            let contentColumnChildren: [ASLayoutElement] = [headerContentStack] + bodyChildren
            let contentColumn = ASStackLayoutSpec(
                direction: .vertical,
                spacing: FirePostCellLayoutCalculator.headerToBodySpacing,
                justifyContent: .start,
                alignItems: .stretch,
                children: contentColumnChildren
            )
            contentColumn.style.flexGrow = 1.0
            contentColumn.style.flexShrink = 1.0
            contentColumn.style.minWidth = ASDimensionMake(max(bodyAvailableWidth, 1))
            contentColumn.style.maxWidth = ASDimensionMake(max(bodyAvailableWidth, 1))

            let row = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: avatarSp,
                justifyContent: .start,
                alignItems: .stretch,
                children: [avatarColumn, contentColumn]
            )
            row.style.flexShrink = 1.0
            row.style.minWidth = ASDimensionMake(max(rowAvailableWidth, 1))
            row.style.maxWidth = ASDimensionMake(max(rowAvailableWidth, 1))
            rootStack = row
        }

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(
                top: 8,
                left: outerPadding + indent,
                bottom: 8,
                right: outerPadding
            ),
            child: rootStack
        )
        var spec: ASLayoutSpec = inset
        if !threadLineNode.isHidden {
            threadLineNode.style.preferredSize = CGSize(width: 1, height: 1)
            threadLineNode.style.flexGrow = 1
            let threadInset = ASInsetLayoutSpec(
                insets: UIEdgeInsets(
                    top: 8 + avatarSz,
                    left: outerPadding + indent + avatarSz / 2 - 0.5,
                    bottom: 8,
                    right: 0
                ),
                child: threadLineNode
            )
            spec = ASOverlayLayoutSpec(child: spec, overlay: threadInset)
        }
        if !dividerNode.isHidden {
            dividerNode.style.preferredSize = CGSize(width: max(bodyAvailableWidth, 1), height: 0.5)
            let divider = ASRelativeLayoutSpec(
                horizontalPosition: .start,
                verticalPosition: .end,
                sizingOption: [],
                child: dividerNode
            )
            spec = ASOverlayLayoutSpec(child: spec, overlay: divider)
        }
        return spec
    }

    override func layout() {
        super.layout()

        // Size poll views inside the container. Prefer the container's laid-out width so
        // hit targets match the Texture frame (do not overflow a narrow parent bounds).
        let fallbackWidth = Self.availableContentWidth(
            totalWidth: calculatedSize.width,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let containerWidth = pollContainerNode.bounds.width
        let availableWidth = containerWidth > 1 ? containerWidth : fallbackWidth

        var pollY: CGFloat = 0
        for (index, pollView) in pollViews.enumerated() {
            let height = index < pollHeights.count ? pollHeights[index] : 0
            pollView.frame = CGRect(
                x: 0,
                y: pollY,
                width: availableWidth,
                height: height
            )
            pollY += height + 10
        }
    }
}
