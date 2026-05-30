import SwiftUI

struct FireTopicDetailListHost: UIViewControllerRepresentable {
    let configuration: FireTopicDetailRuntimeConfiguration

    func makeUIViewController(context: Context) -> FireTopicDetailListViewController {
        FireTopicDetailListViewController()
    }

    func updateUIViewController(
        _ uiViewController: FireTopicDetailListViewController,
        context: Context
    ) {
        uiViewController.update(configuration: configuration)
    }
}
