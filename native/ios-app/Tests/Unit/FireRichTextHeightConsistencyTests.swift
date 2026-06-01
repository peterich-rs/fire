import AsyncDisplayKit
import XCTest
@testable import Fire

final class FireRichTextHeightConsistencyTests: XCTestCase {
    func testASTextNodeMeasureMatchesRenderHeight() {
        let attributedText = NSAttributedString(
            string: "Hello, this is a test string for measuring rich text height consistency.",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.label,
            ]
        )

        let width: CGFloat = 300
        let measuredHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: attributedText,
            containerWidth: width,
            contentSizeCategory: .medium
        )

        XCTAssertNotNil(measuredHeight)
        XCTAssertGreaterThan(measuredHeight!, 0)

        // Verify ASTextNode.measure() and display use the same engine
        let textNode = ASTextNode()
        textNode.attributedText = attributedText
        textNode.maximumNumberOfLines = 0
        let layout = textNode.layoutThatFits(ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        ))

        XCTAssertEqual(ceil(layout.size.height), measuredHeight!, "ASTextNode layoutThatFits should produce the same height as measureRichTextHeight")
    }

    func testEmptyTextReturnsNil() {
        let result = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: nil,
            containerWidth: 300,
            contentSizeCategory: .medium
        )
        XCTAssertNil(result)

        let emptyResult = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: NSAttributedString(string: ""),
            containerWidth: 300,
            contentSizeCategory: .medium
        )
        XCTAssertNil(emptyResult)
    }

    func testMultilineTextHeightIsGreaterThanSingleLine() {
        let singleLine = NSAttributedString(
            string: "Short",
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)]
        )
        let multiLine = NSAttributedString(
            string: "This is a much longer text that will definitely wrap to multiple lines when constrained to a narrow width.",
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)]
        )

        let singleHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: singleLine,
            containerWidth: 100,
            contentSizeCategory: .medium
        )
        let multiHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: multiLine,
            containerWidth: 100,
            contentSizeCategory: .medium
        )

        XCTAssertNotNil(singleHeight)
        XCTAssertNotNil(multiHeight)
        XCTAssertGreaterThan(multiHeight!, singleHeight!)
    }

    func testWiderContainerProducesShorterOrEqualHeight() {
        let text = NSAttributedString(
            string: "This is a test string that spans multiple lines in narrow containers but fewer in wider ones.",
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)]
        )

        let narrowHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: text,
            containerWidth: 100,
            contentSizeCategory: .medium
        )
        let wideHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: text,
            containerWidth: 400,
            contentSizeCategory: .medium
        )

        XCTAssertNotNil(narrowHeight)
        XCTAssertNotNil(wideHeight)
        XCTAssertLessThanOrEqual(wideHeight!, narrowHeight!)
    }
}
