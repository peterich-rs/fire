import SwiftUI
import UIKit

@MainActor
final class FireTopicDetailModalRouter {
    private weak var viewController: UIViewController?
    private let viewModel: FireAppViewModel
    private let topicDetailStore: FireTopicDetailStore

    init(
        viewController: UIViewController,
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore
    ) {
        self.viewController = viewController
        self.viewModel = viewModel
        self.topicDetailStore = topicDetailStore
    }

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
        let rootView = FireFilteredTopicListView(
            viewModel: viewModel,
            title: filterRoute.title,
            categorySlug: filterRoute.categorySlug,
            categoryId: filterRoute.categoryId,
            parentCategorySlug: filterRoute.parentCategorySlug,
            tag: filterRoute.tag
        )
        .fireTopicRoutePresenter(topicRoutePresenter)
        navigationController.pushViewController(UIHostingController(rootView: rootView), animated: true)
    }

    func presentProfile(username: String) {
        let rootView = NavigationStack {
            FirePublicProfileView(viewModel: viewModel, username: username)
        }
        let controller = UIHostingController(rootView: rootView)
        presentSheetController(controller)
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
                    try await viewModel.updateBookmark(
                        bookmarkID: bookmarkID,
                        name: name,
                        reminderAt: reminderAt,
                        recoveryOriginURL: recoveryOriginURL
                    )
                } else {
                    _ = try await viewModel.createBookmark(
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
                    try await viewModel.deleteBookmark(
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

    func presentFlagSheet(
        topicID: UInt64,
        context: FirePostManagementContext,
        onSubmitted: @escaping @MainActor (String) -> Void
    ) {
        let rootView = FireTopicDetailFlagSheetHost(
            store: topicDetailStore,
            topicID: topicID,
            context: context,
            onSubmitted: onSubmitted
        )
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentTopicVoters(_ voters: [VotedUserState], isLoading: Bool) {
        let rootView = NavigationStack {
            FireTopicVotersSheet(voters: voters, isLoading: isLoading)
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentPostReplies(
        topicID: UInt64,
        context: FirePostReplyContext,
        baseURLString: String,
        onJumpToPost: @escaping (UInt32) -> Void
    ) {
        let rootView = NavigationStack {
            FireTopicDetailPostRepliesHost(
                store: topicDetailStore,
                topicID: topicID,
                context: context,
                baseURLString: baseURLString,
                onJumpToPost: { [weak self] postNumber in
                    self?.viewController?.dismiss(animated: true) {
                        onJumpToPost(postNumber)
                    }
                }
            )
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentAdvancedComposer(
        route: FireComposerRoute,
        initialBody: String,
        onReplySubmitted: @escaping @MainActor () -> Void,
        onSubmissionNotice: @escaping @MainActor (String) -> Void
    ) {
        let rootView = NavigationStack {
            FireComposerView(
                viewModel: viewModel,
                route: route,
                initialBody: initialBody,
                onReplySubmitted: onReplySubmitted,
                onSubmissionNotice: onSubmissionNotice
            )
        }
        let controller = UIHostingController(rootView: rootView)
        controller.modalPresentationStyle = .fullScreen
        viewController?.present(controller, animated: true)
    }

    func presentImageViewer(image: FireCookedImage) {
        let rootView = FireTopicImageViewer(image: image)
        let controller = UIHostingController(rootView: rootView)
        controller.modalPresentationStyle = .fullScreen
        viewController?.present(controller, animated: true)
    }

    func presentDeleteConfirmation(
        postNumber: UInt32,
        onConfirm: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: "删除回复",
            message: "确认删除 #\(postNumber) 吗？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            onConfirm()
        })
        viewController?.present(alert, animated: true)
    }

    func presentNotice(title: String = "提示", message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        viewController?.present(alert, animated: true)
    }

    private func presentSheetController(_ controller: UIViewController) {
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        viewController?.present(controller, animated: true)
    }
}

private struct FireTopicDetailFlagSheetHost: View {
    @ObservedObject var store: FireTopicDetailStore

    let topicID: UInt64
    let context: FirePostManagementContext
    let onSubmitted: @MainActor (String) -> Void

    var body: some View {
        FirePostFlagSheet(
            context: context,
            options: FirePostFlagOption.options(from: store.postActionTypes),
            isLoadingOptions: store.isLoadingPostActionTypes
        ) { option, message in
            try await store.flagPost(
                topicID: topicID,
                postID: context.postID,
                flagTypeID: option.id,
                message: message
            )
            await MainActor.run {
                onSubmitted("举报已提交。")
            }
        }
        .task {
            await store.loadPostActionTypesIfNeeded()
        }
    }
}

private struct FireTopicDetailPostRepliesHost: View {
    @ObservedObject var store: FireTopicDetailStore

    let topicID: UInt64
    let context: FirePostReplyContext
    let baseURLString: String
    let onJumpToPost: (UInt32) -> Void

    var body: some View {
        FirePostRepliesSheet(
            post: context.post,
            replies: store.postReplies(for: context.post.id) ?? [],
            replyHistory: store.postReplyHistory(for: context.post.id) ?? [],
            isLoading: store.isLoadingPostReplyContext(postID: context.post.id),
            errorMessage: store.postReplyContextError(for: context.post.id),
            baseURLString: baseURLString,
            onJumpToPost: onJumpToPost,
            onRetry: {
                await store.loadPostReplyContextIfNeeded(
                    topicID: topicID,
                    post: context.post,
                    force: true
                )
            }
        )
        .task(id: context.post.id) {
            await store.loadPostReplyContextIfNeeded(
                topicID: topicID,
                post: context.post
            )
        }
    }
}
