import AsyncDisplayKit
import UIKit

final class FireTopicDetailFeedCellFactory: NSObject {
    var configuration: FireTopicDetailRuntimeConfiguration?
    var onRequestLoadMore: (() -> Void)?

    func makeCellNode(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration,
        layoutWidth: CGFloat,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        switch item.kind {
        case .header:
            return FireTopicDetailHeaderCellNode(configuration: configuration, appearance: appearance)
        case .aiSummary:
            return FireTopicDetailAISummaryCellNode(configuration: configuration, appearance: appearance)
        case .stats:
            return makeStatsCellNode(
                configuration: configuration,
                layoutWidth: layoutWidth,
                appearance: appearance
            )
        case .topicVote:
            return makeTopicVoteCellNode(configuration: configuration, appearance: appearance)
        case .repliesHeader:
            return makeRepliesHeaderCellNode(configuration: configuration, appearance: appearance)
        case .replyFooter:
            return makeReplyFooterCellNode(
                for: item,
                configuration: configuration,
                appearance: appearance
            )
        case .bodyState:
            return makeBodyStateCellNode(configuration: configuration, appearance: appearance)
        case .notice:
            return makeTextCellNode(
                for: item,
                configuration: configuration,
                appearance: appearance
            )
        case .originalPost, .reply:
            return makeMissingPostCellNode(appearance: appearance)
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

    private func makeStatsCellNode(
        configuration: FireTopicDetailRuntimeConfiguration,
        layoutWidth: CGFloat,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: node)

        let dividerNode = ASDisplayNode()
        dividerNode.backgroundColor = appearance.divider
        dividerNode.style.preferredSize = CGSize(width: max(layoutWidth, 1), height: 0.5)

        let replyNode = makeStatNode(value: "\(configuration.displayedReplyCount)", label: "回复", appearance: appearance)
        let viewNode = makeStatNode(value: "\(configuration.displayedViewsCount)", label: "浏览", appearance: appearance)
        let interactionNode = makeStatNode(
            value: configuration.displayedInteractionCount.map(String.init) ?? "...",
            label: "互动",
            appearance: appearance
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

    private func makeStatNode(value: String, label: String, appearance: FireAppearanceSnapshot) -> ASDisplayNode {
        let valueNode = ASTextNode()
        // Texture ASTextNode defaults to opaque; without a clear background the
        // display fill is pure black, which survives light-theme switches as a
        // black bar under 回复/浏览/互动.
        configureChromeTextNode(valueNode)
        let captionFont = UIFont.preferredFont(forTextStyle: .subheadline)
        valueNode.attributedText = NSAttributedString(
            string: value,
            attributes: [
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                    for: UIFont.monospacedDigitSystemFont(ofSize: captionFont.pointSize, weight: .semibold)
                ),
                .foregroundColor: appearance.ink,
            ]
        )

        let labelNode = ASTextNode()
        configureChromeTextNode(labelNode)
        labelNode.attributedText = NSAttributedString(
            string: label,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption2),
                .foregroundColor: appearance.subtleInk,
            ]
        )

        let wrapper = ASDisplayNode()
        wrapper.automaticallyManagesSubnodes = true
        wrapper.backgroundColor = .clear
        wrapper.isOpaque = false
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

    private func configureChromeTextNode(_ node: ASTextNode) {
        FireAppearanceTexture.configureChromeTextNode(node)
    }

    private func makeTopicVoteCellNode(
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        guard let detail = configuration.detail else { return ASCellNode() }

        let wrapperNode = ASCellNode()
        wrapperNode.automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: wrapperNode)

        let containerNode = ASDisplayNode()
        containerNode.backgroundColor = .secondarySystemBackground
        containerNode.cornerRadius = 8
        containerNode.automaticallyManagesSubnodes = true

        let titleNode = ASTextNode()
        FireAppearanceTexture.configureChromeTextNode(titleNode)
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
        FireAppearanceTexture.configureChromeTextNode(statusNode)
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
            with: detail.userVoted ? appearance.ink : .white,
            for: .normal
        )
        toggleNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        toggleNode.backgroundColor = detail.userVoted ? .tertiarySystemFill : FireTopicDetailCellColors.accent
        toggleNode.cornerRadius = 16
        toggleNode.clipsToBounds = true
        toggleNode.isEnabled = configuration.canWriteInteractions
        toggleNode.addTarget(self, action: #selector(handleToggleTopicVote), forControlEvents: .touchUpInside)
        toggleNode.fireBindPressBounce(.button)

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
        votersNode.fireBindPressBounce(.compact)

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

    private func makeRepliesHeaderCellNode(
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: node)

        let titleNode = ASTextNode()
        configureChromeTextNode(titleNode)
        titleNode.attributedText = NSAttributedString(
            string: "回复",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: appearance.ink,
            ]
        )

