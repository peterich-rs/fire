import AsyncDisplayKit
import UIKit

/// Root Texture node for the topic-detail page.
///
/// Owns:
/// - The `ASCollectionNode` feed surface
/// - Bottom quick reply chrome owned by the UIKit controller runtime
///
/// Layout is performed by Texture on a background thread.
final class FireTopicDetailRootNode: ASDisplayNode {
    let feedNode: ASCollectionNode
    let quickReplyBarNode: FireTopicQuickReplyBarNode
    private var bottomSafeAreaInset: CGFloat = 0

    // MARK: - Init

    init(
        feedNode: ASCollectionNode,
        quickReplyBarNode: FireTopicQuickReplyBarNode
    ) {
        self.feedNode = feedNode
        self.quickReplyBarNode = quickReplyBarNode
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .systemBackground
        self.feedNode.style.flexGrow = 1.0
        self.feedNode.style.flexShrink = 1.0
    }

    @MainActor
    func updateBottomSafeAreaInset(_ inset: CGFloat) {
        guard abs(bottomSafeAreaInset - inset) > 0.5 else { return }
        bottomSafeAreaInset = inset
        quickReplyBarNode.updateBottomInset(inset)
        setNeedsLayout()
    }

    override func layout() {
        super.layout()
        guard let scrollView = feedNode.view as? UIScrollView else { return }
        var insets = scrollView.contentInset
        if !quickReplyBarNode.isHidden {
            insets.bottom = quickReplyBarNode.calculatedSize.height
        } else {
            insets.bottom = bottomSafeAreaInset
        }
        if abs(scrollView.contentInset.bottom - insets.bottom) > 0.5 {
            scrollView.contentInset = insets
            scrollView.scrollIndicatorInsets = insets
        }
    }

    // MARK: - Layout

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if !quickReplyBarNode.isHidden {
            let replyOverlay = ASRelativeLayoutSpec(
                horizontalPosition: .start,
                verticalPosition: .end,
                sizingOption: [],
                child: quickReplyBarNode
            )
            return ASOverlayLayoutSpec(child: feedNode, overlay: replyOverlay)
        }
        return ASWrapperLayoutSpec(layoutElement: feedNode)
    }
}
