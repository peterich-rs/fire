import XCTest
@testable import Fire

final class FireRouteParserTests: XCTestCase {
    func testParseCustomTopicRouteWithPostNumberQuery() throws {
        let url = try XCTUnwrap(URL(string: "fire://topic/123?postNumber=45"))

        let route = FireRouteParser.parse(url: url)

        XCTAssertEqual(route, .topic(topicId: 123, postNumber: 45))
    }

    func testParseLinuxDoTopicRouteFromSlugPath() throws {
        let url = try XCTUnwrap(URL(string: "https://linux.do/t/fire-native/987/6?u=alice"))

        let route = FireRouteParser.parse(url: url)

        XCTAssertEqual(route, .topic(topicId: 987, postNumber: 6))
    }

    func testParseLinuxDoTopicRouteWithNumericSlug() throws {
        let url = try XCTUnwrap(URL(string: "https://linux.do/t/123/987"))

        let route = FireRouteParser.parse(url: url)

        XCTAssertEqual(route, .topic(topicId: 987, postNumber: nil))
    }

    func testParseLinuxDoTopicRouteWithNumericSlugAndPostNumber() throws {
        let url = try XCTUnwrap(URL(string: "https://linux.do/t/123/987/6"))

        let route = FireRouteParser.parse(url: url)

        XCTAssertEqual(route, .topic(topicId: 987, postNumber: 6))
    }

    func testParseLinuxDoProfileRoute() throws {
        let url = try XCTUnwrap(URL(string: "https://linux.do/u/alice/summary"))

        let route = FireRouteParser.parse(url: url)

        XCTAssertEqual(route, .profile(username: "alice"))
    }

    func testParseBadgeRoutePreservesOptionalSlug() throws {
        let url = try XCTUnwrap(URL(string: "fire://badge/42?slug=trust-level-3"))

        let route = FireRouteParser.parse(url: url)

        XCTAssertEqual(route, .badge(id: 42, slug: "trust-level-3"))
    }

    func testNotificationPayloadMapsIntoTopicRoute() {
        let route = FireRouteParser.route(
            fromNotificationUserInfo: [
                "topicId": NSNumber(value: 321),
                "postNumber": NSNumber(value: 9),
            ]
        )

        XCTAssertEqual(route, .topic(topicId: 321, postNumber: 9))
    }

    func testNotificationPayloadPreservesOptionalPreviewMetadata() {
        let route = FireRouteParser.route(
            fromNotificationUserInfo: [
                "topicId": NSNumber(value: 321),
                "postNumber": NSNumber(value: 9),
                "topicTitle": "Fire Native",
                "excerpt": "最新进展",
            ]
        )

        XCTAssertEqual(
            route,
            .topic(
                topicId: 321,
                postNumber: 9,
                preview: FireTopicRoutePreview(
                    title: "Fire Native",
                    slug: "",
                    categoryId: nil,
                    excerptText: "最新进展"
                )
            )
        )
    }

    func testUnsupportedURLReturnsNil() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/fire"))

        XCTAssertNil(FireRouteParser.parse(url: url))
    }

    // MARK: - parse(path:)

    func testParsePathWithSlugTopicIdAndPostNumber() {
        let route = FireRouteParser.parse(path: "/t/fire-native/987/6")

        XCTAssertEqual(route, .topic(topicId: 987, postNumber: 6))
    }

    func testParsePathWithSlugTopicIdPostNumberAndQuery() {
        let route = FireRouteParser.parse(path: "/t/fire-native/987/6?u=alice")

        XCTAssertEqual(route, .topic(topicId: 987, postNumber: 6))
    }

    func testParsePathWithTopicIdOnly() {
        let route = FireRouteParser.parse(path: "/t/some-slug/123")

        XCTAssertEqual(route, .topic(topicId: 123, postNumber: nil))
    }

    func testParsePathReturnsNilForEmptyPath() {
        XCTAssertNil(FireRouteParser.parse(path: "/"))
    }

    func testParsePathProfile() {
        let route = FireRouteParser.parse(path: "/u/alice/summary")

        XCTAssertEqual(route, .profile(username: "alice"))
    }

    // MARK: - postUrl fallback in notification payload

    func testNotificationPayloadFallsBackToPostUrl() {
        let route = FireRouteParser.route(
            fromNotificationUserInfo: [
                "postUrl": "/t/fire-native/987/6",
                "topicTitle": "Fire Native",
                "excerpt": "最新进展",
            ]
        )

        XCTAssertEqual(
            route,
            .topic(
                topicId: 987,
                postNumber: 6,
                preview: FireTopicRoutePreview(
                    title: "Fire Native",
                    slug: "",
                    categoryId: nil,
                    excerptText: "最新进展"
                )
            )
        )
    }

    func testNotificationPayloadFallsBackToPostUrlWithRelativeQuery() {
        let route = FireRouteParser.route(
            fromNotificationUserInfo: [
                "postUrl": "/t/fire-native/987/6?u=alice",
                "topicTitle": "Fire Native",
            ]
        )

        XCTAssertEqual(
            route,
            .topic(
                topicId: 987,
                postNumber: 6,
                preview: FireTopicRoutePreview(
                    title: "Fire Native",
                    slug: "",
                    categoryId: nil,
                    excerptText: nil
                )
            )
        )
    }

    func testNotificationPayloadFallsBackToPostUrlAbsoluteURL() {
        let route = FireRouteParser.route(
            fromNotificationUserInfo: [
                "postUrl": "https://linux.do/t/fire-native/987/6",
            ]
        )

        XCTAssertEqual(route, .topic(topicId: 987, postNumber: 6))
    }

    func testNotificationPayloadPrefersTopicIdOverPostUrl() {
        let route = FireRouteParser.route(
            fromNotificationUserInfo: [
                "topicId": NSNumber(value: 321),
                "postNumber": NSNumber(value: 9),
                "postUrl": "/t/fire-native/987/6",
            ]
        )

        XCTAssertEqual(route, .topic(topicId: 321, postNumber: 9))
    }

    func testNotificationPayloadFallsBackToPostUrlWhenTopicIdIsNegativeNSNumber() {
        let route = FireRouteParser.route(
            fromNotificationUserInfo: [
                "topicId": NSNumber(value: -1),
                "postUrl": "/t/fire-native/987/6",
            ]
        )

        XCTAssertEqual(route, .topic(topicId: 987, postNumber: 6))
    }

    func testNotificationPayloadReturnsNilWithoutTopicIdOrPostUrl() {
        let route = FireRouteParser.route(
            fromNotificationUserInfo: [
                "topicTitle": "Fire Native",
            ]
        )

        XCTAssertNil(route)
    }
}
