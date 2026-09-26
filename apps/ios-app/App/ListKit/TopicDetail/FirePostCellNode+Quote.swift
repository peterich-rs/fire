import AsyncDisplayKit
import UIKit

final class FireTopicQuoteNode: ASDisplayNode {
    private let barNode = ASDisplayNode()
    private let bodyNode = ASTextNode()

    init(attributedText: NSAttributedString) {
        super.init()
        automaticallyManagesSubnodes = true
        isOpaque = false
        backgroundColor = FireTheme.uiCanvas
        barNode.backgroundColor = FireTopicDetailCellColors.accent.withAlphaComponent(0.45)
        barNode.style.preferredSize = CGSize(width: 3, height: 1)
        barNode.style.flexGrow = 1
        bodyNode.attributedText = attributedText
        bodyNode.maximumNumberOfLines = 0
        bodyNode.style.flexShrink = 1
        FireAppearanceTexture.configureChromeTextNode(bodyNode)
    }

    func apply(attributedText: NSAttributedString) {
        bodyNode.attributedText = attributedText
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .start,
            alignItems: .stretch,
            children: [barNode, bodyNode]
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0),
            child: row
        )
    }
}

extension FirePostCellNode {
    func configureQuote(payload: FirePostCellRenderPayload) {
        if let replyContext = payload.replyContext,
           let targetPN = payload.replyTargetPostNumber, targetPN > 0 {
            replyContextNode.isHidden = false
            let replyContextFont = UIFont.preferredFont(forTextStyle: .caption1)
            replyContextNode.setAttributedTitle(NSAttributedString(
                string: replyContext,
                attributes: [.font: replyContextFont, .foregroundColor: Self.accentTextColor]
            ), for: .normal)
        } else {
            replyContextNode.isHidden = true
            replyContextNode.setAttributedTitle(nil, for: .normal)
        }
    }
}
