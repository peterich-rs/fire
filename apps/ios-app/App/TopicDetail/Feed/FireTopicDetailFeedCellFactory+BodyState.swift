import AsyncDisplayKit
import UIKit

extension FireTopicDetailFeedCellFactory {
    @objc
    private func handleLoadTopicDetail() {
        guard let configuration else { return }
        Task { await configuration.onLoadTopicDetail() }
    }

    func makeBodyStateCellNode(
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

    func makeTextCellNode(
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

    func makeMissingPostCellNode(appearance: FireAppearanceSnapshot) -> ASCellNode {
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
