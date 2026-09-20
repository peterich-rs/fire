import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func configureRichTextNode(_ node: ASTextNode) {
        node.linkAttributeNames = [NSAttributedString.Key.link.rawValue]
        node.passthroughNonlinkTouches = true
        node.alwaysHandleTruncationTokenTap = true
        node.isUserInteractionEnabled = true
        node.placeholderEnabled = true
        node.placeholderColor = .tertiarySystemFill
        node.style.flexShrink = 1.0
    }

    func applyExpansion(payload: FirePostCellRenderPayload) {
        configureBodyContent(payload: payload)
    }

    func configureBodyContent(payload: FirePostCellRenderPayload) {
        let usesStructuredSegments = payload.renderContent.segments.contains { segment in
            segment.isImage || segment.isOnebox
        }
        guard usesStructuredSegments else {
            configureBodyText(payload: payload)
            rebuildContentSegmentNodes([], renderSizes: [])
            return
        }

        guard !payload.textExpansionState.isCollapsed else {
            configureBodyText(payload: payload)
            configureImageOnlySegmentNodes(payload: payload)
            return
        }

        bodyTextNode.attributedText = nil
        bodyTextNode.isHidden = true
        bodySelectableTextNode.attributedText = nil
        bodySelectableTextNode.isHidden = true
        renderedContentID = nil
        linkDelegate = RichTextNodeLinkDelegate(
            onLink: { [weak self] url in
                self?.currentCallbacks?.onLinkTapped(url)
            },
            onTruncation: { [weak self] in
                guard let self, let payload = self.currentPayload, let callbacks = self.currentCallbacks else { return }
                callbacks.onExpandText(payload.post)
            }
        )

        let availableWidth = Self.availableContentWidth(
            totalWidth: payload.layoutWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let renderSizes = payload.renderContent.segments.map { segment -> CGSize? in
            guard case .image(let image) = segment else {
                return nil
            }
            return FirePostCellLayoutCalculator.imageRenderSize(
                for: image,
                availableWidth: availableWidth,
                depth: currentDepth
            )
        }
        let nextSignature = payload.renderContent.segments.map(\.signatureToken)
        if contentSegmentSignature != nextSignature {
            rebuildContentSegmentNodes(payload.renderContent.segments, renderSizes: renderSizes)
            contentSegmentSignature = nextSignature
        } else {
            updateContentSegmentNodes(payload.renderContent.segments, renderSizes: renderSizes)
        }
    }

    func configureImageOnlySegmentNodes(payload: FirePostCellRenderPayload) {
        let availableWidth = Self.availableContentWidth(
            totalWidth: payload.layoutWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let imageSegments = payload.renderContent.segments.compactMap { segment -> FireTopicPostRenderSegment? in
            guard case .image = segment else { return nil }
            return segment
        }
        let renderSizes = imageSegments.map { segment -> CGSize? in
            guard case .image(let image) = segment else {
                return nil
            }
            return FirePostCellLayoutCalculator.imageRenderSize(
                for: image,
                availableWidth: availableWidth,
                depth: currentDepth
            )
        }
        let nextSignature = imageSegments.map(\.signatureToken)
        if contentSegmentSignature != nextSignature {
            rebuildContentSegmentNodes(imageSegments, renderSizes: renderSizes)
            contentSegmentSignature = nextSignature
        } else {
            updateContentSegmentNodes(imageSegments, renderSizes: renderSizes)
        }
    }

    func configureBodyText(payload: FirePostCellRenderPayload) {
        guard let attrText = payload.renderContent.attributedText, attrText.length > 0 else {
            bodyTextNode.attributedText = nil
            bodyTextNode.isHidden = true
            bodySelectableTextNode.attributedText = nil
            bodySelectableTextNode.isHidden = true
            renderedContentID = nil
            return
        }

        let isCollapsed = payload.textExpansionState.isCollapsed
        let appearanceToken = payload.appearance.token
        // Include collapse + color appearance so ASTextNode rebuilds when expanding
        // or when the user switches light/dark after the cell was bound.
        let contentID = "post:\(payload.post.id)|render:\(payload.renderContent.signature.token)|collapsed:\(isCollapsed)|a:\(appearanceToken)"

        if renderedContentID != contentID {
            renderedContentID = contentID
            let collapsedDisplay = FirePostCollapsedTextNormalizer.attributedTextForCollapsedDisplay(
                attrText,
                accentColor: Self.accentTextColor
            )
            // Bake resolved ink colors for Texture's async/sync display path.
            let resolvedFull = payload.appearance.resolvingDynamicColors(attrText)
            let resolvedCollapsed = payload.appearance.resolvingDynamicColors(collapsedDisplay)
            bodyTextNode.attributedText = isCollapsed ? resolvedCollapsed : resolvedFull
            bodySelectableTextNode.attributedText = resolvedFull
        }
        bodyTextNode.isHidden = !isCollapsed
        bodySelectableTextNode.isHidden = isCollapsed
        bodyTextNode.maximumNumberOfLines = isCollapsed
            ? UInt(FirePostTextExpansionState.collapsedLineLimit)
            : 0
        // When the normalizer already inlined "... 展开" after eliding a quote body,
        // skip ASTextNode's truncation token so we don't double-render the control.
        let collapsedAlreadyHasExpandControl = isCollapsed
            && (bodyTextNode.attributedText?.string.contains("展开") == true)
        bodyTextNode.truncationAttributedText = isCollapsed && !collapsedAlreadyHasExpandControl
            ? FirePostCollapsedTextNormalizer.expansionTruncationToken(
                accentColor: Self.accentTextColor,
                colorTraits: payload.colorTraits
            )
            : nil
        // Keep natural height tight to measured glyphs — do not let the stack stretch lines.
        bodyTextNode.style.flexGrow = 0
        bodyTextNode.style.flexShrink = 1.0
        bodySelectableTextNode.style.flexGrow = 0

        linkDelegate = RichTextNodeLinkDelegate(
            onLink: { [weak self] url in
                guard let self else { return }
                if FirePostCollapsedTextNormalizer.isExpandTextURL(url),
                   let payload = self.currentPayload,
                   let callbacks = self.currentCallbacks {
                    callbacks.onExpandText(payload.post)
                    return
                }
                self.currentCallbacks?.onLinkTapped(url)
            },
            onTruncation: { [weak self] in
                guard let self, let payload = self.currentPayload, let callbacks = self.currentCallbacks else { return }
                callbacks.onExpandText(payload.post)
            }
        )
        bodyTextNode.delegate = linkDelegate
        bodySelectableTextNode.onLink = { [weak self] url in
            self?.currentCallbacks?.onLinkTapped(url)
        }
    }

    func rebuildContentSegmentNodes(
        _ segments: [FireTopicPostRenderSegment],
        renderSizes: [CGSize?]
    ) {
        for node in contentSegmentNodes {
            node.removeFromSupernode()
        }
        contentSegmentNodes.removeAll()
        contentSegmentSignature = segments.map(\.signatureToken)

        for (index, segment) in segments.enumerated() {
            switch segment {
            case .text(let attributedText):
                let textNode = FireSelectableRichTextNode()
                configureSelectableTextNode(textNode)
                let traits = currentPayload?.colorTraits ?? .current
                textNode.attributedText = FireTextureAttributedText.resolvingDynamicColors(
                    attributedText,
                    with: traits
                )
                textNode.isHidden = false
                textNode.onLink = { [weak self] url in
                    self?.currentCallbacks?.onLinkTapped(url)
                }
                contentSegmentNodes.append(textNode)
            case .image(let image):
                let renderSize = index < renderSizes.count
                    ? (renderSizes[index] ?? CGSize(width: 1, height: 1))
                    : CGSize(width: 1, height: 1)
                let imageNode = FirePostImageNode(image: image, renderSize: renderSize)
                imageNode.onTap = { [weak self, weak imageNode] in
                    guard let imageNode else { return }
                    self?.handleImageTap(imageNode)
                }
                contentSegmentNodes.append(imageNode)
            case .onebox(let card):
                let oneboxNode = FireTopicOneboxNode(card: card)
                oneboxNode.onOpen = { [weak self] url in
                    self?.currentCallbacks?.onLinkTapped(url)
                }
                contentSegmentNodes.append(oneboxNode)
            }
        }
    }

    func updateContentSegmentNodes(
        _ segments: [FireTopicPostRenderSegment],
        renderSizes: [CGSize?]
    ) {
        for (index, node) in contentSegmentNodes.enumerated() {
            guard index < segments.count else {
                break
            }
            switch (node, segments[index]) {
            case (let textNode as FireSelectableRichTextNode, .text(let attributedText)):
                let traits = currentPayload?.colorTraits ?? .current
                textNode.attributedText = FireTextureAttributedText.resolvingDynamicColors(
                    attributedText,
                    with: traits
                )
                textNode.isHidden = false
                textNode.onLink = { [weak self] url in
                    self?.currentCallbacks?.onLinkTapped(url)
                }
            case (let imageNode as FirePostImageNode, .image):
                if index < renderSizes.count, let renderSize = renderSizes[index] {
                    imageNode.updateRenderSize(renderSize)
                }
            case (let oneboxNode as FireTopicOneboxNode, .onebox):
                oneboxNode.refreshChrome()
            default:
                continue
            }
        }
    }

    func bodyElement(
        _ node: ASDisplayNode,
        didAttachBoostBarrage: inout Bool
    ) -> ASLayoutElement {
        guard !boostBarrageNode.isHidden,
              !didAttachBoostBarrage,
              node is ASTextNode || node is FireSelectableRichTextNode else {
            return node
        }
        didAttachBoostBarrage = true
        boostBarrageNode.style.flexGrow = 1.0
        boostBarrageNode.style.flexShrink = 1.0
        return ASOverlayLayoutSpec(
            child: node,
            overlay: boostBarrageNode
        )
    }

    static func availableContentWidth(
        totalWidth: CGFloat,
        depth: Int,
        avatarSize: CGFloat,
        avatarSpacing: CGFloat
    ) -> CGFloat {
        let vd = FirePostCellLayoutCalculator.visualDepth(for: depth)
        let indent = CGFloat(min(vd, FirePostCellLayoutCalculator.maxVisualDepth))
            * FirePostCellLayoutCalculator.indentWidthPerDepth
        return max(
            totalWidth
                - FirePostCellLayoutCalculator.outerHorizontalPadding * 2
                - indent
                - FirePostCellLayoutCalculator.bodyLeadingOffset(for: depth),
            1
        )
    }

    func configureSelectableTextNode(_ node: FireSelectableRichTextNode) {
        node.isHidden = true
        node.style.flexShrink = 1.0
    }

    static func shouldSuppressAttachmentsForCollapsedText(
        plainText: String,
        hasAttributedText: Bool,
        textExpansionState: FirePostTextExpansionState,
        totalWidth: CGFloat,
        depth: Int,
        avatarSize: CGFloat,
        avatarSpacing: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> Bool {
        guard textExpansionState.isCollapsed else {
            return false
        }
        let availableWidth = availableContentWidth(
            totalWidth: totalWidth,
            depth: depth,
            avatarSize: avatarSize,
            avatarSpacing: avatarSpacing
        )
        guard let textHeight = FirePostCellLayoutCalculator.estimatedRichTextHeight(
            plainText: plainText,
            hasAttributedText: hasAttributedText,
            containerWidth: availableWidth,
            contentSizeCategory: contentSizeCategory,
            textExpansionState: textExpansionState
        ) else {
            return false
        }
        return textHeight > FirePostCellLayoutCalculator.collapsedTextHeight(
            contentSizeCategory: contentSizeCategory
        )
    }

    static func shouldSuppressAttachmentsForCollapsedText(
        attributedText: NSAttributedString?,
        textExpansionState: FirePostTextExpansionState,
        totalWidth: CGFloat,
        depth: Int,
        avatarSize: CGFloat,
        avatarSpacing: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> Bool {
        shouldSuppressAttachmentsForCollapsedText(
            plainText: attributedText?.string ?? "",
            hasAttributedText: attributedText != nil,
            textExpansionState: textExpansionState,
            totalWidth: totalWidth,
            depth: depth,
            avatarSize: avatarSize,
            avatarSpacing: avatarSpacing,
            contentSizeCategory: contentSizeCategory
        )
    }
}
