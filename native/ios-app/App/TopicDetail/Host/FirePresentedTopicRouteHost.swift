import SwiftUI
import UIKit

struct FirePresentedTopicRouteHost: UIViewControllerRepresentable {
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore

    let viewModel: FireAppViewModel
    let route: FireAppRoute

    func makeUIViewController(context: Context) -> UINavigationController {
        FireAppRouteControllerFactory.makeNavigationController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            route: route
        )
    }

    func updateUIViewController(
        _ uiViewController: UINavigationController,
        context: Context
    ) {
        // Route inputs are immutable after presentation.
    }
}
