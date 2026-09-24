import SwiftUI
import UIKit

struct FireComposerControllerHost: UIViewControllerRepresentable {
    let viewModel: FireAppViewModel
    let route: FireComposerRoute
    var initialBody: String? = nil
    var initialBodySelectionLocation: Int? = nil
    var initialCategoryID: UInt64? = nil
    var initialTags: [String] = []
    var onTopicCreated: ((UInt64) -> Void)?
    var onReplySubmitted: (() -> Void)?
    var onPrivateMessageCreated: ((UInt64, String) -> Void)?
    var onSubmissionNotice: ((String) -> Void)?

    func makeUIViewController(context: Context) -> UINavigationController {
        let composer = FireComposerViewController(
            viewModel: viewModel,
            route: route,
            initialBody: initialBody,
            initialBodySelectionLocation: initialBodySelectionLocation,
            initialCategoryID: initialCategoryID,
            initialTags: initialTags,
            onTopicCreated: onTopicCreated,
            onReplySubmitted: onReplySubmitted,
            onPrivateMessageCreated: onPrivateMessageCreated,
            onSubmissionNotice: onSubmissionNotice
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
