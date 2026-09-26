import Combine
import UIKit

@MainActor
final class FireTopicDetailViewController: UIViewController, UIGestureRecognizerDelegate {
    let viewModel: FireAppViewModel
    let topicDetailStore: FireTopicDetailStore
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    let feedController: FireTopicDetailFeedController
    let paginationCoordinator: FireTopicDetailPaginationCoordinator
    let visibilityCoordinator: FireTopicDetailVisibilityCoordinator
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
            self?.topicDetailStore.snapshot(for: self?.row.topic.id ?? 0)?.rows.contains {
                $0.postId == postID && $0.isMutating
            } ?? false
        },
        isPostTextExpanded: { [weak self] postID in
            self?.expandedPostTextIDs.contains(postID) ?? false
        },
        isReplyThreadExpanded: { [weak self] postID in
            self?.expandedReplyRootPostIDs.contains(postID) ?? false
        },
        isLoadingPostReplyContext: { [weak self] postID in
            self?.topicDetailStore.snapshot(for: self?.row.topic.id ?? 0)?.rows.contains {
                $0.postId == postID && $0.isLoadingReplyContext
            } ?? false
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
            self.topicDetailStore.acknowledgeScrollTarget(
                topicId: self.topic.id,
                postNumber: postNumber
            )
        },
        onLoadMoreTopicPosts: { [weak self] in
            guard let self else { return false }
            self.topicDetailStore.loadMore(topicId: self.topic.id)
            return true
        },
        onReloadTopicAiSummary: { [weak self] in
            guard let self else { return }
            self.topicDetailStore.reloadAiSummary(topicId: self.topic.id, skipAgeCheck: true)
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
        onAcceptSolution: { [weak self] post, accepted in
            self?.setSolutionAccepted(post, accepted: accepted)
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
    var pendingSnapshotWork: FireTopicDetailSnapshotWork?
    var cancellables = Set<AnyCancellable>()
    var lastAppliedCollectionRevision: UInt64 = 0
    var lastAppliedChromeRevision: UInt64 = 0
    var lastAppliedSidecarRevision: UInt64 = 0
    var lastAppliedInteractionRevision: UInt64 = 0
    var lastAppliedComposerRevision: UInt64 = 0
    var lastFeedSnapshot: FireTopicDetailRuntimeSnapshot?
    var adoptedRenderProjection: FireTopicDetailAdoptedProjection?
    var deferredFeedApply: FireTopicDetailDeferredFeedApply?
    var deferredFeedApplyGeneration: UInt64 = 0

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
            topicDetailStore.endReplyTyping(topicId: row.topic.id)
        }
    }

    var topic: TopicSummaryState {
        row.topic
    }

    var detailSnapshot: FireTopicDetailSnapshot? {
        topicDetailStore.snapshot(for: topic.id)
    }

    var displayedTopicTitle: String {
        let trimmedDetailTitle = detailSnapshot?.chrome.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailTitle.isEmpty {
            return trimmedDetailTitle
        }
        let trimmedRowTitle = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRowTitle.isEmpty ? "话题 \(topic.id)" : trimmedRowTitle
    }

    var displayedTopicSlug: String {
        let trimmedDetailSlug = detailSnapshot?.chrome.slug.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDetailSlug.isEmpty {
            return trimmedDetailSlug
        }
        return topic.slug.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayedCategoryId: UInt64? {
        detailSnapshot?.chrome.categoryId ?? topic.categoryId
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
        FireTopicPresentation.isPrivateMessageArchetype(detailSnapshot?.chrome.archetype)
    }

    var topicCloudflareRecoveryURL: URL {
        viewModel.cloudflareRecoveryTopicURL(
            topicId: topic.id,
            topicSlug: displayedTopicSlug
        )
    }


    func configureRuntime() {
        let startedAt = Date()
        viewModel.topicDetailLogger()?.debug("topic detail configure runtime start topic_id=\(row.topic.id)")
        feedController.paginationCoordinator = paginationCoordinator
        feedController.visibilityCoordinator = visibilityCoordinator
        feedController.diagnosticsLogger = viewModel.topicDetailLogger()
        feedController.onRefresh = { [weak self] in
            await self?.performRefresh()
        }
        feedController.onBackgroundTap = { [weak self] in
            self?.quickReplyBar.resignInputFocus()
        }
        feedController.onScrollInteractionChanged = { [weak self] isActive in
            guard let self else { return }
            self.topicDetailStore.noteScrollInteraction(
                topicId: self.row.topic.id,
                active: isActive
            )
            self.toolbarCoordinator.updateScrollChrome(
                isTitlePinned: self.feedController.isTitleCurrentlyPinned,
                isScrolling: isActive
            )
            if !isActive {
                self.flushDeferredFeedApplyIfNeeded()
            }
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
        paginationCoordinator.onNoteFilteredFeedTail = { [weak self] itemCount, visibleMaxItem in
            guard let self else { return }
            self.topicDetailStore.noteFilteredFeedTail(
                topicId: self.topic.id,
                itemCount: itemCount,
                visibleMaxItem: visibleMaxItem
            )
        }

        visibilityCoordinator.feedController = feedController
        visibilityCoordinator.onVisiblePostNumbersChanged = { [weak self] visiblePostNumbers in
            self?.handleVisiblePostNumbersChanged(visiblePostNumbers)
        }
        visibilityCoordinator.onScrollTargetHandled = { [weak self] postNumber in
            guard let self else { return }
            self.topicDetailStore.acknowledgeScrollTarget(
                topicId: self.topic.id,
                postNumber: postNumber
            )
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


    nonisolated static func elapsedMilliseconds(since startedAt: Date) -> Int64 {
        Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
    }

    nonisolated static func formatSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    static let reactionPickerAutoCollapseSeconds: TimeInterval = 3.5
}

