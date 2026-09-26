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
        let node = FireTopicDetailRepliesHeaderChromeNode()
        node.onRequestLoadMore = nil
        node.apply(
            item: FireTopicDetailRuntimeItem(
                id: "replies-header",
                kind: .repliesHeader,
                postID: nil,
                postNumber: nil,
                replyIndex: nil,
                contentToken: AnyHashable("header")
            ),
            configuration: configuration,
            appearance: appearance
        )
        return node
    }

    func makeReplyFooterCellNode(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        let node = FireTopicDetailReplyFooterChromeNode()
        node.onRequestLoadMore = { [weak self] in
            self?.onRequestLoadMore?()
        }
        node.apply(item: item, configuration: configuration, appearance: appearance)
        return node
    }
}

final class FireTopicDetailRepliesHeaderChromeNode: ASCellNode, FireTopicDetailChromeCellNode {
    var onRequestLoadMore: (() -> Void)?
    private let titleNode = ASTextNode()
    private let countNode = ASTextNode()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        FireAppearanceTexture.configureChromeTextNode(titleNode)
        FireAppearanceTexture.configureChromeTextNode(countNode)
        countNode.style.flexShrink = 1
    }

    func apply(
        item _: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) {
        FireAppearanceTexture.applySnapshot(appearance, to: self)
        titleNode.attributedText = NSAttributedString(string: "回复", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .headline),
            .foregroundColor: appearance.ink,
        ])
        let countText: String
        if configuration.hasLoadedTopic {
            if configuration.loadedReplyCount < configuration.totalReplyCount {
                countText = "已加载 \(configuration.loadedReplyCount) / \(configuration.totalReplyCount) 条"
            } else {
                countText = "\(configuration.totalReplyCount) 条 · \(configuration.displayedFloorCount) 楼"
            }
        } else {
            countText = ""
        }
        countNode.attributedText = NSAttributedString(string: countText, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: appearance.subtleInk,
        ])
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_: ASSizeRange) -> ASLayoutSpec {
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1
        let stack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .start,
            alignItems: .center,
            children: [titleNode, spacer, countNode]
        )
        return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 18, left: 16, bottom: 14, right: 16), child: stack)
    }
}

final class FireTopicDetailReplyFooterChromeNode: ASCellNode, FireTopicDetailChromeCellNode {
    var onRequestLoadMore: (() -> Void)?
    private let labelNode = ASTextNode()
    private let buttonNode = ASButtonNode()
    private let indicatorNode = ASDisplayNode()
    private var showsButton = false
    private var showsIndicator = false

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        FireAppearanceTexture.configureChromeTextNode(labelNode)
        buttonNode.addTarget(self, action: #selector(handleTap), forControlEvents: .touchUpInside)
        buttonNode.fireBindPressBounce(.button)
        indicatorNode.setViewBlock {
            let view = UIActivityIndicatorView(style: .medium)
            view.startAnimating()
            return view
        }
        indicatorNode.style.preferredSize = CGSize(width: 20, height: 20)
    }

    func apply(
        item: FireTopicDetailRuntimeItem,
        configuration _: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) {
        FireAppearanceTexture.applySnapshot(appearance, to: self)
        let state = (item.contentToken.base as? String)
            .flatMap(FireTopicDetailRuntimeReplyFooterState.fromContentToken(_:))
            ?? .none
        showsButton = false
        showsIndicator = false
        labelNode.isHidden = true
        buttonNode.isHidden = true
        indicatorNode.isHidden = true
        switch state {
        case .none:
            break
        case .loadMoreAvailable:
            showsButton = true
            buttonNode.isHidden = false
            buttonNode.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
            buttonNode.setTitle("加载更多回复", with: UIFont.preferredFont(forTextStyle: .subheadline), with: FireTopicDetailCellColors.accent, for: .normal)
        case .loadFailed:
            showsButton = true
            buttonNode.isHidden = false
            buttonNode.setImage(UIImage(systemName: "arrow.clockwise.circle"), for: .normal)
            buttonNode.setTitle("加载更多回复失败，点击重试", with: UIFont.preferredFont(forTextStyle: .subheadline), with: FireTopicDetailCellColors.accent, for: .normal)
        case .emptyPrompt:
            labelNode.isHidden = false
            labelNode.attributedText = NSAttributedString(string: "还没有回复，发表你的看法吧", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: appearance.subtleInk,
            ])
        case .endReached:
            labelNode.isHidden = false
            labelNode.attributedText = NSAttributedString(string: "---- 到底了 ----", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: appearance.tertiaryInk,
            ])
        case .loadingFooter:
            showsIndicator = true
            indicatorNode.isHidden = false
            labelNode.isHidden = false
            labelNode.attributedText = NSAttributedString(string: "正在加载更多回复...", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: appearance.subtleInk,
            ])
        }
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        var children: [ASLayoutElement] = []
        if showsIndicator { children.append(indicatorNode) }
        if !labelNode.isHidden { children.append(labelNode) }
        if showsButton { children.append(buttonNode) }
        let stack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8,
            justifyContent: .center,
            alignItems: .center,
            children: children.isEmpty ? [ASLayoutSpec()] : children
        )
        stack.style.preferredSize = CGSize(width: constrainedSize.max.width, height: 44)
        return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16), child: stack)
    }

    @objc private func handleTap() {
        onRequestLoadMore?()
    }
}
