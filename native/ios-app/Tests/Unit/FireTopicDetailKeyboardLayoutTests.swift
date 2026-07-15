import AsyncDisplayKit
import XCTest
@testable import Fire

final class FireTopicDetailKeyboardLayoutTests: XCTestCase {
    @MainActor
    func testQuickReplyBarHeightIncludesSafeAreaButNotKeyboard() {
        let zeroInset = measuredQuickReplyBarHeight(bottomInset: 0)
        let withSafeArea = measuredQuickReplyBarHeight(bottomInset: 34)

        XCTAssertEqual(withSafeArea, zeroInset + 34, accuracy: 1.0)
    }

    @MainActor
    private func measuredQuickReplyBarHeight(bottomInset: CGFloat) -> CGFloat {
        let node = FireTopicQuickReplyBarNode()
        node.apply(state: FireTopicDetailQuickReplyState(
            isVisible: true,
            typingSummary: nil,
            targetSummary: nil,
            placeholder: "快速回复…",
            draft: "",
            isSubmitting: false,
            validationMessage: nil
        ))
        node.updateLayoutWidth(393)
        node.updateBottomInset(bottomInset)
        return node.layoutThatFits(ASSizeRange(
            min: CGSize(width: 393, height: 0),
            max: CGSize(width: 393, height: 852)
        )).size.height
    }

    func testFeedBottomInsetAddsKeyboardOverlapOnlyWhenQuickReplyVisible() {
        XCTAssertEqual(
            fireTopicDetailFeedBottomInset(
                quickReplyBarHeight: 92,
                safeAreaBottom: 34,
                keyboardOverlap: 300,
                isQuickReplyVisible: true
            ),
            392
        )

        XCTAssertEqual(
            fireTopicDetailFeedBottomInset(
                quickReplyBarHeight: 92,
                safeAreaBottom: 34,
                keyboardOverlap: 300,
                isQuickReplyVisible: false
            ),
            34
        )
    }
}