        let countNode = ASTextNode()
        configureChromeTextNode(countNode)
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
                .foregroundColor: appearance.subtleInk,
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
        configuration _: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: node)

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
            buttonNode.fireBindPressBounce(.button)
            childElement = buttonNode
        case .emptyPrompt:
            let label = ASTextNode()
            FireAppearanceTexture.configureChromeTextNode(label)
            label.attributedText = NSAttributedString(
                string: "还没有回复，发表你的看法吧",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: appearance.subtleInk,
                ]
            )
            childElement = label
        case .endReached:
            let label = ASTextNode()
            FireAppearanceTexture.configureChromeTextNode(label)
            label.attributedText = NSAttributedString(
                string: "---- 到底了 ----",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: appearance.tertiaryInk,
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
            buttonNode.fireBindPressBounce(.button)
            childElement = buttonNode
        case .loadingFooter:
            let label = ASTextNode()
            label.attributedText = NSAttributedString(
                string: "正在加载更多回复...",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: appearance.subtleInk,
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

    private func makeBodyStateCellNode(
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: node)

        let stackChildren: [ASLayoutElement]
        if configuration.isLoadingTopic || configuration.isWaitingForPostRender {
            let label = ASTextNode()
            FireAppearanceTexture.configureChromeTextNode(label)
            label.attributedText = NSAttributedString(
                string: "加载中...",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .caption1),
                    .foregroundColor: appearance.subtleInk,
                ]
            )
            stackChildren = [label]
        } else {
            let messageNode = ASTextNode()
            FireAppearanceTexture.configureChromeTextNode(messageNode)
            messageNode.attributedText = NSAttributedString(
                string: configuration.detailError ?? "加载帖子",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .caption1),
                    .foregroundColor: appearance.subtleInk,
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
            buttonNode.fireBindPressBounce(.button)

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
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: node)

        let titleNode = ASTextNode()
        FireAppearanceTexture.configureChromeTextNode(titleNode)
        titleNode.maximumNumberOfLines = 0
        let bodyNode = ASTextNode()
        FireAppearanceTexture.configureChromeTextNode(bodyNode)
        bodyNode.maximumNumberOfLines = 0

        switch item.kind {
        case .header:
            let status = configuration.row.statusLabels.joined(separator: " · ")
            titleNode.attributedText = NSAttributedString(
                string: configuration.displayedTopicTitle,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: appearance.ink,
                ]
            )
            bodyNode.attributedText = status.isEmpty ? nil : NSAttributedString(
                string: status,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: appearance.subtleInk,
                ]
            )
        case .aiSummary:
            let title = "AI 摘要"
            let body: String
            if let summary = configuration.topicAiSummary {
                body = configuration.isTopicAiSummaryExpanded
                    ? summary.summarizedText
                    : "点击展开"
            } else {
                body = ""
            }
            titleNode.attributedText = NSAttributedString(
                string: title,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: appearance.ink,
                ]
            )
            bodyNode.attributedText = NSAttributedString(
                string: body,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: appearance.subtleInk,
                ]
            )
        case .notice:
            let statusMessage = item.statusMessage
            let title = statusMessage?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTitle = (title?.isEmpty == false) ? title : nil
            let messageColor = statusMessage?.emphasizesError == true ? UIColor.systemRed : appearance.subtleInk
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
                        .foregroundColor: statusMessage?.emphasizesError == true ? UIColor.systemRed : appearance.ink,
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
            buttonNode.fireBindPressBounce(.button)
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

    private func makeMissingPostCellNode(appearance: FireAppearanceSnapshot) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: node)

        let textNode = ASTextNode()
        FireAppearanceTexture.configureChromeTextNode(textNode)
        textNode.attributedText = NSAttributedString(
            string: "帖子内容加载中...",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: appearance.subtleInk,
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
