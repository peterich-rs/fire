import AsyncDisplayKit
import UIKit

/// Root Texture node for the topic-detail page.
///
/// Owns:
/// - The `ASCollectionNode` feed surface
/// - Bottom quick reply chrome owned by the UIKit controller runtime
///
/// Layout is performed by Texture on a background thread. Geometry that
/// changes frequently (keyboard overlap) must **not** be read from
/// `layoutSpecThatFits` — that would race the layout thread and force
/// full-tree remeasure (which can freeze topic detail on entry / keyboard).
/// Keyboard lift is applied on the main thread in `layout()` as a frame offset.
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
        // Bar height includes safe-area padding — remeasure overlay once so the
        // first paint after appear is not stuck on the pre-safe-area size.
        // (setNeedsLayout alone reuses the cached calculated layout.)
        invalidateCalculatedLayout()
        setNeedsLayout()
    }

    @MainActor
    func updateKeyboardOverlap(_ overlap: CGFloat) {
        let target = max(overlap, 0)
        guard abs(keyboardOverlap - target) > 0.5 else { return }
        keyboardOverlap = target
        // Cheap path: only re-run main-thread `layout()` so the bar frame can
        // be offset and feed contentInset updated. Never invalidate the
        // Texture calculated layout for keyboard frames.
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
        applyQuickReplyKeyboardLift()
        applyFeedContentInsets()
    }

    // MARK: - Layout

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        // Pin the bar to the bottom of the root. Keyboard lift is a post-layout
        // frame offset — do not wrap the bar in ASInsetLayoutSpec(keyboard).
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

    // MARK: - Private

    /// Lift the bar above the keyboard without changing Texture calculated sizes.
    private func applyQuickReplyKeyboardLift() {
        guard !quickReplyBarNode.isHidden else { return }
        // `super.layout()` always places the bar at the bottom. When the keyboard
        // is hidden, that resting frame is already correct (no extra work).
        guard keyboardOverlap > 0.5 else { return }
        var frame = quickReplyBarNode.frame
        frame.origin.y -= keyboardOverlap
        quickReplyBarNode.frame = frame
    }

    private func applyFeedContentInsets() {
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
}

func fireTopicDetailFeedBottomInset(
    quickReplyBarHeight: CGFloat,
    safeAreaBottom: CGFloat,
    keyboardOverlap: CGFloat,
    isQuickReplyVisible: Bool
) -> CGFloat {
    isQuickReplyVisible ? quickReplyBarHeight + keyboardOverlap : safeAreaBottom
}
