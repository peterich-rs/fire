import AsyncDisplayKit
import UIKit

extension FireTopicDetailFeedCellFactory {
    func makeStatsCellNode(
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

    func configureChromeTextNode(_ node: ASTextNode) {
        FireAppearanceTexture.configureChromeTextNode(node)
    }
}
