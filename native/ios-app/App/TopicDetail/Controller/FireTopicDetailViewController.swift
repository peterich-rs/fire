import Combine
import UIKit

@MainActor
final class FireTopicDetailViewController: UIViewController, UIGestureRecognizerDelegate {
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
    private lazy var pageBackEdgePanGestureRecognizer: UIScreenEdgePanGestureRecognizer = {
        let gesture = UIScreenEdgePanGestureRecognizer(
            target: self,
            action: #selector(handlePageBackEdgePan(_:))
        )
        gesture.edges = .left
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

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
        postReplyContextError: { [weak self] postID in
            self?.topicDetailStore.postReplyContextError(for: postID)
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
        onOpenProfile: { [weak self] username in
            self?.modalRouter.presentProfile(username: username)
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
    private var snapshotBuildTask: Task<Void, Never>?
    private var snapshotBuildGeneration: UInt64 = 0
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
        snapshotBuildTask?.cancel()
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
        view.addGestureRecognizer(pageBackEdgePanGestureRecognizer)
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
        pageBackEdgePanGestureRecognizer.isEnabled = canNavigateBackFromTopicDetail
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
        feedController.onScrollInteractionChanged = { [weak self] isActive in
            guard let self else { return }
            self.topicDetailStore.setTopicDetailScrollInteractionActive(
                isActive,
                topicId: self.row.topic.id
            )
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
                self?.buildAndApplyChromeState()
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
        snapshotBuildTask?.cancel()
        snapshotBuildTask = nil
        cancellables.removeAll()
        topicDetailStore.setTopicDetailScrollInteractionActive(
            false,
            topicId: row.topic.id,
            drainDeferredRefresh: false
        )

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

    private var needsPresentedRootEdgeDismissGesture: Bool {
        (navigationController?.viewControllers.count ?? 0) <= 1
            && (navigationController?.presentingViewController != nil || presentingViewController != nil)
    }

    private var canNavigateBackFromTopicDetail: Bool {
        if let navigationController {
            return navigationController.viewControllers.count > 1
                || navigationController.presentingViewController != nil
        }
        return presentingViewController != nil
    }

    @objc private func handlePageBackEdgePan(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
        guard gestureRecognizer.state == .ended,
              canNavigateBackFromTopicDetail,
              navigationController?.transitionCoordinator == nil else {
            return
        }
        let translation = gestureRecognizer.translation(in: view)
        let velocity = gestureRecognizer.velocity(in: view)
        let horizontalDistance = max(translation.x, 0)
        let horizontalVelocity = max(velocity.x, 0)
        guard horizontalDistance > 72 || horizontalVelocity > 420,
              max(abs(translation.x), abs(velocity.x)) > max(abs(translation.y), abs(velocity.y)) else {
            return
        }
        navigateBackFromTopicDetail()
    }

    private func navigateBackFromTopicDetail() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else if let navigationController {
            navigationController.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pageBackEdgePanGestureRecognizer,
              let panGesture = gestureRecognizer as? UIScreenEdgePanGestureRecognizer else {
            return true
        }
        guard canNavigateBackFromTopicDetail,
              navigationController?.transitionCoordinator == nil else {
            return false
        }
        let velocity = panGesture.velocity(in: view)
        return velocity.x >= 0 && abs(velocity.x) >= abs(velocity.y)
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

        topicDetailStore.$topicChromeRevisions
            .map { revisions in revisions[topicId] ?? 0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.buildAndApplyChromeState()
            }
            .store(in: &cancellables)

        topicDetailStore.$topicSidecarRevisions
            .map { revisions in revisions[topicId] ?? 0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.buildAndApplySnapshot()
            }
            .store(in: &cancellables)

        topicDetailStore.$topicInteractionRevisions
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

    private func buildCurrentRouteState(topicId: UInt64) -> FireTopicDetailRouteState {
        let detail = topicDetailStore.topicDetail(for: topicId)
        return FireTopicDetailRouteState(
            currentUsername: viewModel.session.bootstrap.currentUsername,
            baseURLString: baseURLString,
            canWriteInteractions: canWriteInteractions,
            row: row,
            displayedCategory: viewModel.categoryPresentation(for: detail?.categoryId ?? row.topic.categoryId)
        )
    }

    private func buildCurrentFeedState(topicId: UInt64) -> FireTopicDetailFeedState {
        let store = topicDetailStore
        return FireTopicDetailFeedState(
            detail: store.topicDetail(for: topicId),
            renderState: store.topicRenderState(for: topicId),
            postLookup: store.topicPostLookup(for: topicId),
            isLoadingTopic: store.isLoadingTopic(topicId: topicId),
            isLoadingMoreTopicPosts: store.isLoadingMoreTopicPosts(topicId: topicId),
            loadMoreTopicPostsError: store.loadMoreTopicPostsError(topicId: topicId),
            hasMoreTopicPosts: store.hasMoreTopicPosts(topicId: topicId),
            detailError: store.errorMessage(for: topicId),
            detailNotice: store.detailNotice(topicId: topicId),
            topicCollectionRevision: store.topicCollectionRevision(topicId: topicId),
            pendingScrollTarget: store.pendingScrollTarget(topicId: topicId)
        )
    }

    private func buildCurrentChromeState(topicId: UInt64) -> FireTopicDetailChromeState {
        FireTopicDetailChromeState(
            detail: topicDetailStore.topicDetail(for: topicId),
            row: row,
            baseURLString: baseURLString,
            canWriteInteractions: canWriteInteractions
        )
    }

    private func buildCurrentComposerState(topicId: UInt64) -> FireTopicDetailComposerState {
        FireTopicDetailComposerState(
            typingUsers: topicDetailStore.topicPresenceUsers(for: topicId),
            composerContext: composerContext,
            replyDraft: replyDraft,
            quickReplyError: quickReplyError,
            isSubmittingReply: topicDetailStore.isSubmittingReply(topicId: topicId),
            minimumReplyLength: minimumReplyLength,
            canWriteInteractions: canWriteInteractions
        )
    }

    private func buildCurrentSidecarState(topicId: UInt64) -> FireTopicDetailSidecarState {
        FireTopicDetailSidecarState(
            topicAiSummary: topicDetailStore.topicAiSummary(for: topicId),
            isLoadingTopicAiSummary: topicDetailStore.isLoadingTopicAiSummary(topicId: topicId),
            topicAiSummaryError: topicDetailStore.topicAiSummaryError(for: topicId)
        )
    }

    private func buildCurrentInteractionState() -> FireTopicDetailInteractionState {
        FireTopicDetailInteractionState(
            mutatingPostIDs: topicDetailStore.mutatingPostIDs,
            loadingPostReplyContextIDs: topicDetailStore.loadingPostReplyContextIDs,
            postReplyContextErrorsByPostID: topicDetailStore.postReplyContextErrorsByPostID,
            expandedPostTextIDs: expandedPostTextIDs,
            expandedReplyRootPostIDs: expandedReplyRootPostIDs
        )
    }

    private func buildCurrentPageState() -> FireTopicDetailPageState {
        let topicId = row.topic.id
        return FireTopicDetailPageState(
            feed: buildCurrentFeedState(topicId: topicId),
            chrome: buildCurrentChromeState(topicId: topicId),
            composer: buildCurrentComposerState(topicId: topicId),
            sidecar: buildCurrentSidecarState(topicId: topicId),
            interaction: buildCurrentInteractionState(),
            route: buildCurrentRouteState(topicId: topicId)
        )
    }

    private func buildRuntimeConfiguration(from state: FireTopicDetailPageState) -> FireTopicDetailRuntimeConfiguration {
        FireTopicDetailRuntimeConfiguration(
            viewModel: viewModel,
            displayedCategory: state.route.displayedCategory,
            currentUsername: state.route.currentUsername,
            row: state.route.row,
            baseURLString: state.route.baseURLString,
            detail: state.feed.detail,
            renderState: state.feed.renderState,
            pendingScrollTarget: state.feed.pendingScrollTarget,
            detailError: state.feed.detailError,
            detailNotice: state.feed.detailNotice,
            hasMoreTopicPosts: state.feed.hasMoreTopicPosts,
            isLoadingTopic: state.feed.isLoadingTopic,
            isLoadingMoreTopicPosts: state.feed.isLoadingMoreTopicPosts,
            loadMoreTopicPostsError: state.feed.loadMoreTopicPostsError,
            topicAiSummary: state.sidecar.topicAiSummary,
            isLoadingTopicAiSummary: state.sidecar.isLoadingTopicAiSummary,
            topicAiSummaryError: state.sidecar.topicAiSummaryError,
            topicCollectionRevision: state.feed.topicCollectionRevision,
            canWriteInteractions: state.route.canWriteInteractions,
            postLookup: state.feed.postLookup,
            interactionState: state.interaction,
            snapshotInvalidationToken: AnyHashable(FireTopicDetailFeedInvalidationToken(
                topicID: state.topic.id,
                topicCollectionRevision: state.feed.topicCollectionRevision,
                pendingScrollTarget: state.feed.pendingScrollTarget,
                detailError: state.feed.detailError ?? "",
                detailNotice: state.feed.detailNotice,
                hasDetail: state.feed.detail != nil,
                isLoadingTopic: state.feed.isLoadingTopic,
                isLoadingMoreTopicPosts: state.feed.isLoadingMoreTopicPosts,
                loadMoreTopicPostsError: state.feed.loadMoreTopicPostsError ?? "",
                hasMoreTopicPosts: state.feed.hasMoreTopicPosts,
                canWriteInteractions: state.route.canWriteInteractions,
                currentUsername: state.route.currentUsername ?? "",
                baseURLString: state.route.baseURLString,
                expandedReplyRootPostIDs: state.interaction.expandedReplyRootPostIDs
            )),
            interactions: runtimeInteractions
        )
    }

    private func buildAndApplySnapshot() {
        snapshotBuildGeneration &+= 1
        let generation = snapshotBuildGeneration
        let pageState = buildCurrentPageState()
        let configuration = buildRuntimeConfiguration(from: pageState)
        let input = FireTopicDetailSnapshotInput(
            configuration: configuration,
            toolbarState: snapshotAssembler.makeToolbarState(from: pageState.chrome),
            quickReplyState: snapshotAssembler.makeQuickReplyState(from: pageState.composer),
            pendingScrollTarget: pageState.feed.pendingScrollTarget,
            invalidationToken: configuration.snapshotInvalidationToken
        )

        applyChromeState(chrome: pageState.chrome, composer: pageState.composer)

        snapshotBuildTask?.cancel()
        snapshotBuildTask = Task.detached(priority: .userInitiated) { [weak self, snapshotAssembler, input, configuration, generation] in
            let buildStartedAt = Date()
            let snapshot = snapshotAssembler.buildSnapshot(from: input)
            let buildDurationMs = Self.elapsedMilliseconds(since: buildStartedAt)

            await MainActor.run { [weak self] in
                guard let self,
                      self.snapshotBuildGeneration == generation,
                      !Task.isCancelled else {
                    return
                }
                self.applyBuiltSnapshot(
                    snapshot,
                    configuration: configuration,
                    buildDurationMs: buildDurationMs
                )
            }
        }
    }

    private func buildAndApplyChromeState() {
        let topicId = row.topic.id
        applyChromeState(
            chrome: buildCurrentChromeState(topicId: topicId),
            composer: buildCurrentComposerState(topicId: topicId)
        )
    }

    private func applyChromeState(
        chrome: FireTopicDetailChromeState,
        composer: FireTopicDetailComposerState
    ) {
        toolbarCoordinator.apply(state: snapshotAssembler.makeToolbarState(from: chrome))
        quickReplyBarNode.apply(state: snapshotAssembler.makeQuickReplyState(from: composer))
    }

    private func applyBuiltSnapshot(
        _ snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration,
        buildDurationMs: Int64
    ) {
        let applyStartedAt = Date()
        feedUpdatePipeline.apply(snapshot: snapshot, configuration: configuration)
        let applyDurationMs = Self.elapsedMilliseconds(since: applyStartedAt)
        logSnapshotApply(
            snapshot: snapshot,
            configuration: configuration,
            buildDurationMs: buildDurationMs,
            applyDurationMs: applyDurationMs
        )
    }

    private func logSnapshotApply(
        snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration,
        buildDurationMs: Int64,
        applyDurationMs: Int64
    ) {
        viewModel.topicDetailLogger()?.debug(
            "topic detail snapshot apply topic_id=\(topic.id) snapshot_build_ms=\(buildDurationMs) feed_apply_ms=\(applyDurationMs) snapshot_item_count=\(snapshot.items.count) topic_collection_revision=\(configuration.topicCollectionRevision) has_detail=\(configuration.detail != nil)"
        )
    }

    nonisolated private static func elapsedMilliseconds(since startedAt: Date) -> Int64 {
        Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
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
            modalRouter.presentWebLink(url)
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
        buildAndApplyChromeState()
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
        guard shouldLoadReplyContext(for: post) else {
            return
        }
        Task {
            await topicDetailStore.loadPostReplyContextIfNeeded(
                topicID: topic.id,
                post: post
            )
        }
    }

    private func shouldLoadReplyContext(for post: TopicPostState) -> Bool {
        let declaredReplyCount = Int(post.replyCount)
        guard declaredReplyCount > 0 else {
            return false
        }
        guard let renderState = topicDetailStore.topicRenderState(for: topic.id) else {
            return true
        }
        return FireTopicDetailReplyContextLoadPolicy.shouldLoadReplyContext(
            for: post,
            replyRows: renderState.replyRows,
            postLookup: topicDetailStore.topicPostLookup(for: topic.id)
        )
    }

    private func clearComposerTarget() {
        let shouldKeepFocus = quickReplyBarNode.isInputFocused
        composerContext = nil
        buildAndApplyChromeState()
        if shouldKeepFocus {
            quickReplyBarNode.focusInput()
            DispatchQueue.main.async { [weak self] in
                self?.quickReplyBarNode.focusInput()
            }
        }
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
                self.buildAndApplyChromeState()
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
            buildAndApplyChromeState()
            return
        }
        guard trimmed.count >= minimumReplyLength else {
            quickReplyError = "回复至少需要 \(minimumReplyLength) 个字。"
            buildAndApplyChromeState()
            return
        }

        let topicId = composerContext?.topicId ?? topic.id
        let replyToPostNumber = composerContext?.replyToPostNumber
        quickReplyError = nil
        buildAndApplyChromeState()

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
                buildAndApplyChromeState()
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("pending review") {
                    replyDraft = ""
                    composerContext = nil
                    quickReplyBarNode.resignInputFocus()
                    buildAndApplyChromeState()
                    modalRouter.presentNotice(message: "回复已提交，等待审核。")
                    return
                }
                quickReplyError = message
                buildAndApplyChromeState()
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
