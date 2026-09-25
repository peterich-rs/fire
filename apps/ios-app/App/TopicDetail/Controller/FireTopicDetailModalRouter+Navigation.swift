import SafariServices
import UIKit

@MainActor
extension FireTopicDetailModalRouter {
    func push(route: FireAppRoute) {
        guard let navigationController = viewController?.navigationController else { return }
        let topicRoutePresenter = FireAppRouteControllerFactory.makeTopicRoutePresenter(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { [weak navigationController] in navigationController }
        )
        let controller = FireAppRouteControllerFactory.makeViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            route: route,
            topicRoutePresenter: topicRoutePresenter
        )
        navigationController.pushViewController(controller, animated: true)
    }

    func push(filterRoute: FireTopicFilterRoute) {
        guard let navigationController = viewController?.navigationController else { return }
        let topicRoutePresenter = FireAppRouteControllerFactory.makeTopicRoutePresenter(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { [weak navigationController] in navigationController }
        )
        let controller = FireFilteredTopicListViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            title: filterRoute.title,
            categorySlug: filterRoute.categorySlug,
            categoryId: filterRoute.categoryId,
            parentCategorySlug: filterRoute.parentCategorySlug,
            tag: filterRoute.tag,
            topicRoutePresenter: topicRoutePresenter
        )
        navigationController.pushViewController(controller, animated: true)
    }

    func presentProfile(username: String) {
        guard let viewController else { return }
        FireUserCard.present(from: viewController, viewModel: viewModel, username: username)
    }

    func presentWebLink(_ url: URL) {
        let controller = SFSafariViewController(url: url)
        viewController?.present(controller, animated: true)
    }

    func presentImageViewer(image: FireCookedImage) {
        guard let viewController else { return }
        let controller = FireTopicPhotoBrowserController(image: image)
        controller.present(from: viewController)
    }
}
