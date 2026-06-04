import Combine
import UIKit

@MainActor
final class FireTopicDetailViewController: UIViewController {
    let viewModel: FireAppViewModel
    let topicDetailStore: FireTopicDetailStore
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    private let feedController: FireTopicDetailFeedController
    private let paginationCoordinator: FireTopicDetailPaginationCoordinator
    private let visibilityCoordinator: FireTopicDetailVisibilityCoordinator
    private let layoutManager = FirePostLayoutManager()
    private let quickReplyBarNode: FireTopicQuickReplyBarNode
    let rootNode: FireTopicDetailRootNode

    private lazy var feedUpdatePipeline = FireTopicDetailFeedUpdatePipeline(
        feedController: feedController,
        paginationCoordinator: paginationCoordinator,
        visibilityCoordinator: visibilityCoordinator
    )

    private lazy var modalRouter = FireTopicDetailModalRouter(
        viewController: self,
        viewModel: viewModel,
        topicDetailStore: topicDetailStore
    )

    private lazy var toolbarCoordinator = FireTopicDetailToolbarCoordinator(
        viewController: self,
        actions: .init(
            onPresentTopicEditor: { [weak self] in
                self?.presentTopicEditor()
            },
            onPresentBookmarkEditor: { [weak self] in
                self?.presentTopicBookmarkEditor()
            },
            onUpdateNotificationLevel: { [weak self] option in
                self?.updateTopicNotificationLevel(option)
            }
        )
    )

    private lazy var runtimeInteractions = FireTopicDetailRuntimeInteractions(
        isMutatingPost: { [weak self] postID in
            self?.topicDetailStore.isMutatingPost(postId: postID) ?? false
        },
        isPostTextExpanded: { [weak self] postID in
            self?.expandedPostTextIDs.contains(postID) ?? false
        },
        isReplyThreadExpanded: { [weak self] postID in
            self?.expandedReplyRootPostIDs.contains(postID) ?? false
        },
        isLoadingPostReplyContext: { [weak self] postID in
            self?.topicDetailStore.isLoadingPostReplyContext(postID: postID) ?? false
        },
        onVisiblePostNumbersChanged: { [weak self] visiblePostNumbers in
            self?.handleVisiblePostNumbersChanged(visiblePostNumbers)
        },
        onRefresh: { [weak self] in
            await self?.performRefresh()
        },
        onLoadTopicDetail: { [weak self] in
            await self?.loadTopicDetail(force: true)
        },
        onScrollTargetHandled: { [weak self] postNumber in
            guard let self else { return }
            self.topicDetailStore.markScrollTargetSatisfied(
                topicId: self.topic.id,
                postNumber: postNumber
            )
        },
        onLoadMoreTopicPosts: { [weak self] in
            guard let self else { return false }
            return self.topicDetailStore.loadMoreTopicPostsIfNeeded(topicId: self.topic.id)
        },
        onReloadTopicAiSummary: { [weak self] in
            guard let self else { return }
            self.topicDetailStore.reloadTopicAiSummary(topicId: self.topic.id)
        },
        onOpenComposer: { [weak self] post in
            self?.openComposer(replyToPost: post)
        },
        onOpenPostNumber: { [weak self] postNumber in
            self?.openPostNumber(postNumber)
        },
        onOpenPostReplies: { [weak self] post in
            self?.openPostReplies(for: post)
        },
        onLinkTapped: { [weak self] url in
            self?.handleRichTextLink(url)
        },
        onOpenImage: { [weak self] image in
            self?.modalRouter.presentImageViewer(image: image)
        },
        onToggleLike: { [weak self] post in
            self?.toggleLike(for: post)
        },
        onSelectReaction: { [weak self] post, reactionID in
            self?.toggleReaction(reactionID, for: post)
        },
        onEditPost: { [weak self] post in
            self?.presentPostEditor(post)
        },
        onBookmarkPost: { [weak self] post in
            self?.presentPostBookmarkEditor(post)
        },
        onDeletePost: { [weak self] post in
            self?.confirmDelete(post)
        },
        onRecoverPost: { [weak self] post in
            self?.recoverPost(post)
        },
        onFlagPost: { [weak self] post in
            self?.presentFlagSheet(post)
        },
        onExpandPostText: { [weak self] post in
            self?.expandedPostTextIDs.insert(post.id)
            self?.buildAndApplySnapshot()
        },
        onVotePoll: { [weak self] post, poll, options in
            self?.submitPollVote(for: post, poll: poll, options: options)
        },
        onUnvotePoll: { [weak self] post, poll in
            self?.removePollVote(for: post, poll: poll)
        },
        onToggleTopicVote: { [weak self] in
            await self?.toggleTopicVote()
        },
        onShowTopicVoters: { [weak self] in
            await self?.presentTopicVoters()
        },
        onOpenCategory: { [weak self] category in
            self?.modalRouter.push(filterRoute: .category(category))
        },
        onOpenTag: { [weak self] tagName in
            self?.modalRouter.push(filterRoute: .tag(tagName))
        }
    )

