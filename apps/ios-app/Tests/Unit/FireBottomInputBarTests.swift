import XCTest
@testable import Fire

final class FireBottomInputBarTests: XCTestCase {
    @MainActor
    func testEmptyTextUsesSingleLineHeight() {
        let height = FireBottomInputBar.estimatedWrappedHeight(text: "", width: 300)
        XCTAssertEqual(height, FireBottomInputBar.minimumInputHeight, accuracy: 0.5)
    }

    @MainActor
    func testLongTextGrowsAboveSingleLine() {
        let long = String(repeating: "这是一段足够长的中文内容用来触发自动换行", count: 4)
        let height = FireBottomInputBar.estimatedWrappedHeight(text: long, width: 300)
        XCTAssertGreaterThan(height, FireBottomInputBar.minimumInputHeight + 8)
    }

    @MainActor
    func testLongTextCapsAtFiveLines() {
        let huge = String(repeating: "abcdefghijklmnopqrstuvwxyz ", count: 40)
        let height = FireBottomInputBar.estimatedWrappedHeight(text: huge, width: 260)
        XCTAssertLessThanOrEqual(height, FireBottomInputBar.maximumInputHeight() + 1)
        XCTAssertGreaterThan(height, FireBottomInputBar.minimumInputHeight)
    }

    @MainActor
    func testChatBarIntrinsicHeightGrowsWithText() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIView(frame: window.bounds)
        window.addSubview(host)

        let bar = FireBottomInputBar(kind: .chat)
        host.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor),
        ])

        bar.apply(text: "hi", placeholder: "发消息…", isSending: false, isEnabled: true)
        window.layoutIfNeeded()
        let shortHeight = bar.bounds.height > 1 ? bar.bounds.height : bar.intrinsicContentSize.height

        let longText = String(repeating: "自动换行测试内容 ", count: 18)
        bar.apply(text: longText, placeholder: "发消息…", isSending: false, isEnabled: true)
        window.layoutIfNeeded()
        let longHeight = bar.bounds.height > 1 ? bar.bounds.height : bar.intrinsicContentSize.height

        XCTAssertGreaterThan(shortHeight, 1)
        XCTAssertGreaterThan(
            FireBottomInputBar.estimatedWrappedHeight(text: longText, width: 390),
            FireBottomInputBar.minimumInputHeight + 8
        )
        XCTAssertGreaterThan(longHeight, shortHeight)
        XCTAssertLessThanOrEqual(longHeight, 280)
    }

    @MainActor
    func testSendStaysDisabledForEmptyTextWithoutImages() {
        let bar = FireBottomInputBar(kind: .chat)
        bar.apply(text: "   ", placeholder: "发消息…", isSending: false, isEnabled: true)
        XCTAssertTrue(bar.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(bar.currentImages.isEmpty)
    }
}
