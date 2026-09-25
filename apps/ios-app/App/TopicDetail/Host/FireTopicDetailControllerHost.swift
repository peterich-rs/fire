import SwiftUI

/// Thin `UIViewControllerRepresentable` bridge that passes immutable route inputs
/// into `FireTopicDetailViewController` and owns nothing else.
///
/// This is the only SwiftUI surface that remains in the topic-detail path.
/// All page lifecycle, state, and presentation are owned by the controller.
struct FireTopicDetailControllerHost: UIViewControllerRepresentable {
    @EnvironmentObject private var topicDetailStore: FireTopicDetailStore

    let viewModel: FireAppViewModel
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    func makeUIViewController(context: Context) -> FireTopicDetailViewController {
        viewModel.topicRouteLogger()?.info(
            "topic detail controller host make ui controller topic_id=\(row.topic.id) post_number=\(scrollToPostNumber.map(String.init) ?? "nil")"
        )
        let controller = FireTopicDetailViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            row: row,
            scrollToPostNumber: scrollToPostNumber
        )
        viewModel.topicRouteLogger()?.debug(
            "topic detail controller host make ui controller complete topic_id=\(row.topic.id)"
        )
        return controller
    }

    func updateUIViewController(
        _ uiViewController: FireTopicDetailViewController,
        context: Context
    ) {
        // Route inputs are immutable after creation.
        // No update logic is intentional here.
    }
}
