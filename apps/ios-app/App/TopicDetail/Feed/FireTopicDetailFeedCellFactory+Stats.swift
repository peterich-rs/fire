import AsyncDisplayKit
import UIKit

extension FireTopicDetailFeedCellFactory {
    func makeStatsCellNode(
        configuration: FireTopicDetailRuntimeConfiguration,
        layoutWidth: CGFloat,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        let node = FireTopicDetailStatsChromeNode()
        node.apply(
            item: FireTopicDetailRuntimeItem(
                id: "stats",
                kind: .stats,
                postID: nil,
                postNumber: nil,
                replyIndex: nil,
                contentToken: AnyHashable(layoutWidth)
            ),
            configuration: configuration,
            appearance: appearance
        )
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

final class FireTopicDetailStatsChromeNode: ASCellNode, FireTopicDetailChromeCellNode {
    private let dividerNode = ASDisplayNode()
    private let replyValue = ASTextNode()
    private let viewValue = ASTextNode()
    private let interactionValue = ASTextNode()
    private let replyLabel = ASTextNode()
    private let viewLabel = ASTextNode()
    private let interactionLabel = ASTextNode()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        [replyValue, viewValue, interactionValue, replyLabel, viewLabel, interactionLabel].forEach {
            FireAppearanceTexture.configureChromeTextNode($0)
        }
    }

    func apply(
        item _: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) {
        FireAppearanceTexture.applySnapshot(appearance, to: self)
        dividerNode.backgroundColor = appearance.divider
        replyValue.attributedText = Self.value("\(configuration.displayedReplyCount)", ink: appearance.ink)
        viewValue.attributedText = Self.value("\(configuration.displayedViewsCount)", ink: appearance.ink)
        interactionValue.attributedText = Self.value(
            configuration.displayedInteractionCount.map(String.init) ?? "...",
            ink: appearance.ink
        )
        replyLabel.attributedText = Self.caption("回复", ink: appearance.subtleInk)
        viewLabel.attributedText = Self.caption("浏览", ink: appearance.subtleInk)
        interactionLabel.attributedText = Self.caption("互动", ink: appearance.subtleInk)
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        func column(_ value: ASTextNode, _ label: ASTextNode) -> ASLayoutElement {
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 2,
                justifyContent: .start,
                alignItems: .center,
                children: [value, label]
            )
            stack.style.flexGrow = 1
            stack.style.flexShrink = 1
            return stack
        }
        dividerNode.style.preferredSize = CGSize(width: max(constrainedSize.max.width, 1), height: 0.5)
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [
                column(replyValue, replyLabel),
                column(viewValue, viewLabel),
                column(interactionValue, interactionLabel),
            ]
        )
        let root = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [dividerNode, row]
        )
        return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 12, left: 16, bottom: 8, right: 16), child: root)
    }

    private static func value(_ text: String, ink: UIColor) -> NSAttributedString {
        let captionFont = UIFont.preferredFont(forTextStyle: .subheadline)
        return NSAttributedString(string: text, attributes: [
            .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                for: UIFont.monospacedDigitSystemFont(ofSize: captionFont.pointSize, weight: .semibold)
            ),
            .foregroundColor: ink,
        ])
    }

    private static func caption(_ text: String, ink: UIColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .caption2),
            .foregroundColor: ink,
        ])
    }
}
