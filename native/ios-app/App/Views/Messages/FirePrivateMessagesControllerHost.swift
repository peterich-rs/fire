import Combine
import SwiftUI
import UIKit

struct FirePrivateMessagesControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore

    let viewModel: FireAppViewModel

    func makeUIViewController(context: Context) -> FirePrivateMessagesViewController {
        FirePrivateMessagesViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            topicRoutePresenter: topicRoutePresenter
        )
    }

    func updateUIViewController(
        _ uiViewController: FirePrivateMessagesViewController,
        context: Context
    ) {
        uiViewController.updateTopicRoutePresenter(topicRoutePresenter)
    }
}
