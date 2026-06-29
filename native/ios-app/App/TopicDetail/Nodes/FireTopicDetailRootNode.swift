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
    private var keyboardOverlap: CGFloat = 0
    private var topChromeInset: CGFloat = 0

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

    @MainActor
    func updateKeyboardOverlap(_ overlap: CGFloat) {
        let target = max(overlap, 0)
        guard abs(keyboardOverlap - target) > 0.5 else { return }
        keyboardOverlap = target
        invalidateCalculatedLayout()
        setNeedsLayout()
    }

    @MainActor
    func updateTopChromeInset(_ inset: CGFloat) {
        guard abs(topChromeInset - inset) > 0.5 else { return }
        topChromeInset = inset
        setNeedsLayout()
    }

    override func layout() {
        super.layout()
        guard let scrollView = feedNode.view as? UIScrollView else { return }
        var insets = scrollView.contentInset
        insets.top = topChromeInset
        insets.bottom = fireTopicDetailFeedBottomInset(
            quickReplyBarHeight: quickReplyBarNode.calculatedSize.height,
            safeAreaBottom: bottomSafeAreaInset,
            keyboardOverlap: keyboardOverlap,
            isQuickReplyVisible: !quickReplyBarNode.isHidden
        )
        if abs(scrollView.contentInset.top - insets.top) > 0.5
            || abs(scrollView.contentInset.bottom - insets.bottom) > 0.5 {
            scrollView.contentInset = insets
            scrollView.scrollIndicatorInsets = insets
        }
    }

    // MARK: - Layout

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if !quickReplyBarNode.isHidden {
            let liftedBar = ASInsetLayoutSpec(
                insets: UIEdgeInsets(
                    top: 0,
                    left: 0,
                    bottom: keyboardOverlap,
                    right: 0
                ),
                child: quickReplyBarNode
            )
            let replyOverlay = ASRelativeLayoutSpec(
                horizontalPosition: .start,
                verticalPosition: .end,
                sizingOption: [],
                child: liftedBar
            )
            return ASOverlayLayoutSpec(child: feedNode, overlay: replyOverlay)
        }
        return ASWrapperLayoutSpec(layoutElement: feedNode)
    }
}

func fireTopicDetailFeedBottomInset(
    quickReplyBarHeight: CGFloat,
    safeAreaBottom: CGFloat,
    keyboardOverlap: CGFloat,
    isQuickReplyVisible: Bool
) -> CGFloat {
    isQuickReplyVisible ? quickReplyBarHeight + keyboardOverlap : safeAreaBottom
}
