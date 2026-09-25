import SwiftUI
import UIKit

@MainActor
extension FireTopicDetailModalRouter {
    private func presentPrivateMessageComposer(username: String, displayName: String) {
        let composer = FireComposerViewController(
            viewModel: viewModel,
            route: FireComposerRoute(kind: .privateMessage(recipients: [username], title: nil)),
            onPrivateMessageCreated: { [weak self] topicID, title in
                self?.push(route: .topic(
                    topicId: topicID,
                    postNumber: nil,
                    preview: FireTopicRoutePreview.fromMetadata(title: title, slug: nil)
                ))
            }
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        viewController?.present(navigationController, animated: true)
    }

    func presentBookmarkEditor(
        context: FireBookmarkEditorContext,
        recoveryOriginURL: URL,
        onReload: @escaping @MainActor () async -> Void
    ) {
        let rootView = FireBookmarkEditorSheet(
            context: context,
            onSave: { [viewModel] name, reminderAt in
                if let bookmarkID = context.bookmarkID {
                    try await viewModel.topicInteraction.updateBookmark(
                        bookmarkID: bookmarkID,
                        name: name,
                        reminderAt: reminderAt,
                        recoveryOriginURL: recoveryOriginURL
                    )
                } else {
                    _ = try await viewModel.topicInteraction.createBookmark(
                        bookmarkableID: context.bookmarkableID,
                        bookmarkableType: context.bookmarkableType,
                        name: name,
                        reminderAt: reminderAt,
                        recoveryOriginURL: recoveryOriginURL
                    )
                }
                await onReload()
            },
            onDelete: context.bookmarkID.map { [viewModel] bookmarkID in
                {
                    try await viewModel.topicInteraction.deleteBookmark(
                        bookmarkID: bookmarkID,
                        recoveryOriginURL: recoveryOriginURL
                    )
                    await onReload()
                }
            }
        )
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentPostEditor(
        topicID: UInt64,
        context: FirePostEditorContext,
        onSaved: @escaping @MainActor () async -> Void
    ) {
        let rootView = NavigationStack {
            FirePostEditorView(
                viewModel: viewModel,
                topicID: topicID,
                postID: context.postID,
                postNumber: context.postNumber,
                onSaved: {
                    Task { await onSaved() }
                }
            )
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentTopicEditor(
        topicID: UInt64,
        initialTitle: String,
        initialCategoryID: UInt64?,
        initialTags: [String],
        onSaved: @escaping @MainActor () async -> Void
    ) {
        let rootView = NavigationStack {
            FireTopicEditorView(
                viewModel: viewModel,
                topicID: topicID,
                initialTitle: initialTitle,
                initialCategoryID: initialCategoryID,
                initialTags: initialTags,
                onSaved: {
                    Task { await onSaved() }
                }
            )
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentAdvancedComposer(
        route: FireComposerRoute,
        initialBody: String,
        initialBodySelectionLocation: Int? = nil,
        onReplySubmitted: @escaping @MainActor () -> Void,
        onSubmissionNotice: @escaping @MainActor (String) -> Void,
        scrollToCreatedReply: Bool = false
    ) {
        let composer = FireComposerViewController(
            viewModel: viewModel,
            route: route,
            initialBody: initialBody,
            initialBodySelectionLocation: initialBodySelectionLocation,
            onReplySubmitted: onReplySubmitted,
            onSubmissionNotice: onSubmissionNotice,
            scrollToCreatedReply: scrollToCreatedReply
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        viewController?.present(navigationController, animated: true)
    }

    func presentBoostComposer(onSubmit: @escaping (String) -> Void) {
        let controller = FireBoostInputViewController()
        controller.onSubmit = onSubmit
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            // Keep a single medium detent. Custom short detents + keyboard overlap
            // previously produced unsatisfiable top/bottom constraints.
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.preferredCornerRadius = 18
        }
        viewController?.present(controller, animated: true)
    }
}
