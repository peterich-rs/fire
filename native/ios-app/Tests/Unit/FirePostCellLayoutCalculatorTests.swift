import UIKit
import XCTest
@testable import Fire

final class FirePostCellLayoutCalculatorTests: XCTestCase {
    func testCalculateAlignsContentColumnAndDividerWithReplyRowContract() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 42,
            depth: 1,
            showsThreadLine: true,
            showsDivider: true,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            hasReactions: false,
            acceptedAnswer: false,
            trait: trait
        )

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: 40,
            imageHeights: [],
            trait: trait
        )

        XCTAssertEqual(layout.avatarFrame.origin.x, 16, accuracy: 0.01)
        XCTAssertEqual(layout.avatarFrame.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(layout.avatarFrame.width, 32, accuracy: 0.01)
        XCTAssertEqual(layout.metaFrame.minY, 8, accuracy: 0.01)
        XCTAssertEqual(layout.textFrame?.minY ?? -.greatestFiniteMagnitude, 36, accuracy: 0.01)
        XCTAssertEqual(layout.dividerFrame?.minX ?? -.greatestFiniteMagnitude, 16, accuracy: 0.01)
        XCTAssertEqual(layout.dividerFrame?.width ?? -.greatestFiniteMagnitude, 288, accuracy: 0.01)
        XCTAssertEqual(layout.totalHeight, 84.5, accuracy: 0.01)
        XCTAssertEqual(layout.threadLineFrame?.minY ?? -.greatestFiniteMagnitude, 38, accuracy: 0.01)
    }

    func testMeasureRichTextHeightGrowsAsAvailableWidthShrinks() {
        let attributedText = NSAttributedString(
            string: String(repeating: "Fire native reply row ", count: 12),
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
            ]
        )

        let wideHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: attributedText,
            containerWidth: 240,
            contentSizeCategory: .large
        )
        let narrowHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: attributedText,
            containerWidth: 120,
            contentSizeCategory: .large
        )

        XCTAssertNotNil(wideHeight)
        XCTAssertNotNil(narrowHeight)
        XCTAssertGreaterThan(narrowHeight ?? 0, wideHeight ?? 0)
    }

    func testAvailableContentWidthAccountsForIndentAvatarAndOuterPadding() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 360,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 7,
            depth: 3,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            hasReactions: false,
            acceptedAnswer: false,
            trait: trait
        )

        let availableWidth = FirePostCellLayoutCalculator.availableContentWidth(
            for: key,
            trait: trait
        )

        XCTAssertEqual(availableWidth, 256, accuracy: 0.01)
    }
}