import Combine
import PhotosUI
import UIKit
import UniformTypeIdentifiers

private let fireTopicDetailSnapshotBuildDiagnosticThresholdMs: Int64 = 50
private let fireTopicDetailSnapshotApplyDiagnosticThresholdMs: Int64 = 16

@MainActor
final class FireTopicDetailViewController: UIViewController, UIGestureRecognizerDelegate {
    let viewModel: FireAppViewModel
    let topicDetailStore: FireTopicDetailStore
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    let feedController: FireTopicDetailFeedController
    let paginationCoordinator: FireTopicDetailPaginationCoordinator
    let visibilityCoordinator: FireTopicDetailVisibilityCoordinator
    let layoutManager = FirePostLayoutManager()
    /// Pure UIKit bottom chrome layered above Texture feed (WeChat-style).
    let quickReplyBar = FireTopicQuickReplyBarView()
    var quickReplyBottomConstraint: NSLayoutConstraint?
    var quickReplyHeightConstraint: NSLayoutConstraint?
    let rootNode: FireTopicDetailRootNode
    lazy var pageBackEdgePanGestureRecognizer: UIScreenEdgePanGestureRecognizer = {
        let gesture = UIScreenEdgePanGestureRecognizer(
            target: self,
            action: #selector(handlePageBackEdgePan(_:))
        )
        gesture.edges = .left
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    lazy var feedUpdatePipeline = FireTopicDetailFeedUpdatePipeline(
        feedController: feedController,
        paginationCoordinator: paginationCoordinator,
        visibilityCoordinator: visibilityCoordinator,
        logger: viewModel.topicDetailLogger()
    )

    lazy var modalRouter = FireTopicDetailModalRouter(
        viewController: self,
        viewModel: viewModel,
        topicDetailStore: topicDetailStore
    )

    lazy var toolbarCoordinator = FireTopicDetailToolbarCoordinator(
        viewController: self,
        actions: .init(
            onToggleSearch: { [weak self] in
                self?.toggleTopicSearch()
            },
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

    lazy var runtimeInteractions = FireTopicDetailRuntimeInteractions(
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
        onToggleTopicAiSummaryExpanded: { [weak self] in
            guard let self else { return }
            self.isTopicAiSummaryExpanded.toggle()
            self.buildAndApplySnapshot()
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
            self?.collapseReactionPicker(animatedSnapshot: true)
        },
        onToggleReactionPicker: { [weak self] post in
            self?.toggleReactionPicker(for: post)
        },
        onBoostPost: { [weak self] post in
            self?.openBoostComposer(for: post)
        },
        quickReactionOptionsProvider: { [weak self] in
            FireTopicPresentation.quickReactionOptions(
                from: self?.viewModel.session.bootstrap.enabledReactionIds ?? []
            )
        },
        isReactionPickerExpanded: { [weak self] postID in
            self?.expandedReactionPickerPostIDs.contains(postID) ?? false
        },
        onQuotePost: { [weak self] post in
            self?.openQuoteComposer(for: post)
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
            self?.togglePostTextExpansion(for: post)
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

    let snapshotAssembler = FireTopicDetailSnapshotAssembler()
    let detailOwnerToken: String
    let timingTracker: FireTopicTimingTracker

    var initialLoadTask: Task<Void, Never>?
    var subscriptionTask: Task<Void, Never>?
    var snapshotBuildTask: Task<Void, Never>?
    var snapshotBuildGeneration: UInt64 = 0
    var cancellables = Set<AnyCancellable>()

    var expandedPostTextIDs: Set<UInt64> = []
    var expandedReplyRootPostIDs: Set<UInt64> = []
    var expandedReactionPickerPostIDs: Set<UInt64> = []
    var reactionPickerCollapseWorkItem: DispatchWorkItem?
    var didAttemptReactionPickerCoachmark = false
    var isTopicAiSummaryExpanded = false
    var composerContext: FireReplyComposerContext?
    var replyDraft = ""
    var quickReplyError: String?
    var keyboardFrameInScreen: CGRect = .null
    let topicSearchBar = FireTopicSearchBar()
    var topicSearchQuery = ""
    var topicSearchMatches: [FireTopicSearchMatch] = []
    var topicSearchIndex = -1
    var lastLayoutDiagnosticsSignature: String?
    var repeatedLayoutDiagnosticsCount = 0
    var appearanceCancellables = Set<AnyCancellable>()
    var lastColorAppearanceStyle: UIUserInterfaceStyle = .unspecified
    var activeTopicSearchMatch: FireTopicSearchMatch? {
        guard topicSearchIndex >= 0,
              topicSearchIndex < topicSearchMatches.count else {
            return nil
        }
        return topicSearchMatches[topicSearchIndex]
    }

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
        self.rootNode = FireTopicDetailRootNode(
            feedNode: feedController.collectionNode
        )
        self.detailOwnerToken = "ios.topic-detail.\(row.topic.id).\(UUID().uuidString.lowercased())"
        self.timingTracker = FireTopicTimingTracker(topicId: row.topic.id)
        super.init(nibName: nil, bundle: nil)
        viewModel.topicDetailLogger()?.info(
            "topic detail controller init topic_id=\(row.topic.id) post_number=\(scrollToPostNumber.map(String.init) ?? "nil") owner_token=\(detailOwnerToken) row_title_length=\(row.topic.title.count)"
        )
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
        viewModel.topicDetailLogger()?.debug("topic detail loadView start topic_id=\(row.topic.id)")
        view = rootNode.view
        viewModel.topicDetailLogger()?.debug("topic detail loadView complete topic_id=\(row.topic.id)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let startedAt = Date()
        viewModel.topicDetailLogger()?.info(
            "topic detail viewDidLoad start topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
        view.backgroundColor = FireTheme.uiCanvas
        view.tintColor = FireTheme.uiAccent
        configureRuntime()
        configureQuickReplyBar()
        configureTopicSearchBar()
        configureNavigationAppearance()
        bindColorAppearanceObservers()
        lastColorAppearanceStyle = traitCollection.userInterfaceStyle
        toolbarCoordinator.configureNavigationItem(navigationItem)
        updateDismissButtonIfNeeded()
        view.addGestureRecognizer(pageBackEdgePanGestureRecognizer)
        beginPageLifecycle()
        buildAndApplySnapshot()
        viewModel.topicDetailLogger()?.info(
            "topic detail viewDidLoad complete topic_id=\(row.topic.id) elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt))"
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        handleColorAppearanceChange(reason: "traitCollection")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let startedAt = Date()
        let diagnosticsSignature = layoutDiagnosticsSignature()
        let shouldLogLayout = shouldLogLayoutDiagnostics(signature: diagnosticsSignature)
        if shouldLogLayout {
            viewModel.topicDetailLogger()?.debug(
                "topic detail viewDidLayoutSubviews start topic_id=\(row.topic.id) signature=\(diagnosticsSignature) repeated_count=\(repeatedLayoutDiagnosticsCount)"
            )
        }
        layoutTopicSearchBar()
        updateBottomChromeInset()
        feedController.invalidateLayoutIfWidthChanged()
        if shouldLogLayout {
            viewModel.topicDetailLogger()?.debug(
                "topic detail viewDidLayoutSubviews complete topic_id=\(row.topic.id) elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt)) signature=\(diagnosticsSignature)"
            )
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomChromeInset()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let startedAt = Date()
        viewModel.topicDetailLogger()?.info(
            "topic detail viewWillAppear topic_id=\(row.topic.id) animated=\(animated) navigation_stack_count=\(navigationController?.viewControllers.count ?? 0)"
        )
        viewModel.topicDetailLogger()?.debug("topic detail viewWillAppear configure navigation start topic_id=\(row.topic.id)")
        configureNavigationAppearance()
        updateDismissButtonIfNeeded()
        updateBackGestureAvailability()
        viewModel.topicDetailLogger()?.debug("topic detail viewWillAppear configure navigation complete topic_id=\(row.topic.id)")
        viewModel.setAPMRoute("topic.detail.\(row.topic.id)")
        viewModel.topicDetailLogger()?.info(
            "topic detail viewWillAppear complete topic_id=\(row.topic.id) elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt))"
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.topicDetailLogger()?.info(
            "topic detail viewDidAppear topic_id=\(row.topic.id) animated=\(animated) view_attached=\(feedController.isViewAttached)"
        )
        updateBackGestureAvailability()
        Task {
            await timingTracker.setSceneActive(true)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.topicDetailLogger()?.info(
            "topic detail viewDidDisappear topic_id=\(row.topic.id) animated=\(animated) moving_from_parent=\(isMovingFromParent) being_dismissed=\(isBeingDismissed)"
        )
        if isMovingFromParent || isBeingDismissed {
            endPageLifecycle()
        }
        viewModel.restoreTopLevelAPMRoute()
        Task {
            await timingTracker.stop()
            await topicDetailStore.endTopicReplyPresence(topicId: row.topic.id)
        }
    }

    var topic: TopicSummaryState {
        row.topic
    }

    var detail: TopicDetailState? {
        topicDetailStore.topicDetail(for: topic.id)
    }

    var displayedTopicTitle: String {
        let trimmedDetailTitle = detail?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailTitle.isEmpty {
            return trimmedDetailTitle
        }
        let trimmedRowTitle = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRowTitle.isEmpty ? "话题 \(topic.id)" : trimmedRowTitle
    }

    var displayedTopicSlug: String {
        let trimmedDetailSlug = detail?.slug.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailSlug.isEmpty {
            return trimmedDetailSlug
        }
        return topic.slug.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayedCategoryId: UInt64? {
        detail?.categoryId ?? topic.categoryId
    }

    var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var canWriteInteractions: Bool {
        viewModel.canStartAuthenticatedMutation
    }

    var minimumReplyLength: Int {
        let minLength = isPrivateMessageThread
            ? viewModel.session.bootstrap.minPersonalMessagePostLength
            : viewModel.session.bootstrap.minPostLength
        return FireTopicPresentation.minimumReplyLength(from: minLength)
    }

    var isPrivateMessageThread: Bool {
        FireTopicPresentation.isPrivateMessageArchetype(detail?.archetype)
    }

    var topicCloudflareRecoveryURL: URL {
        viewModel.cloudflareRecoveryTopicURL(
            topicId: topic.id,
            topicSlug: displayedTopicSlug
        )
    }

    var topicBookmarkContext: FireBookmarkEditorContext {
        FireBookmarkEditorContext(
            bookmarkID: detail?.bookmarkId,
            bookmarkableID: topic.id,
            bookmarkableType: "Topic",
            topicID: topic.id,
            postNumber: nil,
            title: displayedTopicTitle,
            initialName: detail?.bookmarkName,
            initialReminderAt: detail?.bookmarkReminderAt,
            allowsDelete: detail?.bookmarkId != nil
        )
    }

    func postBookmarkContext(for post: TopicPostState) -> FireBookmarkEditorContext {
        let username = post.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return FireBookmarkEditorContext(
            bookmarkID: post.bookmarkId,
            bookmarkableID: post.id,
            bookmarkableType: "Post",
            topicID: topic.id,
            postNumber: post.postNumber,
            title: username.isEmpty ? "#\(post.postNumber)" : "#\(post.postNumber) · \(username)",
            initialName: post.bookmarkName,
            initialReminderAt: post.bookmarkReminderAt,
            allowsDelete: post.bookmarkId != nil
        )
    }

    func configureRuntime() {
        let startedAt = Date()
        viewModel.topicDetailLogger()?.debug("topic detail configure runtime start topic_id=\(row.topic.id)")
        feedController.paginationCoordinator = paginationCoordinator
        feedController.visibilityCoordinator = visibilityCoordinator
        feedController.layoutManager = layoutManager
        feedController.diagnosticsLogger = viewModel.topicDetailLogger()
        feedController.onRefresh = { [weak self] in
            await self?.performRefresh()
        }
        feedController.onBackgroundTap = { [weak self] in
            self?.quickReplyBar.resignInputFocus()
        }
        feedController.onScrollInteractionChanged = { [weak self] isActive in
            guard let self else { return }
            self.topicDetailStore.setTopicDetailScrollInteractionActive(
                isActive,
                topicId: self.row.topic.id
            )
            self.toolbarCoordinator.updateScrollChrome(
                isTitlePinned: self.feedController.isTitleCurrentlyPinned,
                isScrolling: isActive
            )
        }
        feedController.onTitlePinStateChanged = { [weak self] isPinned in
            guard let self else { return }
            self.toolbarCoordinator.updateScrollChrome(
                isTitlePinned: isPinned,
                isScrolling: self.feedController.isScrollInteractionActive
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

        quickReplyBar.callbacks = .init(
            onDraftChanged: { [weak self] draft in
                self?.replyDraft = draft
                self?.quickReplyError = nil
                self?.buildAndApplyChromeState()
            },
            onSubmit: { [weak self] payload in
                self?.submitQuickReply(payload)
            },
            onOpenAdvancedComposer: { [weak self] in
                guard let self else { return }
                // Boost stays in the bottom bar; advanced composer is reply-only.
                if self.composerContext?.isBoost == true {
                    self.composerContext = FireReplyComposerContext(
                        topicId: self.topic.id,
                        postId: self.composerContext?.postId,
                        replyToPostNumber: self.composerContext?.replyToPostNumber,
                        replyToUsername: self.composerContext?.replyToUsername,
                        kind: .reply
                    )
                    self.buildAndApplyChromeState()
                }
                self.openAdvancedComposer()
            },
            onClearTarget: { [weak self] in
                self?.clearComposerTarget()
            },
            onFocusChanged: { [weak self] focused in
                self?.handleQuickReplyFocusChanged(focused)
            },
            onHeightChanged: { [weak self] in
                self?.updateBottomChromeInset()
            },
            onSearchMentions: { [weak self] term in
                await self?.searchQuickReplyMentions(term: term) ?? []
            },
            onPickImage: { [weak self] in
                self?.presentQuickReplyImagePicker()
            }
        )
        viewModel.topicDetailLogger()?.debug(
            "topic detail configure runtime complete topic_id=\(row.topic.id) elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt))"
        )
    }

    func configureQuickReplyBar() {
        // Layer above Texture feed so cells never show through the bar.
        quickReplyBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(quickReplyBar)

        let bottom = quickReplyBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let height = quickReplyBar.heightAnchor.constraint(equalToConstant: 0)
        quickReplyBottomConstraint = bottom
        quickReplyHeightConstraint = height

        NSLayoutConstraint.activate([
            quickReplyBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            quickReplyBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,
            height,
        ])
        view.bringSubviewToFront(quickReplyBar)
    }


    func beginPageLifecycle() {
        viewModel.topicDetailLogger()?.info(
            "topic detail lifecycle begin topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
        topicDetailStore.beginTopicDetailLifecycle(
            topicId: row.topic.id,
            ownerToken: detailOwnerToken
        )

        timingTracker.start { [weak viewModel] topicId, topicTimeMs, timings in
            guard let viewModel else { return false }
            return await viewModel.topicInteraction.reportTopicTimings(
                topicId: topicId,
                topicTimeMs: topicTimeMs,
                timings: timings
            )
        }

        subscribeToKeyboardNotifications()
        subscribeToStoreRevisions()
        kickOffInitialLoad()
        kickOffMessageBusSubscription()
        viewModel.topicDetailLogger()?.debug(
            "topic detail lifecycle begin scheduled tasks topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
    }

    func endPageLifecycle() {
        viewModel.topicDetailLogger()?.info(
            "topic detail lifecycle end topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
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

    func kickOffInitialLoad() {
        initialLoadTask?.cancel()
        viewModel.topicDetailLogger()?.info(
            "topic detail initial load task scheduled topic_id=\(row.topic.id) target_post=\(scrollToPostNumber.map(String.init) ?? "nil")"
        )
        initialLoadTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            self.viewModel.topicDetailLogger()?.info(
                "topic detail initial load task start topic_id=\(self.row.topic.id) target_post=\(self.scrollToPostNumber.map(String.init) ?? "nil")"
            )
            await self.loadTopicDetail(targetPostNumber: self.scrollToPostNumber)
            self.viewModel.topicDetailLogger()?.info(
                "topic detail initial load task complete topic_id=\(self.row.topic.id) elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt)) cancelled=\(Task.isCancelled)"
            )
        }
    }

    func updateDismissButtonIfNeeded() {
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

    func dismissPresentedTopicDetail() {
        navigationController?.dismiss(animated: true)
    }

    var needsPresentedRootEdgeDismissGesture: Bool {
        (navigationController?.viewControllers.count ?? 0) <= 1
            && (navigationController?.presentingViewController != nil || presentingViewController != nil)
    }

    var canNavigateBackFromTopicDetail: Bool {
        if let navigationController {
            return navigationController.viewControllers.count > 1
                || navigationController.presentingViewController != nil
        }
        return presentingViewController != nil
    }

    func updateBackGestureAvailability() {
        let usesMainNavigationController = navigationController is FireMainNavigationController
        navigationController?.interactivePopGestureRecognizer?.isEnabled =
            !usesMainNavigationController && (navigationController?.viewControllers.count ?? 0) > 1
        pageBackEdgePanGestureRecognizer.isEnabled =
            !usesMainNavigationController && canNavigateBackFromTopicDetail
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

    func navigateBackFromTopicDetail() {
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

    func configureNavigationAppearance() {
        // Opaque chrome so dark images scrolling underneath cannot tint the bar black
        // in light mode (translucent material samples feed content).
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = FireTheme.uiCanvas
        appearance.shadowColor = FireTheme.uiDivider
        appearance.titleTextAttributes = [
            .foregroundColor: FireTheme.uiInk,
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: FireTheme.uiInk,
        ]

        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent
        navigationController?.navigationBar.barTintColor = FireTheme.uiCanvas
        view.backgroundColor = FireTheme.uiCanvas
        view.tintColor = FireTheme.uiAccent
    }

    func bindColorAppearanceObservers() {
        // Single bus from Environment (preference write / storage sync). Avoid also
        // listening to the NotificationCenter name here — same event would re-apply twice.
        FireAppearanceEnvironment.snapshotPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.applyAppearance(snapshot)
            }
            .store(in: &appearanceCancellables)
    }

    func handleColorAppearanceChange(reason: String) {
        let snapshot = FireAppearanceEnvironment.snapshot(for: view, window: view.window)
        applyAppearance(snapshot)
        viewModel.topicDetailLogger()?.debug(
            "topic detail appearance reason=\(reason) token=\(snapshot.token)"
        )
    }

    /// Shell layers that sit outside factory cell rebuilds (VC view + Texture root).
    func applyAppearanceShell(_ snapshot: FireAppearanceSnapshot? = nil) {
        let resolved = snapshot ?? FireAppearanceEnvironment.snapshot(for: view, window: view.window)
        FireAppearanceTexture.applySnapshot(resolved, to: view)
        rootNode.applyAppearance(resolved)
        feedController.assertFeedShellAppearance(resolved)
        configureNavigationAppearance()
    }

    func kickOffMessageBusSubscription() {
        subscriptionTask?.cancel()
        viewModel.topicDetailLogger()?.debug(
            "topic detail messagebus subscription task scheduled topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            self.viewModel.topicDetailLogger()?.debug(
                "topic detail messagebus subscription task start topic_id=\(self.row.topic.id) owner_token=\(self.detailOwnerToken)"
            )
            await self.topicDetailStore.maintainTopicDetailSubscription(
                topicId: self.row.topic.id,
                ownerToken: self.detailOwnerToken
            )
            self.viewModel.topicDetailLogger()?.debug(
                "topic detail messagebus subscription task complete topic_id=\(self.row.topic.id) cancelled=\(Task.isCancelled)"
            )
        }
    }

    func loadTopicDetail(
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        let topicSlug = displayedTopicSlug
        let startedAt = Date()
        viewModel.topicDetailLogger()?.info(
            "topic detail controller load request start topic_id=\(row.topic.id) force=\(force) target_post=\(targetPostNumber.map(String.init) ?? "nil") slug_present=\(!topicSlug.isEmpty)"
        )
        await topicDetailStore.loadTopicDetail(
            topicId: row.topic.id,
            topicSlug: topicSlug.isEmpty ? nil : topicSlug,
            targetPostNumber: targetPostNumber,
            force: force
        )
        viewModel.topicDetailLogger()?.info(
            "topic detail controller load request complete topic_id=\(row.topic.id) elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt)) has_detail=\(topicDetailStore.topicDetail(for: row.topic.id) != nil) is_loading=\(topicDetailStore.isLoadingTopic(topicId: row.topic.id)) error_present=\(topicDetailStore.errorMessage(for: row.topic.id) != nil)"
        )
    }

    func subscribeToStoreRevisions() {
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

    func subscribeToKeyboardNotifications() {
        // Deliver synchronously on the posting thread (main). Do not hop through
        // RunLoop.main / DispatchQueue.main — that defers handling by a turn and
        // makes the quick-reply bar lag behind the keyboard after swipe-to-reply.
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
            .sink { [weak self] notification in
                self?.handleKeyboardNotification(notification)
            }
            .store(in: &cancellables)
    }

    func buildCurrentRouteState(topicId: UInt64) -> FireTopicDetailRouteState {
        let detail = topicDetailStore.topicDetail(for: topicId)
        return FireTopicDetailRouteState(
            currentUsername: viewModel.session.bootstrap.currentUsername,
            baseURLString: baseURLString,
            canWriteInteractions: canWriteInteractions,
            row: row,
            displayedCategory: viewModel.categoryPresentation(for: detail?.categoryId ?? row.topic.categoryId)
        )
    }

    func buildCurrentFeedState(topicId: UInt64) -> FireTopicDetailFeedState {
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

    func buildCurrentChromeState(topicId: UInt64) -> FireTopicDetailChromeState {
        FireTopicDetailChromeState(
            detail: topicDetailStore.topicDetail(for: topicId),
            row: row,
            baseURLString: baseURLString,
            canWriteInteractions: canWriteInteractions
        )
    }

    func buildCurrentComposerState(topicId: UInt64) -> FireTopicDetailComposerState {
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

    func buildCurrentSidecarState(topicId: UInt64) -> FireTopicDetailSidecarState {
        FireTopicDetailSidecarState(
            topicAiSummary: topicDetailStore.topicAiSummary(for: topicId),
            isLoadingTopicAiSummary: topicDetailStore.isLoadingTopicAiSummary(topicId: topicId),
            topicAiSummaryError: topicDetailStore.topicAiSummaryError(for: topicId)
        )
    }

    func buildCurrentInteractionState() -> FireTopicDetailInteractionState {
        FireTopicDetailInteractionState(
            mutatingPostIDs: topicDetailStore.mutatingPostIDs,
            loadingPostReplyContextIDs: topicDetailStore.loadingPostReplyContextIDs,
            expandedPostTextIDs: expandedPostTextIDs,
            expandedReplyRootPostIDs: expandedReplyRootPostIDs,
            expandedReactionPickerPostIDs: expandedReactionPickerPostIDs
        )
    }

    func buildCurrentPageState() -> FireTopicDetailPageState {
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

    func buildRuntimeConfiguration(from state: FireTopicDetailPageState) -> FireTopicDetailRuntimeConfiguration {
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
            isTopicAiSummaryExpanded: isTopicAiSummaryExpanded,
            topicCollectionRevision: state.feed.topicCollectionRevision,
            canWriteInteractions: state.route.canWriteInteractions,
            postLookup: state.feed.postLookup,
            interactionState: state.interaction,
            activeSearchPostID: activeTopicSearchMatch?.postID,
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
                activeSearchPostID: activeTopicSearchMatch?.postID,
                expandedReplyRootPostIDs: state.interaction.expandedReplyRootPostIDs,
                expandedReactionPickerPostIDs: state.interaction.expandedReactionPickerPostIDs
            )),
            interactions: runtimeInteractions
        )
    }

    func buildAndApplySnapshot() {
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
        let logger = viewModel.topicDetailLogger()
        snapshotBuildTask = Task.detached(priority: .userInitiated) { [weak self, snapshotAssembler, input, configuration, generation, logger] in
            let buildStartedAt = Date()
            let snapshot = snapshotAssembler.buildSnapshot(from: input)
            let buildDurationMs = Self.elapsedMilliseconds(since: buildStartedAt)
            if buildDurationMs >= fireTopicDetailSnapshotBuildDiagnosticThresholdMs {
                logger?.debug(
                    "topic detail snapshot build slow topic_id=\(configuration.row.topic.id) generation=\(generation) build_ms=\(buildDurationMs) item_count=\(snapshot.items.count)"
                )
            }

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

    /// Local expand / picker / reply-tree toggles stay on the main thread so a
    /// single row can relayout without a detached full-page snapshot rebuild.
    func applyLocalInteractionSnapshot() {
        snapshotBuildGeneration &+= 1
        snapshotBuildTask?.cancel()
        snapshotBuildTask = nil
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
        let snapshot = snapshotAssembler.buildSnapshot(from: input)
        applyBuiltSnapshot(
            snapshot,
            configuration: configuration,
            buildDurationMs: 0
        )
    }

    func buildAndApplyChromeState() {
        let topicId = row.topic.id
        applyChromeState(
            chrome: buildCurrentChromeState(topicId: topicId),
            composer: buildCurrentComposerState(topicId: topicId)
        )
    }

    func applyChromeState(
        chrome: FireTopicDetailChromeState,
        composer: FireTopicDetailComposerState
    ) {
        toolbarCoordinator.apply(state: snapshotAssembler.makeToolbarState(from: chrome))
        quickReplyBar.apply(state: snapshotAssembler.makeQuickReplyState(from: composer))
        updateBottomChromeInset()
    }

    func applyBuiltSnapshot(
        _ snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration,
        buildDurationMs: Int64
    ) {
        let applyStartedAt = Date()
        feedUpdatePipeline.apply(snapshot: snapshot, configuration: configuration)
        // Collection updates can recreate Texture shells; keep canvas in sync with
        // the current appearance so dark→light survives data reload paths.
        applyAppearanceShell()
        let applyDurationMs = Self.elapsedMilliseconds(since: applyStartedAt)
        logSnapshotApply(
            snapshot: snapshot,
            configuration: configuration,
            buildDurationMs: buildDurationMs,
            applyDurationMs: applyDurationMs
        )
    }

    func logSnapshotApply(
        snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration,
        buildDurationMs: Int64,
        applyDurationMs: Int64
    ) {
        guard buildDurationMs >= fireTopicDetailSnapshotBuildDiagnosticThresholdMs
                || applyDurationMs >= fireTopicDetailSnapshotApplyDiagnosticThresholdMs
                || !feedController.isViewAttached else {
            return
        }
        viewModel.topicDetailLogger()?.debug(
            "topic detail snapshot apply diagnostic topic_id=\(topic.id) snapshot_build_ms=\(buildDurationMs) feed_apply_ms=\(applyDurationMs) snapshot_item_count=\(snapshot.items.count) topic_collection_revision=\(configuration.topicCollectionRevision) has_detail=\(configuration.detail != nil) feed_attached=\(feedController.isViewAttached)"
        )
    }

    nonisolated private static func elapsedMilliseconds(since startedAt: Date) -> Int64 {
        Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
    }

    nonisolated private static func formatSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    func layoutDiagnosticsSignature() -> String {
        "bounds=\(Self.formatSize(view.bounds.size)) safe_bottom=\(Int(view.safeAreaInsets.bottom.rounded())) feed_attached=\(feedController.isViewAttached)"
    }

    func shouldLogLayoutDiagnostics(signature: String) -> Bool {
        guard lastLayoutDiagnosticsSignature == signature else {
            lastLayoutDiagnosticsSignature = signature
            repeatedLayoutDiagnosticsCount = 0
            return true
        }
        repeatedLayoutDiagnosticsCount += 1
        return repeatedLayoutDiagnosticsCount.isMultiple(of: 500)
    }

    func handleLayoutRevisionChanged() {
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

    func performRefresh() async {
        timingTracker.recordInteraction()
        topicDetailStore.clearTopicDetailAnchor(topicId: topic.id)
        await loadTopicDetail(force: true)
        // Force-load rebuilds Texture nodes; re-assert shell so dark→light survives PTR.
        applyAppearanceShell()
    }

    func handleKeyboardNotification(_ notification: Notification) {
        if notification.name == UIResponder.keyboardWillHideNotification {
            keyboardFrameInScreen = .null
        } else {
            keyboardFrameInScreen =
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
        }
        updateBottomChromeInset(animatedWith: notification)
    }

    func updateBottomChromeInset(animatedWith notification: Notification? = nil) {
        // WeChat-style bottom input — pure UIKit, no Texture overlay:
        //
        // 1) Bar internal bottom padding
        //    - keyboard hidden → home-indicator safe area
        //    - keyboard up     → small pad (keyboard covers home indicator)
        // 2) Keyboard overlap → bar bottom constraint constant
        // 3) Feed contentInset.bottom = barHeight + keyboardOverlap
        let keyboardOverlap = keyboardOverlapHeight
        let keyboardVisible = keyboardOverlap > 0.5
        let homeIndicator = view.safeAreaInsets.bottom
        let barBottomPadding: CGFloat = keyboardVisible ? 8 : homeIndicator

        quickReplyBar.updateBottomInset(barBottomPadding)

        let previousBottom = quickReplyBottomConstraint?.constant ?? 0
        let previousHeight = quickReplyHeightConstraint?.constant ?? 0
        let measuredBarHeight = quickReplyBar.preferredHeight(forWidth: max(view.bounds.width, 1))
        quickReplyBottomConstraint?.constant = -keyboardOverlap
        quickReplyHeightConstraint?.constant = measuredBarHeight

        let barVisible = !quickReplyBar.isHidden
        let feedBottom = fireTopicDetailFeedBottomInset(
            quickReplyBarHeight: measuredBarHeight,
            safeAreaBottom: homeIndicator,
            keyboardOverlap: keyboardOverlap,
            isQuickReplyVisible: barVisible
        )
        rootNode.updateFeedBottomInset(feedBottom)
        updateFeedTopInset()
        view.bringSubviewToFront(quickReplyBar)

        let geometryChanged =
            abs(previousBottom + keyboardOverlap) > 0.5
            || abs(previousHeight - measuredBarHeight) > 0.5

        guard geometryChanged || notification != nil else { return }

        if let notification {
            let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
                .doubleValue ?? 0.25
            let curveRawValue = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?
                .uintValue ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
            // Keyboard uses a private curve (rawValue 7). Shift into
            // UIView.AnimationOptions so the bar tracks the system animation.
            let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [options, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.view.layoutIfNeeded()
            }
        }
        // Non-keyboard geometry commits on the next layout pass, or via an
        // explicit layoutIfNeeded() in presentQuickReplyInput() before focus.
    }

    var currentSearchBarHeight: CGFloat {
        topicSearchBar.isHidden ? 0 : topicSearchBar.bounds.height
    }

    var keyboardOverlapHeight: CGFloat {
        guard !keyboardFrameInScreen.isNull else {
            return 0
        }
        let frameInView = view.convert(keyboardFrameInScreen, from: nil)
        return max(view.bounds.intersection(frameInView).height, 0)
    }

    func handleVisiblePostNumbersChanged(_ visiblePostNumbers: Set<UInt32>) {
        if !visiblePostNumbers.isEmpty {
            timingTracker.recordInteraction()
        }
        timingTracker.updateVisiblePostNumbers(visiblePostNumbers)

        topicDetailStore.handleVisiblePostNumbersChanged(
            topicId: topic.id,
            visiblePostNumbers: visiblePostNumbers
        )
        maybePresentReactionPickerCoachmark(visiblePostNumbers: visiblePostNumbers)
    }

    func handleRichTextLink(_ url: URL) {
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
        case .notifications, .profileTab, .search:
            break
        }
    }

    func handleTopicLink(_ payload: FireTopicRoutePayload) {
        if payload.topicId == topic.id {
            guard let postNumber = payload.postNumber else { return }
            openPostNumber(postNumber)
            return
        }
        modalRouter.push(route: .topic(payload: payload))
    }

    func handleQuickReplyFocusChanged(_ focused: Bool) {
        if focused {
            topicDetailStore.beginTopicReplyPresence(topicId: topic.id)
        } else {
            Task {
                await topicDetailStore.endTopicReplyPresence(topicId: topic.id)
            }
        }
    }

    func openComposer(replyToPost: TopicPostState?) {
        composerContext = FireReplyComposerContext(
            topicId: topic.id,
            postId: replyToPost?.id,
            replyToPostNumber: replyToPost?.postNumber,
            replyToUsername: replyToPost?.username,
            kind: .reply
        )
        presentQuickReplyInput()
    }

    func openBoostComposer(for post: TopicPostState) {
        guard post.canBoost else {
            modalRouter.presentNotice(message: "当前帖子暂时不能 Boost。")
            return
        }
        guard canWriteInteractions else {
            modalRouter.presentNotice(message: "登录后才能 Boost。")
            return
        }
        // Share the bottom quick-reply chrome with comments instead of a separate sheet.
        composerContext = FireReplyComposerContext(
            topicId: topic.id,
            postId: post.id,
            replyToPostNumber: post.postNumber,
            replyToUsername: post.username,
            kind: .boost
        )
        if !replyDraft.isEmpty, composerContext?.isBoost == true {
            // Keep draft if user was already drafting a boost; otherwise clear reply draft noise.
        }
        presentQuickReplyInput()
    }

    /// Apply chrome first, commit bar geometry, then focus so the keyboard and
    /// input strip rise together (especially for swipe-to-reply).
    func presentQuickReplyInput() {
        buildAndApplyChromeState()
        // Target row / height must be in the hierarchy before first-responder
        // kicks off the keyboard animation; otherwise the bar catches up late.
        view.layoutIfNeeded()
        quickReplyBar.focusInput()
    }






    static let reactionPickerAutoCollapseSeconds: TimeInterval = 3.5

    func openPostNumber(_ postNumber: UInt32) {
        guard postNumber > 0 else { return }
        Task {
            await loadTopicDetail(targetPostNumber: postNumber)
        }
    }










    func clearComposerTarget() {
        // Cancel target is a full dismiss of the current compose session: drop the
        // reply/Boost target, wipe draft text, and leave the keyboard down.
        composerContext = nil
        replyDraft = ""
        quickReplyError = nil
        buildAndApplyChromeState()
        view.layoutIfNeeded()
        quickReplyBar.resignInputFocus()
    }

    func openAdvancedComposer() {
        let context = composerContext
            ?? FireReplyComposerContext(
                topicId: topic.id,
                postId: nil,
                replyToPostNumber: nil,
                replyToUsername: nil
            )
        quickReplyBar.resignInputFocus()
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

    func openQuoteComposer(for post: TopicPostState) {
        guard let quote = FireQuoteMarkdown.build(
            username: post.username,
            postNumber: post.postNumber,
            topicID: topic.id,
            plainText: post.presentation?.plainText() ?? ""
        ) else {
            modalRouter.presentNotice(message: "该帖子暂无可引用内容。")
            return
        }

        let quickReplyDraft = replyDraft
        let initialBody = FireComposerInitialBody.merge(
            initialBody: quote,
            currentBody: quickReplyDraft
        ).text
        let quoteSelectionLocation = (quote as NSString).length
        composerContext = FireReplyComposerContext(
            topicId: topic.id,
            postId: post.id,
            replyToPostNumber: post.postNumber,
            replyToUsername: post.username
        )
        quickReplyBar.resignInputFocus()
        buildAndApplyChromeState()
        modalRouter.presentAdvancedComposer(
            route: FireComposerRoute(
                kind: .advancedReply(
                    topicID: topic.id,
                    topicTitle: displayedTopicTitle,
                    categoryID: displayedCategoryId,
                    replyToPostNumber: post.postNumber,
                    replyToUsername: post.username,
                    isPrivateMessage: isPrivateMessageThread
                )
            ),
            initialBody: initialBody,
            initialBodySelectionLocation: quoteSelectionLocation,
            onReplySubmitted: { [weak self] in
                guard let self else { return }
                self.replyDraft = ""
                self.composerContext = nil
                self.quickReplyError = nil
                self.buildAndApplyChromeState()
                Task {
                    await self.loadTopicDetail(targetPostNumber: post.postNumber, force: true)
                }
            },
            onSubmissionNotice: { [weak self] message in
                self?.modalRouter.presentNotice(message: message)
            }
        )
    }

    func submitQuickReply(_ payload: FireBottomInputPayload) {
        Task { @MainActor in
            let raw: String
            do {
                raw = try await composeQuickReplyRaw(from: payload)
            } catch {
                quickReplyError = error.localizedDescription
                buildAndApplyChromeState()
                return
            }

            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                quickReplyError = composerContext?.isBoost == true
                    ? "Boost 内容不能为空。"
                    : "回复内容不能为空。"
                buildAndApplyChromeState()
                return
            }

            if composerContext?.isBoost == true {
                submitBoostFromQuickReply(raw: trimmed)
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

            do {
                try await topicDetailStore.submitReply(
                    topicId: topicId,
                    raw: trimmed,
                    replyToPostNumber: replyToPostNumber
                )
                finishQuickReplySuccess()
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("pending review") {
                    finishQuickReplySuccess()
                    modalRouter.presentNotice(message: "回复已提交，等待审核。")
                    return
                }
                quickReplyError = message
                buildAndApplyChromeState()
            }
        }
    }

    func composeQuickReplyRaw(from payload: FireBottomInputPayload) async throws -> String {
        var parts: [String] = []
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        for image in payload.images {
            guard let data = image.fireJPEGDataForUpload() else { continue }
            let upload = try await viewModel.uploadImage(
                fileName: "reply-\(UUID().uuidString).jpg",
                mimeType: "image/jpeg",
                bytes: data
            )
            let alt = upload.originalFilename?.isEmpty == false
                ? upload.originalFilename!
                : "image"
            parts.append("![\(alt)](\(upload.shortUrl))")
        }
        return parts.joined(separator: "\n\n")
    }

    func finishQuickReplySuccess() {
        replyDraft = ""
        composerContext = nil
        quickReplyBar.resetAfterSend()
        quickReplyBar.resignInputFocus()
        buildAndApplyChromeState()
    }

    func searchQuickReplyMentions(term: String) async -> [FireBottomInputMention] {
        do {
            let result = try await viewModel.searchService.searchUsers(
                term: term,
                includeGroups: true,
                limit: 8,
                topicID: topic.id,
                categoryID: displayedCategoryId
            )
            let users = result.users.map { user in
                FireBottomInputMention(
                    handle: user.username,
                    displayName: user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? user.username
                )
            }
            let groups = result.groups.map { group in
                FireBottomInputMention(
                    handle: group.name,
                    displayName: group.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? group.name
                )
            }
            return users + groups
        } catch {
            return []
        }
    }

    func presentQuickReplyImagePicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 4
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func submitBoostFromQuickReply(raw: String) {
        guard let postId = composerContext?.postId else {
            quickReplyError = "找不到要 Boost 的帖子。"
            buildAndApplyChromeState()
            return
        }
        quickReplyError = nil
        buildAndApplyChromeState()
        Task { @MainActor in
            do {
                try await topicDetailStore.createBoost(
                    topicId: topic.id,
                    postId: postId,
                    raw: raw
                )
                finishQuickReplySuccess()
                FireMotionHaptics.success()
            } catch is CancellationError {
                // ignore
            } catch {
                FireMotionHaptics.error()
                quickReplyError = error.localizedDescription
                buildAndApplyChromeState()
            }
        }
    }

    func presentTopicBookmarkEditor() {
        modalRouter.presentBookmarkEditor(
            context: topicBookmarkContext,
            recoveryOriginURL: topicCloudflareRecoveryURL,
            onReload: { [weak self] in
                await self?.loadTopicDetail(force: true)
            }
        )
    }

    func presentPostBookmarkEditor(_ post: TopicPostState) {
        modalRouter.presentBookmarkEditor(
            context: postBookmarkContext(for: post),
            recoveryOriginURL: topicCloudflareRecoveryURL,
            onReload: { [weak self] in
                await self?.loadTopicDetail(force: true)
            }
        )
    }

    func presentPostEditor(_ post: TopicPostState) {
        modalRouter.presentPostEditor(
            topicID: topic.id,
            context: FirePostEditorContext(postID: post.id, postNumber: post.postNumber),
            onSaved: { [weak self] in
                await self?.loadTopicDetail(force: true)
            }
        )
    }

    func presentTopicEditor() {
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

    func presentFlagSheet(_ post: TopicPostState) {
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

    func updateTopicNotificationLevel(_ option: FireTopicNotificationLevelOption) {
        Task { @MainActor in
            do {
                try await viewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: topic.id,
                    notificationLevel: option.rawValue,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
                await loadTopicDetail(force: true)
                FireUIKitToast.show(option.cycleToastMessage, style: .success, in: view)
            } catch {
                // Reconcile toolbar glyph if the optimistic cycle preview diverged.
                buildAndApplyChromeState()
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

}

extension FireTopicDetailViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in
                    self?.quickReplyBar.insertImage(image)
                }
            }
        }
    }
}

extension FireTopicDetailViewController: FireAppearanceApplying {
    func applyAppearance(_ snapshot: FireAppearanceSnapshot) {
        let style = snapshot.userInterfaceStyle
        let styleChanged = lastColorAppearanceStyle != style
        lastColorAppearanceStyle = style
        viewModel.topicDetailLogger()?.info(
            "topic detail applyAppearance topic_id=\(row.topic.id) style=\(style.rawValue) token=\(snapshot.token) style_changed=\(styleChanged)"
        )
        applyAppearanceShell(snapshot)
        quickReplyBar.applyThemeColorsIfNeeded()
        feedController.refreshColorAppearance(snapshot)
    }
}

