import UIKit
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

    func testTopicRouteFromActionCapturesStablePreviewAndPostNumber() {
        let action = UserActionState(
            actionType: 5,
            topicId: 987,
            postNumber: 6,
            title: "Fire Native",
            slug: "fire-native",
            excerpt: "动态摘要",
            categoryId: 42,
            actingUsername: "alice",
            actingAvatarTemplate: nil,
            createdAt: "2026-04-18T10:00:00Z"
        )

        let route = FireAppRoute.topic(action: action)

        XCTAssertEqual(
            route,
            .topic(
                topicId: 987,
                postNumber: 6,
                preview: FireTopicRoutePreview(
                    title: "Fire Native",
                    slug: "fire-native",
                    categoryId: 42,
                    excerptText: "动态摘要"
                )
            )
        )
    }

    func testTopicRouteFromActionFallsBackToPlaceholderTitleAndSlug() {
        let action = UserActionState(
            actionType: 5,
            topicId: 321,
            postNumber: nil,
            title: nil,
            slug: "   ",
            excerpt: nil,
            categoryId: nil,
            actingUsername: nil,
            actingAvatarTemplate: nil,
            createdAt: nil
        )

        let route = FireAppRoute.topic(action: action)

        XCTAssertEqual(
            route,
            .topic(
                topicId: 321,
                postNumber: nil,
                preview: FireTopicRoutePreview(
                    title: "话题 #321",
                    slug: "topic-321",
                    categoryId: nil
                )
            )
        )
    }

    func testTopicRouteFromActionWithoutTopicIdReturnsNil() {
        let action = UserActionState(
            actionType: 5,
            topicId: nil,
            postNumber: nil,
            title: "Fire Native",
            slug: "fire-native",
            excerpt: nil,
            categoryId: 42,
            actingUsername: nil,
            actingAvatarTemplate: nil,
            createdAt: nil
        )

        XCTAssertNil(FireAppRoute.topic(action: action))
    }

    @MainActor
    func testNavigationStateKeepsFirstPresentedTopicRoute() {
        let navigationState = FireNavigationState()
        let firstRoute = FireAppRoute.topic(topicId: 321, postNumber: nil)
        let nextRoute = FireAppRoute.topic(topicId: 654, postNumber: nil)

        navigationState.presentTopicRoute(firstRoute)
        navigationState.presentTopicRoute(nextRoute)

        XCTAssertEqual(navigationState.presentedTopicRoute, firstRoute)
    }

    @MainActor
    func testNavigationStateAcceptsTopicRouteAfterDismiss() {
        let navigationState = FireNavigationState()
        let firstRoute = FireAppRoute.topic(topicId: 321, postNumber: nil)
        let nextRoute = FireAppRoute.topic(topicId: 654, postNumber: 2)

        navigationState.presentTopicRoute(firstRoute)
        navigationState.dismissPresentedTopicRoute()
        navigationState.presentTopicRoute(nextRoute)

        XCTAssertEqual(navigationState.presentedTopicRoute, nextRoute)
    }

    @MainActor
    func testMainNavigationControllerShowsBarAwayFromHiddenRoot() {
        let root = UIViewController()
        let detail = UIViewController()
        let navigationController = FireMainNavigationController(
            rootViewController: root,
            hidesNavigationBarAtRoot: true
        )

        XCTAssertTrue(navigationController.isNavigationBarHidden)

        navigationController.pushViewController(detail, animated: false)
        XCTAssertFalse(navigationController.isNavigationBarHidden)

        navigationController.updateNavigationBarVisibility(for: root, animated: false)
        XCTAssertTrue(navigationController.isNavigationBarHidden)
    }

    @MainActor
    func testMainNavigationControllerFullScreenPopThresholds() {
        let navigationController = FireMainNavigationController(rootViewController: UIViewController())

        XCTAssertFalse(navigationController.canBeginFullScreenPop(velocity: CGPoint(x: 900, y: 0)))

        navigationController.pushViewController(UIViewController(), animated: false)
        XCTAssertTrue(navigationController.canBeginFullScreenPop(velocity: CGPoint(x: 900, y: 50)))
        XCTAssertFalse(navigationController.canBeginFullScreenPop(velocity: CGPoint(x: -900, y: 0)))
        XCTAssertFalse(navigationController.canBeginFullScreenPop(velocity: CGPoint(x: 80, y: 300)))

        XCTAssertTrue(navigationController.shouldFinishFullScreenPop(progress: 0.40, velocityX: 0))
        XCTAssertTrue(navigationController.shouldFinishFullScreenPop(progress: 0.10, velocityX: 800))
        XCTAssertFalse(navigationController.shouldFinishFullScreenPop(progress: 0.20, velocityX: 200))
    }
}
