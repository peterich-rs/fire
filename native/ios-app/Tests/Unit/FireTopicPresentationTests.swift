import XCTest
@testable import Fire

final class FireTopicPresentationTests: XCTestCase {
    func testParseCategoriesReadsSiteCategories() {
        let categories = FireTopicPresentation.parseCategories(
            from: """
            {
              "site": {
                "categories": [
                  {
                    "id": 7,
                    "name": "Rust",
                    "slug": "rust",
                    "parent_category_id": 2,
                    "color": "FFFFFF",
                    "text_color": "000000"
                  }
                ]
              }
            }
            """
        )

        XCTAssertEqual(categories[7]?.name, "Rust")
        XCTAssertEqual(categories[7]?.slug, "rust")
        XCTAssertEqual(categories[7]?.parentCategoryID, 2)
        XCTAssertEqual(categories[7]?.colorHex, "FFFFFF")
        XCTAssertEqual(categories[7]?.textColorHex, "000000")
    }

    func testNextPageReadsRelativeAndAbsoluteMoreTopicsURLs() {
        XCTAssertEqual(FireTopicPresentation.nextPage(from: "/latest?page=3"), 3)
        XCTAssertEqual(FireTopicPresentation.nextPage(from: "https://linux.do/latest?page=9"), 9)
        XCTAssertNil(FireTopicPresentation.nextPage(from: "/latest"))
        XCTAssertNil(FireTopicPresentation.nextPage(from: nil))
    }

    func testPlainTextNormalizesHTMLContent() {
        let plainText = FireTopicPresentation.plainText(
            from: "<p>Hello<br>Fire</p><ul><li>Rust</li><li>CI</li></ul>"
        )

        XCTAssertEqual(plainText, "Hello Fire \nRust \nCI")
    }
}
