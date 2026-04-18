import XCTest
@testable import Fire

final class FireAppRouteTests: XCTestCase {
    func testTopicRouteFromRowCapturesStablePreview() {
        let row = TopicRowState.routeStub(
            topicId: 987,
            title: "Fire Native",
            slug: "fire-native",
            categoryId: 42,
            tagNames: ["swift", "ios"],
            statusLabels: ["已关闭"],
            excerptText: "预览摘要",
            isPinned: true,
            isClosed: true,
            hasAcceptedAnswer: true,
            hasUnreadPosts: true
        )
        let route = FireAppRoute.topic(row: row)

        XCTAssertEqual(
            route,
            .topic(topicId: 987, postNumber: nil, preview: FireTopicRoutePreview(row: row))
        )

        guard case .topic(let payload) = route else {
            return XCTFail("expected topic route")
        }

        XCTAssertEqual(payload.row.topic.title, "Fire Native")
        XCTAssertEqual(payload.row.topic.slug, "fire-native")
        XCTAssertEqual(payload.row.tagNames, ["swift", "ios"])
        XCTAssertEqual(payload.row.statusLabels, ["已关闭"])
        XCTAssertEqual(payload.row.excerptText, "预览摘要")
        XCTAssertTrue(payload.row.isPinned)
        XCTAssertTrue(payload.row.isClosed)
        XCTAssertTrue(payload.row.hasAcceptedAnswer)
        XCTAssertTrue(payload.row.hasUnreadPosts)
    }

    func testTopicRoutePreviewBuildsTopicRowMetadata() {
        let preview = FireTopicRoutePreview(
            title: "Fire Native",
            slug: "fire-native",
            categoryId: 42,
            tagNames: ["swift", "ios"],
            statusLabels: ["已关闭"],
            excerptText: "预览摘要",
            isClosed: true
        )
        let route = FireAppRoute.topic(topicId: 987, postNumber: 6, preview: preview)

        guard case .topic(let payload) = route else {
            return XCTFail("expected topic route")
        }

        XCTAssertEqual(payload.row.topic.id, 987)
        XCTAssertEqual(payload.row.topic.title, "Fire Native")
        XCTAssertEqual(payload.row.topic.slug, "fire-native")
        XCTAssertEqual(payload.row.topic.categoryId, 42)
        XCTAssertEqual(payload.row.tagNames, ["swift", "ios"])
        XCTAssertEqual(payload.row.statusLabels, ["已关闭"])
        XCTAssertEqual(payload.row.excerptText, "预览摘要")
        XCTAssertTrue(payload.row.isClosed)
        XCTAssertEqual(payload.postNumber, 6)
    }

    func testTopicRouteWithoutPreviewFallsBackToPlaceholderTitle() {
        let route = FireAppRoute.topic(topicId: 321, postNumber: nil)

        guard case .topic(let payload) = route else {
            return XCTFail("expected topic route")
        }

        XCTAssertEqual(payload.row.topic.title, "话题 321")
        XCTAssertEqual(payload.row.topic.slug, "")
        XCTAssertEqual(payload.row.tagNames, [])
    }
}
