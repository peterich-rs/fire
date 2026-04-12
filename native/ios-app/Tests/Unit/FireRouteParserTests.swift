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

    func testUnsupportedURLReturnsNil() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/fire"))

        XCTAssertNil(FireRouteParser.parse(url: url))
    }
}
