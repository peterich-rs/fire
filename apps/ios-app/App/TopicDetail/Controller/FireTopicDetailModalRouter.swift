import SafariServices
import SwiftUI
import UIKit

@MainActor
final class FireTopicDetailModalRouter {
    weak var viewController: UIViewController?
    let viewModel: FireAppViewModel
    let topicDetailStore: FireTopicDetailStore

    init(
        viewController: UIViewController,
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore
    ) {
        self.viewController = viewController
        self.viewModel = viewModel
        self.topicDetailStore = topicDetailStore
    }
}
