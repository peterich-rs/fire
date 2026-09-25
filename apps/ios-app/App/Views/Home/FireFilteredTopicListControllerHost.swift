import Combine
import SwiftUI
import UIKit

struct FireFilteredTopicListControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore

    let viewModel: FireAppViewModel
    let title: String
    let categorySlug: String?
    let categoryId: UInt64?
    let parentCategorySlug: String?
    let tag: String?

    func makeUIViewController(context: Context) -> FireFilteredTopicListViewController {
        FireFilteredTopicListViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            title: title,
            categorySlug: categorySlug,
            categoryId: categoryId,
            parentCategorySlug: parentCategorySlug,
            tag: tag,
            topicRoutePresenter: topicRoutePresenter
        )
    }

    func updateUIViewController(
        _ uiViewController: FireFilteredTopicListViewController,
        context: Context
    ) {
        uiViewController.updateTopicRoutePresenter(topicRoutePresenter)
    }
}