    private let snapshotAssembler = FireTopicDetailSnapshotAssembler()
    private let detailOwnerToken: String
    private let timingTracker: FireTopicTimingTracker

    private var initialLoadTask: Task<Void, Never>?
    private var subscriptionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var expandedPostTextIDs: Set<UInt64> = []
    private var expandedReplyRootPostIDs: Set<UInt64> = []
    private var composerContext: FireReplyComposerContext?
    private var replyDraft = ""
    private var quickReplyError: String?
    private var keyboardFrameInScreen: CGRect = .null

    init(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        row: FireTopicRowPresentation,
        scrollToPostNumber: UInt32?
    ) {
        self.viewModel = viewModel
        self.topicDetailStore = topicDetailStore
        self.row = row
        self.scrollToPostNumber = scrollToPostNumber
        self.feedController = FireTopicDetailFeedController()
        self.paginationCoordinator = FireTopicDetailPaginationCoordinator()
        self.visibilityCoordinator = FireTopicDetailVisibilityCoordinator()
        self.quickReplyBarNode = FireTopicQuickReplyBarNode()
        self.rootNode = FireTopicDetailRootNode(
            feedNode: feedController.collectionNode,
            quickReplyBarNode: quickReplyBarNode
        )
        self.detailOwnerToken = "ios.topic-detail.\(row.topic.id).\(UUID().uuidString.lowercased())"
        self.timingTracker = FireTopicTimingTracker(topicId: row.topic.id)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        initialLoadTask?.cancel()
        subscriptionTask?.cancel()
    }

    override func loadView() {
        view = rootNode.view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.tintColor = FireTopicDetailCellColors.accent
        configureRuntime()
        configureNavigationAppearance()
        toolbarCoordinator.configureNavigationItem(navigationItem)
        updateDismissButtonIfNeeded()
        beginPageLifecycle()
        buildAndApplySnapshot()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        quickReplyBarNode.updateLayoutWidth(view.bounds.width)
        updateBottomChromeInset()
        feedController.invalidateLayoutIfWidthChanged()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomChromeInset()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationAppearance()
        updateDismissButtonIfNeeded()
        viewModel.setAPMRoute("topic.detail.\(row.topic.id)")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled =
            (navigationController?.viewControllers.count ?? 0) > 1
        Task {
            await timingTracker.setSceneActive(true)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            endPageLifecycle()
        }
        viewModel.restoreTopLevelAPMRoute()
        Task {
            await timingTracker.stop()
            await topicDetailStore.endTopicReplyPresence(topicId: row.topic.id)
        }
    }

    private var topic: TopicSummaryState {
        row.topic
    }

    private var detail: TopicDetailState? {
        topicDetailStore.topicDetail(for: topic.id)
    }

    private var displayedTopicTitle: String {
        let trimmedDetailTitle = detail?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailTitle.isEmpty {
            return trimmedDetailTitle
        }
        let trimmedRowTitle = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRowTitle.isEmpty ? "话题 \(topic.id)" : trimmedRowTitle
    }

