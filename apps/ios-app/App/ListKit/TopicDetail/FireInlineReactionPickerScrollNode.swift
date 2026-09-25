import AsyncDisplayKit
import UIKit

/// Horizontal scroller for the inline quick-reaction strip so narrow devices
/// never clip trailing emoji buttons.
final class FireInlineReactionPickerScrollNode: ASScrollNode {
    var buttons: [ASButtonNode] = [] {
        didSet { setNeedsLayout() }
    }

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        automaticallyManagesContentSize = true
        scrollableDirections = [.left, .right]
    }

    override func didLoad() {
        super.didLoad()
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.alwaysBounceVertical = false
        view.clipsToBounds = true
        view.contentInsetAdjustmentBehavior = .never
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: FirePostCellLayoutCalculator.reactionPickerButtonSpacing,
            justifyContent: .start,
            alignItems: .center,
            children: buttons
        )
        // Keep vertical centering inside the strip height.
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 8),
            child: row
        )
    }
}
