import AsyncDisplayKit
import UIKit

extension FireTopicDetailFeedCellFactory {
    @objc
    private func handleLoadMoreReplies() {
        onRequestLoadMore?()
    }

    func makeRepliesHeaderCellNode(
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

    func makeReplyFooterCellNode(
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
}