    private var displayedTopicSlug: String {
        let trimmedDetailSlug = detail?.slug.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailSlug.isEmpty {
            return trimmedDetailSlug
        }
        return topic.slug.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedCategoryId: UInt64? {
        detail?.categoryId ?? topic.categoryId
    }

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var canWriteInteractions: Bool {
        viewModel.canStartAuthenticatedMutation
    }

    private var minimumReplyLength: Int {
        let minLength = isPrivateMessageThread
            ? viewModel.session.bootstrap.minPersonalMessagePostLength
            : viewModel.session.bootstrap.minPostLength
        return FireTopicPresentation.minimumReplyLength(from: minLength)
    }

    private var isPrivateMessageThread: Bool {
        FireTopicPresentation.isPrivateMessageArchetype(detail?.archetype)
    }

    private var topicCloudflareRecoveryURL: URL {
        viewModel.cloudflareRecoveryTopicURL(
            topicId: topic.id,
            topicSlug: displayedTopicSlug
        )
    }

    private var topicBookmarkContext: FireBookmarkEditorContext {
        FireBookmarkEditorContext(
            bookmarkID: detail?.bookmarkId,
            bookmarkableID: topic.id,
            bookmarkableType: "Topic",
            title: displayedTopicTitle,
            initialName: detail?.bookmarkName,
            initialReminderAt: detail?.bookmarkReminderAt,
            allowsDelete: detail?.bookmarkId != nil
        )
    }

    private func postBookmarkContext(for post: TopicPostState) -> FireBookmarkEditorContext {
        let username = post.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return FireBookmarkEditorContext(
            bookmarkID: post.bookmarkId,
            bookmarkableID: post.id,
            bookmarkableType: "Post",
            title: username.isEmpty ? "#\(post.postNumber)" : "#\(post.postNumber) · \(username)",
            initialName: post.bookmarkName,
            initialReminderAt: post.bookmarkReminderAt,
            allowsDelete: post.bookmarkId != nil
        )
    }

    private func configureRuntime() {
        feedController.paginationCoordinator = paginationCoordinator
        feedController.visibilityCoordinator = visibilityCoordinator
        feedController.layoutManager = layoutManager
        feedController.onRefresh = { [weak self] in
            await self?.performRefresh()
        }
        feedController.onBackgroundTap = { [weak self] in
            self?.quickReplyBarNode.resignInputFocus()
        }
        feedController.setup()

        paginationCoordinator.feedController = feedController

        visibilityCoordinator.feedController = feedController
        visibilityCoordinator.onVisiblePostNumbersChanged = { [weak self] visiblePostNumbers in
            self?.handleVisiblePostNumbersChanged(visiblePostNumbers)
        }
        visibilityCoordinator.onScrollTargetHandled = { [weak self] postNumber in
            guard let self else { return }
            self.topicDetailStore.markScrollTargetSatisfied(
                topicId: self.topic.id,
                postNumber: postNumber
            )
        }

        layoutManager.onSnapshotRevisionChanged = { [weak self] in
            self?.handleLayoutRevisionChanged()
        }

        quickReplyBarNode.callbacks = .init(
            onDraftChanged: { [weak self] draft in
                self?.replyDraft = draft
                self?.quickReplyError = nil
                self?.buildAndApplySnapshot()
            },
            onSubmit: { [weak self] in
                self?.submitQuickReply()
            },
            onOpenAdvancedComposer: { [weak self] in
                self?.openAdvancedComposer()
            },
            onClearTarget: { [weak self] in
                self?.clearComposerTarget()
            },
            onFocusChanged: { [weak self] focused in
                self?.handleQuickReplyFocusChanged(focused)
            }
        )
    }

    private func beginPageLifecycle() {
        topicDetailStore.beginTopicDetailLifecycle(
            topicId: row.topic.id,
            ownerToken: detailOwnerToken
        )

        timingTracker.start { [weak viewModel] topicId, topicTimeMs, timings in
            guard let viewModel else { return false }
            return await viewModel.reportTopicTimings(
                topicId: topicId,
                topicTimeMs: topicTimeMs,
                timings: timings
            )
        }

        subscribeToKeyboardNotifications()
        subscribeToStoreRevisions()
        kickOffInitialLoad()
        kickOffMessageBusSubscription()
    }

    private func endPageLifecycle() {
        initialLoadTask?.cancel()
        initialLoadTask = nil
        subscriptionTask?.cancel()
        subscriptionTask = nil
        cancellables.removeAll()

        topicDetailStore.endTopicDetailLifecycle(
            topicId: row.topic.id,
            ownerToken: detailOwnerToken,
            visibleTopicIDs: viewModel.currentVisibleTopicIDs()
        )
    }

    private func kickOffInitialLoad() {
        initialLoadTask?.cancel()
        initialLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadTopicDetail(targetPostNumber: self.scrollToPostNumber)
        }
    }

