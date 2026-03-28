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

        XCTAssertEqual(plainText, "Hello\nFire\n\n Rust\n CI")
    }

    func testBuildRowPresentationsPrecomputesListRenderingFields() throws {
        let topic = TopicSummaryState(
            id: 42,
            title: "Fire Native",
            slug: "fire-native",
            postsCount: 18,
            replyCount: 17,
            views: 2048,
            likeCount: 32,
            excerpt: "<p>Hello&nbsp;<strong>Fire</strong></p>",
            createdAt: "2026-03-28T10:00:00Z",
            lastPostedAt: "2026-03-28T11:30:00Z",
            lastPosterUsername: nil,
            categoryId: 7,
            pinned: true,
            visible: true,
            closed: false,
            archived: false,
            tags: [TopicTagState(id: nil, name: "rust", slug: nil)],
            posters: [TopicPosterState(userId: 9, description: nil, extras: nil)],
            unseen: false,
            unreadPosts: 3,
            newPosts: 1,
            lastReadPostNumber: nil,
            highestPostNumber: 18,
            hasAcceptedAnswer: false,
            canHaveAnswer: true
        )

        let row = try XCTUnwrap(FireTopicPresentation.buildRowPresentations(from: [topic]).first)

        XCTAssertEqual(row.excerptText, "Hello Fire")
        XCTAssertEqual(row.lastPosterUsername, "User 9")
        XCTAssertEqual(row.statusLabels, ["Pinned", "Unread 3", "New 1"])
        XCTAssertEqual(row.tagSummaryText, "#rust")
        XCTAssertNotNil(row.activityTimestampText)
    }
}
