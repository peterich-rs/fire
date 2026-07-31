import UIKit
import XCTest
@testable import Fire

@MainActor
final class FireAppRoutePresentationTests: XCTestCase {
    override func tearDown() {
        FireNavigationState.shared.dismissPresentedTopicRoute()
        super.tearDown()
    }

    func testLocalPresenterIsMarkedNoOp() {
        XCTAssertTrue(FireTopicRoutePresenter.local.isLocalNoOp)
        XCTAssertFalse(FireTopicRoutePresenter.local.present(.topic(topicId: 1, postNumber: nil)))
    }

    func testAppRootPresenterIsNotNoOp() {
        let presenter = FireTopicRoutePresenter.appRoot(navigationState: FireNavigationState())
        XCTAssertFalse(presenter.isLocalNoOp)
    }

    func testCustomPresenterDefaultsNotNoOp() {
        let presenter = FireTopicRoutePresenter { _ in true }
        XCTAssertFalse(presenter.isLocalNoOp)
    }

    func testPresentCascadeUsesPreferredPresenterFirst() {
        let viewModel = FireAppViewModel()
        let store = FireTopicDetailStore(appViewModel: viewModel)
        var preferredHits = 0
        let preferred = FireTopicRoutePresenter { route in
            preferredHits += 1
            return route.isTopicRoute
        }

        let outcome = FireAppRouteControllerFactory.present(
            .topic(topicId: 42, postNumber: 3),
            preferredPresenter: preferred,
            navigationControllerProvider: { nil },
            viewModel: viewModel,
            topicDetailStore: store
        )

        XCTAssertEqual(outcome, .preferredPresenter)
        XCTAssertEqual(preferredHits, 1)
        XCTAssertNil(FireNavigationState.shared.presentedTopicRoute)
    }

    func testPresentCascadePushesOntoProvidedNavigationStackWhenPreferredDeclines() {
        let viewModel = FireAppViewModel()
        let store = FireTopicDetailStore(appViewModel: viewModel)
        let navigationController = UINavigationController(rootViewController: UIViewController())

        let outcome = FireAppRouteControllerFactory.present(
            .topic(topicId: 77, postNumber: nil),
            preferredPresenter: .local,
            navigationControllerProvider: { navigationController },
            viewModel: viewModel,
            topicDetailStore: store
        )

        XCTAssertEqual(outcome, .nestedNavigationStack)
        XCTAssertEqual(navigationController.viewControllers.count, 2)
        XCTAssertTrue(navigationController.viewControllers.last is FireTopicDetailViewController)
        XCTAssertNil(FireNavigationState.shared.presentedTopicRoute)
    }

    func testPresentCascadeFallsBackToRootSecondaryWhenNoNavAvailable() {
        let viewModel = FireAppViewModel()
        let store = FireTopicDetailStore(appViewModel: viewModel)
        let route = FireAppRoute.topic(topicId: 88, postNumber: 1)

        let outcome = FireAppRouteControllerFactory.present(
            route,
            preferredPresenter: .local,
            navigationControllerProvider: { nil },
            viewModel: viewModel,
            topicDetailStore: store
        )

        XCTAssertEqual(outcome, .rootSecondaryStack)
        XCTAssertEqual(FireNavigationState.shared.presentedTopicRoute, route)
    }

    func testPresentCascadeDoesNotSilentFailForTopicRoutes() {
        // Regression: public profile activity used `_ = presenter.present(route)` with
        // the environment default `.local`, which only produced cell selection animation.
        let viewModel = FireAppViewModel()
        let store = FireTopicDetailStore(appViewModel: viewModel)
        let action = UserActionState(
            actionType: 4,
            topicId: 1234,
            postNumber: nil,
            title: "Hello",
            slug: "hello",
            excerpt: nil,
            categoryId: nil,
            actingUsername: nil,
            actingAvatarTemplate: nil,
            createdAt: nil
        )
        guard let route = FireAppRoute.topic(action: action) else {
            return XCTFail("expected topic route from action with topicId")
        }

        let outcome = FireAppRouteControllerFactory.present(
            route,
            preferredPresenter: .local,
            navigationControllerProvider: { nil },
            viewModel: viewModel,
            topicDetailStore: store
        )

        XCTAssertNotEqual(outcome, .unhandled)
        XCTAssertEqual(outcome, .rootSecondaryStack)
    }
}
