import XCTest
@testable import Fire

final class FireRichTextParagraphBoundaryTests: XCTestCase {
    func testSingleParagraphDoesNotAddTrailingBlockBoundary() {
        let html = "<p>Hello</p>"
        let text = renderedText(html)

        XCTAssertEqual(text, "Hello")
    }

    func testConsecutiveParagraphsHaveOneBlankLine() {
        let html = "<p>Hello</p><p>World</p>"
        let text = renderedText(html)

        XCTAssertEqual(text, "Hello\n\nWorld")
    }

    func testHeadingFollowedByParagraphHasNoExtraNewlines() {
        let html = "<h2>Title</h2><p>Body text</p>"
        let text = renderedText(html)

        XCTAssertEqual(text, "Title\n\nBody text")
    }

    func testCodeBlockFollowedByParagraphHasNoExtraNewlines() {
        let html = "<pre><code>let x = 1</code></pre><p>Explanation</p>"
        let text = renderedText(html)

        XCTAssertEqual(text, "let x = 1\n\nExplanation")
    }

    func testBlockquoteFollowedByParagraphHasNoExtraNewlines() {
        let html = "<blockquote><p>Quote</p></blockquote><p>Response</p>"
        let text = renderedText(html)

        XCTAssertFalse(text.contains("\n\n\n"), "Blockquote + paragraph should not produce triple newlines, got: \(text.debugDescription)")
        XCTAssertTrue(text.contains("\n\nResponse"), "Blockquote should be separated from following paragraph, got: \(text.debugDescription)")
    }

    func testDividerFollowedByParagraphHasNoExtraNewlines() {
        let html = "<hr><p>After divider</p>"
        let text = renderedText(html)

        XCTAssertEqual(text, "----------\n\nAfter divider")
    }

    func testMultipleHeadingsDoNotAccumulateNewlines() {
        let html = "<h1>H1</h1><h2>H2</h2><h3>H3</h3>"
        let text = renderedText(html)

        XCTAssertEqual(text, "H1\n\nH2\n\nH3")
    }

    private func renderedText(_ html: String) -> String {
        FireTopicPresentation.renderContent(from: html, baseURLString: "https://linux.do")
            .attributedText?
            .string ?? ""
    }
}
