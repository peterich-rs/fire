import SafariServices
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
        let rootView = FireTopicUserInfoSheet(
            viewModel: viewModel,
            username: username,
            onMessage: { [weak self] profile in
                guard let self else { return }
                self.viewController?.dismiss(animated: true) {
                    Task { @MainActor in
                        self.presentPrivateMessageComposer(
                            username: profile.username,
                            displayName: profile.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                                .ifEmpty(profile.username) ?? profile.username
                        )
                    }
                }
            }
        )
        let controller = UIHostingController(rootView: rootView)
        presentSheetController(controller)
    }

    func presentWebLink(_ url: URL) {
        let controller = SFSafariViewController(url: url)
        viewController?.present(controller, animated: true)
    }

    private func presentPrivateMessageComposer(username: String, displayName: String) {
        let rootView = NavigationStack {
            FireComposerView(
                viewModel: viewModel,
                route: FireComposerRoute(kind: .privateMessage(recipients: [username], title: nil)),
                onPrivateMessageCreated: { [weak self] topicID, title in
                    self?.viewController?.dismiss(animated: true) {
                        self?.push(route: .topic(
                            topicId: topicID,
                            postNumber: nil,
                            preview: FireTopicRoutePreview.fromMetadata(title: title, slug: nil)
                        ))
                    }
                }
            )
        }
        let controller = UIHostingController(rootView: rootView)
        controller.modalPresentationStyle = .fullScreen
        viewController?.present(controller, animated: true)
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

    func presentReactionPicker(
        post: TopicPostState,
        options: [FireReactionOption],
        onSelectReaction: @escaping @MainActor (String) -> Void,
        onShowUsers: @escaping @MainActor (String) -> Void
    ) {
        let rootView = NavigationStack {
            FirePostReactionPickerSheet(
                post: post,
                options: options,
                onSelectReaction: { [weak self] reactionID in
                    self?.viewController?.dismiss(animated: true) {
                        Task { @MainActor in
                            onSelectReaction(reactionID)
                        }
                    }
                },
                onShowUsers: { [weak self] reactionID in
                    self?.viewController?.dismiss(animated: true) {
                        Task { @MainActor in
                            onShowUsers(reactionID)
                        }
                    }
                }
            )
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentReactionUsers(
        groups: [ReactionUsersGroupState],
        reactionID: String?
    ) {
        let rootView = NavigationStack {
            FireReactionUsersSheet(groups: groups, reactionID: reactionID)
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
        initialBodySelectionLocation: Int? = nil,
        onReplySubmitted: @escaping @MainActor () -> Void,
        onSubmissionNotice: @escaping @MainActor (String) -> Void
    ) {
        let rootView = NavigationStack {
            FireComposerView(
                viewModel: viewModel,
                route: route,
                initialBody: initialBody,
                initialBodySelectionLocation: initialBodySelectionLocation,
                onReplySubmitted: onReplySubmitted,
                onSubmissionNotice: onSubmissionNotice
            )
        }
        let controller = UIHostingController(rootView: rootView)
        controller.modalPresentationStyle = .fullScreen
        viewController?.present(controller, animated: true)
    }

    func presentImageViewer(image: FireCookedImage) {
        guard let viewController else { return }
        let controller = FireTopicPhotoBrowserController(image: image)
        controller.present(from: viewController)
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

private struct FireTopicUserInfoSheet: View {
    @ObservedObject var viewModel: FireAppViewModel
    let username: String
    let onMessage: (UserProfileState) -> Void

    @State private var profile: UserProfileState?
    @State private var summary: UserSummaryState?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let profile {
                header(profile)
                FireProfileStatsRow(items: [
                    (formatNumber(summary?.stats.topicCount ?? 0), "话题"),
                    (formatNumber(summary?.stats.postCount ?? 0), "回复"),
                    (formatNumber(summary?.stats.likesReceived ?? 0), "获赞"),
                    (formatNumber(profile.totalFollowers), "粉丝"),
                ])
                metaRows(profile)
                if let bio = profile.bioCooked?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !bio.isEmpty {
                    Text(plainTextFromHtml(rawHtml: bio))
                        .font(.footnote)
                        .foregroundStyle(FireTheme.subtleInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if canSendPrivateMessage(profile) {
                    Button {
                        onMessage(profile)
                    } label: {
                        Label("发私信", systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FireTheme.accent)
                }
            } else if isLoading {
                ProgressView("正在加载用户信息...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(errorMessage ?? "无法加载用户信息。")
                    .font(.footnote)
                    .foregroundStyle(FireTheme.subtleInk)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: username) {
            await load()
        }
    }

    private func header(_ profile: UserProfileState) -> some View {
        HStack(alignment: .center, spacing: 14) {
            FireAvatarView(
                avatarTemplate: profile.avatarTemplate,
                username: profile.username,
                size: 64,
                baseURLString: viewModel.session.bootstrap.baseUrl.ifEmpty("https://linux.do")
            )

            VStack(alignment: .leading, spacing: 5) {
                Text((profile.name ?? "").ifEmpty(profile.username))
                    .font(.headline)
                    .foregroundStyle(FireTheme.ink)
                Text("@\(profile.username) · \(profile.trustLevelLabel)")
                    .font(.caption)
                    .foregroundStyle(FireTheme.tertiaryInk)
            }
        }
    }

    @ViewBuilder
    private func metaRows(_ profile: UserProfileState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let createdAt = profile.createdAt, !createdAt.isEmpty {
                FireProfileMetaEntryView(symbol: "calendar", label: "加入时间", value: createdAt)
            }
            if let lastSeenAt = profile.lastSeenAt, !lastSeenAt.isEmpty {
                FireProfileMetaEntryView(symbol: "clock", label: "最近活跃", value: lastSeenAt)
            }
            if let score = profile.gamificationScore {
                FireProfileMetaEntryView(symbol: "sparkles", label: "积分", value: formatNumber(score))
            }
        }
    }

    private func load() async {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let fetchedProfile = viewModel.fetchUserProfile(username: normalized)
            async let fetchedSummary = viewModel.fetchUserSummary(username: normalized)
            let (profile, summary) = try await (fetchedProfile, fetchedSummary)
            self.profile = profile
            self.summary = summary
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func canSendPrivateMessage(_ profile: UserProfileState) -> Bool {
        let current = viewModel.session.bootstrap.currentUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return current?.localizedCaseInsensitiveCompare(profile.username) != ComparisonResult.orderedSame
            && profile.canSendPrivateMessageToUser
    }

    private func formatNumber(_ value: UInt32) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000.0)
        }
        return "\(value)"
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