    private func updateDismissButtonIfNeeded() {
        let isRootPresentedTopic =
            navigationController?.presentingViewController != nil
            && navigationController?.viewControllers.count == 1
        if isRootPresentedTopic {
            let dismissAction = UIAction { [weak self] _ in
                self?.dismissPresentedTopicDetail()
            }
            let dismissItem = UIBarButtonItem(
                title: "返回",
                image: UIImage(systemName: "chevron.backward"),
                primaryAction: dismissAction
            )
            dismissItem.accessibilityLabel = "返回"
            navigationItem.leftBarButtonItem = dismissItem
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    private func dismissPresentedTopicDetail() {
        navigationController?.dismiss(animated: true)
    }

    private func configureNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.shadowColor = .separator
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
        ]

        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = FireTopicDetailCellColors.accent
    }

    private func kickOffMessageBusSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            await self.topicDetailStore.maintainTopicDetailSubscription(
                topicId: self.row.topic.id,
                ownerToken: self.detailOwnerToken
            )
        }
    }

    func loadTopicDetail(
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        let topicSlug = displayedTopicSlug
        await topicDetailStore.loadTopicDetail(
            topicId: row.topic.id,
            topicSlug: topicSlug.isEmpty ? nil : topicSlug,
            targetPostNumber: targetPostNumber,
            force: force
        )
    }

    private func subscribeToStoreRevisions() {
        let topicId = row.topic.id
        topicDetailStore.$topicCollectionRevisions
            .map { revisions in revisions[topicId] ?? 0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.buildAndApplySnapshot()
            }
            .store(in: &cancellables)
    }

    private func subscribeToKeyboardNotifications() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleKeyboardNotification(notification)
            }
            .store(in: &cancellables)
    }

    private func buildCurrentPageState() -> FireTopicDetailPageState {
        let topicId = row.topic.id
        let store = topicDetailStore

        return FireTopicDetailPageState(
            detail: store.topicDetail(for: topicId),
            renderState: store.topicRenderState(for: topicId),
            postLookup: store.topicPostLookup(for: topicId),
            topicAiSummary: store.topicAiSummary(for: topicId),
            isLoadingTopic: store.isLoadingTopic(topicId: topicId),
            isLoadingMoreTopicPosts: store.isLoadingMoreTopicPosts(topicId: topicId),
            loadMoreTopicPostsError: store.loadMoreTopicPostsError(topicId: topicId),
            isLoadingTopicAiSummary: store.isLoadingTopicAiSummary(topicId: topicId),
            hasMoreTopicPosts: store.hasMoreTopicPosts(topicId: topicId),
            detailError: store.errorMessage(for: topicId),
            detailNotice: store.detailNotice(topicId: topicId),
            topicAiSummaryError: store.topicAiSummaryError(for: topicId),
            loadingPostReplyContextIDs: store.loadingPostReplyContextIDs,
            mutatingPostIDs: store.mutatingPostIDs,
            typingUsers: store.topicPresenceUsers(for: topicId),
            topicCollectionRevision: store.topicCollectionRevision(topicId: topicId),
            pendingScrollTarget: store.pendingScrollTarget(topicId: topicId),
            currentUsername: viewModel.session.bootstrap.currentUsername,
            baseURLString: baseURLString,
            canWriteInteractions: canWriteInteractions,
            expandedPostTextIDs: expandedPostTextIDs,
            expandedReplyRootPostIDs: expandedReplyRootPostIDs,
            composerContext: composerContext,
            replyDraft: replyDraft,
            quickReplyError: quickReplyError,
            isSubmittingReply: store.isSubmittingReply(topicId: topicId),
            minimumReplyLength: minimumReplyLength,
            row: row,
            displayedCategory: viewModel.categoryPresentation(for: detail?.categoryId ?? row.topic.categoryId)
        )
    }

    private func buildRuntimeConfiguration(from state: FireTopicDetailPageState) -> FireTopicDetailRuntimeConfiguration {
        FireTopicDetailRuntimeConfiguration(
            viewModel: viewModel,
            displayedCategory: state.displayedCategory,
            currentUsername: state.currentUsername,
            row: state.row,
            baseURLString: state.baseURLString,
            detail: state.detail,
            renderState: state.renderState,
            pendingScrollTarget: state.pendingScrollTarget,
            detailError: state.detailError,
            detailNotice: state.detailNotice,
            hasMoreTopicPosts: state.hasMoreTopicPosts,
            isLoadingTopic: state.isLoadingTopic,
            isLoadingMoreTopicPosts: state.isLoadingMoreTopicPosts,
            loadMoreTopicPostsError: state.loadMoreTopicPostsError,
            topicAiSummary: state.topicAiSummary,
            isLoadingTopicAiSummary: state.isLoadingTopicAiSummary,
            topicAiSummaryError: state.topicAiSummaryError,
            topicCollectionRevision: state.topicCollectionRevision,
            canWriteInteractions: state.canWriteInteractions,
            postLookup: state.postLookup,
            snapshotInvalidationToken: AnyHashable(FireTopicDetailPageInvalidationToken(
                topicID: state.topic.id,
                topicCollectionRevision: state.topicCollectionRevision,
                pendingScrollTarget: state.pendingScrollTarget,
                detailError: state.detailError ?? "",
                detailNotice: state.detailNotice,
                hasDetail: state.detail != nil,
                isLoadingTopic: state.isLoadingTopic,
                isLoadingMoreTopicPosts: state.isLoadingMoreTopicPosts,
                loadMoreTopicPostsError: state.loadMoreTopicPostsError ?? "",
                hasMoreTopicPosts: state.hasMoreTopicPosts,
                canWriteInteractions: state.canWriteInteractions,
                currentUsername: state.currentUsername ?? "",
                baseURLString: state.baseURLString,
                expandedPostTextIDs: state.expandedPostTextIDs,
                expandedReplyRootPostIDs: state.expandedReplyRootPostIDs,
                loadingPostReplyContextIDs: state.loadingPostReplyContextIDs
            )),
            interactions: runtimeInteractions
        )
    }

    private func buildAndApplySnapshot() {
        let pageState = buildCurrentPageState()
        let configuration = buildRuntimeConfiguration(from: pageState)
        let snapshot = snapshotAssembler.buildSnapshot(
            from: pageState,
            configuration: configuration
        )
        toolbarCoordinator.apply(state: snapshot.toolbarState)
        quickReplyBarNode.apply(state: snapshot.quickReplyState)
        feedUpdatePipeline.apply(snapshot: snapshot, configuration: configuration)
    }

    private func handleLayoutRevisionChanged() {
        guard let snapshot = feedUpdatePipeline.currentSnapshot,
              let configuration = feedUpdatePipeline.currentConfiguration else {
            return
        }
        feedController.applyPublishedLayoutRevision(
            publishedKeys: layoutManager.currentPublishedKeys,
            items: snapshot.items,
            configuration: configuration
        )
    }

    private func performRefresh() async {
        timingTracker.recordInteraction()
        topicDetailStore.clearTopicDetailAnchor(topicId: topic.id)
        await loadTopicDetail(force: true)
    }

    private func handleKeyboardNotification(_ notification: Notification) {
        if notification.name == UIResponder.keyboardWillHideNotification {
            keyboardFrameInScreen = .null
        } else {
            keyboardFrameInScreen =
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
        }
        updateBottomChromeInset(animatedWith: notification)
    }

    private func updateBottomChromeInset(animatedWith notification: Notification? = nil) {
        rootNode.updateBottomSafeAreaInset(currentBottomChromeInset)

        guard let notification else { return }
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
            .doubleValue ?? 0.25
        let curveRawValue = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?
            .uintValue ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    private var currentBottomChromeInset: CGFloat {
        max(view.safeAreaInsets.bottom, keyboardOverlapHeight)
    }

    private var keyboardOverlapHeight: CGFloat {
        guard !keyboardFrameInScreen.isNull else {
            return 0
        }
        let frameInView = view.convert(keyboardFrameInScreen, from: nil)
        return max(view.bounds.intersection(frameInView).height, 0)
    }

    private func handleVisiblePostNumbersChanged(_ visiblePostNumbers: Set<UInt32>) {
        if !visiblePostNumbers.isEmpty {
            timingTracker.recordInteraction()
        }
        timingTracker.updateVisiblePostNumbers(visiblePostNumbers)

        topicDetailStore.handleVisiblePostNumbersChanged(
            topicId: topic.id,
            visiblePostNumbers: visiblePostNumbers
        )
    }

    private func handleRichTextLink(_ url: URL) {
        timingTracker.recordInteraction()

        guard let route = FireRouteParser.parse(url: url) else {
            UIApplication.shared.open(url)
            return
        }

        switch route {
        case .profile(let username):
            modalRouter.presentProfile(username: username)
        case .topic(let payload):
            handleTopicLink(payload)
        case .badge:
            modalRouter.push(route: route)
        }
    }

    private func handleTopicLink(_ payload: FireTopicRoutePayload) {
        if payload.topicId == topic.id {
            guard let postNumber = payload.postNumber else { return }
            openPostNumber(postNumber)
            return
        }
        modalRouter.push(route: .topic(payload: payload))
    }

    private func handleQuickReplyFocusChanged(_ focused: Bool) {
        if focused {
            topicDetailStore.beginTopicReplyPresence(topicId: topic.id)
        } else {
            Task {
                await topicDetailStore.endTopicReplyPresence(topicId: topic.id)
            }
        }
    }

    private func openComposer(replyToPost: TopicPostState?) {
        composerContext = FireReplyComposerContext(
            topicId: topic.id,
            postId: replyToPost?.id,
            replyToPostNumber: replyToPost?.postNumber,
            replyToUsername: replyToPost?.username
        )
        buildAndApplySnapshot()
        quickReplyBarNode.focusInput()
    }

    private func openPostNumber(_ postNumber: UInt32) {
        guard postNumber > 0 else { return }
        Task {
            await loadTopicDetail(targetPostNumber: postNumber)
        }
    }

    private func openPostReplies(for post: TopicPostState) {
        expandedReplyRootPostIDs.insert(post.id)
        buildAndApplySnapshot()
        Task {
            await topicDetailStore.loadPostReplyContextIfNeeded(
                topicID: topic.id,
                post: post
            )
        }
    }

    private func clearComposerTarget() {
        composerContext = nil
        buildAndApplySnapshot()
    }

    private func openAdvancedComposer() {
        let context = composerContext
            ?? FireReplyComposerContext(
                topicId: topic.id,
                postId: nil,
                replyToPostNumber: nil,
                replyToUsername: nil
            )
        quickReplyBarNode.resignInputFocus()
        modalRouter.presentAdvancedComposer(
            route: FireComposerRoute(
                kind: .advancedReply(
                    topicID: topic.id,
                    topicTitle: displayedTopicTitle,
                    categoryID: displayedCategoryId,
                    replyToPostNumber: context.replyToPostNumber,
                    replyToUsername: context.replyToUsername,
                    isPrivateMessage: isPrivateMessageThread
                )
            ),
            initialBody: replyDraft,
            onReplySubmitted: { [weak self] in
                guard let self else { return }
                self.replyDraft = ""
                self.composerContext = nil
                self.quickReplyError = nil
                self.buildAndApplySnapshot()
                Task {
                    await self.loadTopicDetail(force: true)
                }
            },
            onSubmissionNotice: { [weak self] message in
                self?.modalRouter.presentNotice(message: message)
            }
        )
    }

    private func submitQuickReply() {
        let trimmed = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            quickReplyError = "回复内容不能为空。"
            buildAndApplySnapshot()
            return
        }
        guard trimmed.count >= minimumReplyLength else {
            quickReplyError = "回复至少需要 \(minimumReplyLength) 个字。"
            buildAndApplySnapshot()
            return
        }

        let topicId = composerContext?.topicId ?? topic.id
        let replyToPostNumber = composerContext?.replyToPostNumber
        quickReplyError = nil
        buildAndApplySnapshot()

        Task { @MainActor in
            do {
                try await topicDetailStore.submitReply(
                    topicId: topicId,
                    raw: trimmed,
                    replyToPostNumber: replyToPostNumber
                )
                replyDraft = ""
                composerContext = nil
                quickReplyBarNode.resignInputFocus()
                buildAndApplySnapshot()
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("pending review") {
                    replyDraft = ""
                    composerContext = nil
                    quickReplyBarNode.resignInputFocus()
                    buildAndApplySnapshot()
                    modalRouter.presentNotice(message: "回复已提交，等待审核。")
                    return
                }
                quickReplyError = message
                buildAndApplySnapshot()
            }
        }
    }

    private func toggleLike(for post: TopicPostState) {
        applyReactionChange(
            from: post.currentUserReaction,
            to: post.currentUserReaction?.id == "heart" ? nil : "heart",
            postId: post.id
        )
    }

    private func toggleReaction(_ reactionId: String, for post: TopicPostState) {
        let trimmedReactionID = reactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReactionID.isEmpty else { return }
        applyReactionChange(
            from: post.currentUserReaction,
            to: post.currentUserReaction?.id == trimmedReactionID ? nil : trimmedReactionID,
            postId: post.id
        )
    }

    private func applyReactionChange(
        from currentReaction: TopicReactionState?,
        to desiredReactionID: String?,
        postId: UInt64
    ) {
        let currentReactionID = currentReaction?.id
        guard currentReactionID != desiredReactionID else { return }
        guard let toggledReactionID = desiredReactionID ?? currentReactionID, !toggledReactionID.isEmpty else {
            return
        }

        if currentReactionID != nil, currentReaction?.canUndo == false {
            modalRouter.presentNotice(message: "当前表情回应已超过可撤销时间，暂时不能修改。")
            return
        }

        Task { @MainActor in
            do {
                try await transitionReaction(
                    from: currentReactionID,
                    to: desiredReactionID,
                    toggledReactionId: toggledReactionID,
                    postId: postId
                )
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    private func transitionReaction(
        from currentReactionID: String?,
        to desiredReactionID: String?,
        toggledReactionId: String,
        postId: UInt64
    ) async throws {
        switch (currentReactionID, desiredReactionID) {
        case (nil, "heart"):
            try await topicDetailStore.setPostLiked(topicId: topic.id, postId: postId, liked: true)
        case ("heart", nil):
            try await topicDetailStore.setPostLiked(topicId: topic.id, postId: postId, liked: false)
        default:
            try await topicDetailStore.togglePostReaction(
                topicId: topic.id,
                postId: postId,
                reactionId: toggledReactionId
            )
        }
    }

    private func confirmDelete(_ post: TopicPostState) {
        modalRouter.presentDeleteConfirmation(postNumber: post.postNumber) { [weak self] in
            self?.deletePost(
                FirePostManagementContext(postID: post.id, postNumber: post.postNumber)
            )
        }
    }

    private func deletePost(_ context: FirePostManagementContext) {
        Task { @MainActor in
            do {
                try await topicDetailStore.deletePost(
                    topicID: topic.id,
                    postID: context.postID
                )
                modalRouter.presentNotice(message: "已删除 #\(context.postNumber)。")
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    private func recoverPost(_ post: TopicPostState) {
        let context = FirePostManagementContext(postID: post.id, postNumber: post.postNumber)
        Task { @MainActor in
            do {
                try await topicDetailStore.recoverPost(
                    topicID: topic.id,
                    postID: context.postID
                )
                modalRouter.presentNotice(message: "已恢复 #\(context.postNumber)。")
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    private func presentTopicBookmarkEditor() {
        modalRouter.presentBookmarkEditor(
            context: topicBookmarkContext,
            recoveryOriginURL: topicCloudflareRecoveryURL,
            onReload: { [weak self] in
                await self?.loadTopicDetail(force: true)
            }
        )
    }

    private func presentPostBookmarkEditor(_ post: TopicPostState) {
        modalRouter.presentBookmarkEditor(
            context: postBookmarkContext(for: post),
            recoveryOriginURL: topicCloudflareRecoveryURL,
            onReload: { [weak self] in
                await self?.loadTopicDetail(force: true)
            }
        )
    }

    private func presentPostEditor(_ post: TopicPostState) {
        modalRouter.presentPostEditor(
            topicID: topic.id,
            context: FirePostEditorContext(postID: post.id, postNumber: post.postNumber),
            onSaved: { [weak self] in
                await self?.loadTopicDetail(force: true)
            }
        )
    }

    private func presentTopicEditor() {
        modalRouter.presentTopicEditor(
            topicID: topic.id,
            initialTitle: detail?.title ?? topic.title,
            initialCategoryID: detail?.categoryId ?? topic.categoryId,
            initialTags: detail?.tags.map(\.name) ?? row.tagNames,
            onSaved: { [weak self] in
                await self?.loadTopicDetail(force: true)
            }
        )
    }

    private func presentFlagSheet(_ post: TopicPostState) {
        modalRouter.presentFlagSheet(
            topicID: topic.id,
            context: FirePostManagementContext(
                postID: post.id,
                postNumber: post.postNumber,
                username: post.username
            ),
            onSubmitted: { [weak self] message in
                self?.modalRouter.presentNotice(message: message)
            }
        )
    }

    private func updateTopicNotificationLevel(_ option: FireTopicNotificationLevelOption) {
        Task { @MainActor in
            do {
                try await viewModel.setTopicNotificationLevel(
                    topicID: topic.id,
                    notificationLevel: option.rawValue,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
                await loadTopicDetail(force: true)
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    private func toggleTopicVote() async {
        guard let detail else { return }
        do {
            _ = try await viewModel.voteTopic(
                topicID: topic.id,
                voted: !detail.userVoted,
                recoveryOriginURL: topicCloudflareRecoveryURL
            )
        } catch {
            modalRouter.presentNotice(message: error.localizedDescription)
        }
    }

    private func presentTopicVoters() async {
        do {
            let voters = try await viewModel.fetchTopicVoters(topicID: topic.id)
            modalRouter.presentTopicVoters(voters, isLoading: false)
        } catch {
            modalRouter.presentNotice(message: error.localizedDescription)
        }
    }

    private func submitPollVote(
        for post: TopicPostState,
        poll: PollState,
        options: [String]
    ) {
        Task { @MainActor in
            do {
                _ = try await viewModel.votePoll(
                    topicID: topic.id,
                    postID: post.id,
                    pollName: poll.name,
                    options: options,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    private func removePollVote(for post: TopicPostState, poll: PollState) {
        Task { @MainActor in
            do {
                _ = try await viewModel.unvotePoll(
                    topicID: topic.id,
                    postID: post.id,
                    pollName: poll.name,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }
}
