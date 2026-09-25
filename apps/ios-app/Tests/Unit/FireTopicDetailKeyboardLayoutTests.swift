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
        let state = FireTopicDetailQuickReplyState(
            isVisible: true,
            typingSummary: nil,
            targetSummary: nil,
            placeholder: "快速回复…",
            draft: "",
            isSubmitting: false,
            validationMessage: nil
        )
        return FireTopicQuickReplyBarView.estimatedHeight(
            state: state,
            width: 393,
            bottomInset: bottomInset
        )
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

    func testFeedBottomInsetWhenKeyboardHiddenUsesBarHeightOnly() {
        // Resting state: bar height already includes safe-area padding; do not
        // add safeAreaBottom again on top of the bar.
        XCTAssertEqual(
            fireTopicDetailFeedBottomInset(
                quickReplyBarHeight: 92,
                safeAreaBottom: 34,
                keyboardOverlap: 0,
                isQuickReplyVisible: true
            ),
            92
        )
    }

    @MainActor
    func testQuickReplyBarHeightGrowsWithWrappedDraft() {
        let short = FireTopicDetailQuickReplyState(
            isVisible: true,
            typingSummary: nil,
            targetSummary: nil,
            placeholder: "快速回复…",
            draft: "短回复",
            isSubmitting: false,
            validationMessage: nil
        )
        let long = FireTopicDetailQuickReplyState(
            isVisible: true,
            typingSummary: nil,
            targetSummary: nil,
            placeholder: "快速回复…",
            draft: String(repeating: "这是一段会换行的快捷回复内容", count: 6),
            isSubmitting: false,
            validationMessage: nil
        )
        let shortHeight = FireTopicQuickReplyBarView.estimatedHeight(
            state: short,
            width: 393,
            bottomInset: 0
        )
        let longHeight = FireTopicQuickReplyBarView.estimatedHeight(
            state: long,
            width: 393,
            bottomInset: 0
        )
        XCTAssertGreaterThan(longHeight, shortHeight + 8)
        XCTAssertLessThanOrEqual(
            longHeight - shortHeight,
            FireBottomInputBar.maximumInputHeight()
        )
    }
}
