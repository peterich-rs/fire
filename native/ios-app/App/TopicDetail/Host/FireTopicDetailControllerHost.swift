import SwiftUI

/// Thin `UIViewControllerRepresentable` bridge that passes immutable route inputs
/// into `FireTopicDetailViewController` and owns nothing else.
///
/// This is the only SwiftUI surface that remains in the topic-detail path.
/// All page lifecycle, state, and presentation are owned by the controller.
struct FireTopicDetailControllerHost: UIViewControllerRepresentable {
    let viewModel: FireAppViewModel
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    func makeUIViewController(context: Context) -> FireTopicDetailViewController {
        FireTopicDetailViewController(
            viewModel: viewModel,
            row: row,
            scrollToPostNumber: scrollToPostNumber
        )
    }

    func updateUIViewController(
        _ uiViewController: FireTopicDetailViewController,
        context: Context
    ) {
        // Route inputs are immutable after creation.
        // No update logic is intentional here.
    }
}
