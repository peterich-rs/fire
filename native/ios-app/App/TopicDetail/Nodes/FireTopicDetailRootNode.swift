import AsyncDisplayKit
import UIKit

/// Root Texture node for the topic-detail page.
///
/// Owns only the feed surface. Bottom quick-reply chrome is a pure UIKit view
/// owned by `FireTopicDetailViewController` and layered above this node — that
/// is the WeChat model and avoids Texture compositing feed text through the bar.
///
/// Feed bottom inset is driven by the controller via `updateFeedBottomInset`.
final class FireTopicDetailRootNode: ASDisplayNode {
    let feedNode: ASCollectionNode
    private var topChromeInset: CGFloat = 0
    private var bottomChromeInset: CGFloat = 0

    init(feedNode: ASCollectionNode) {
        self.feedNode = feedNode
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = FireTheme.uiCanvas
        isOpaque = true
        self.feedNode.style.flexGrow = 1.0
        self.feedNode.style.flexShrink = 1.0
    }

    @MainActor
    func updateTopChromeInset(_ inset: CGFloat) {
        guard abs(topChromeInset - inset) > 0.5 else { return }
        topChromeInset = max(inset, 0)
        applyFeedContentInsets()
    }

    /// Space reserved under the feed for the quick-reply bar (+ keyboard when up).
    @MainActor
    func updateFeedBottomInset(_ inset: CGFloat) {
        guard abs(bottomChromeInset - inset) > 0.5 else { return }
        bottomChromeInset = max(inset, 0)
        applyFeedContentInsets()
    }

    override func layout() {
        super.layout()
        applyFeedContentInsets()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASWrapperLayoutSpec(layoutElement: feedNode)
    }

    private func applyFeedContentInsets() {
        // layout() is main-thread; still guard so call sites never touch UIScrollView off-main.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyFeedContentInsets()
            }
            return
        }
        guard feedNode.isNodeLoaded,
              let scrollView = feedNode.view as? UIScrollView else { return }
        var insets = scrollView.contentInset
        insets.top = topChromeInset
        insets.bottom = bottomChromeInset
        if abs(scrollView.contentInset.top - insets.top) > 0.5
            || abs(scrollView.contentInset.bottom - insets.bottom) > 0.5 {
            scrollView.contentInset = insets
            scrollView.scrollIndicatorInsets = insets
        }
    }
}

/// Feed bottom inset for topic detail.
///
/// When the quick-reply bar is visible, pass `barHeight + keyboardOverlap`.
/// When hidden, pass the home-indicator safe-area inset only.
func fireTopicDetailFeedBottomInset(
    quickReplyBarHeight: CGFloat,
    safeAreaBottom: CGFloat,
    keyboardOverlap: CGFloat,
    isQuickReplyVisible: Bool
) -> CGFloat {
    isQuickReplyVisible ? quickReplyBarHeight + keyboardOverlap : safeAreaBottom
}
