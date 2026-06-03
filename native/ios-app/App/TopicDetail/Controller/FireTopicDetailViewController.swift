import AsyncDisplayKit
import Combine
import UIKit

/// Page coordinator for the topic-detail screen.
///
/// Owns:
/// - Page lifecycle (begin/end, initial load, message-bus subscription)
/// - `FireTopicDetailRootNode` and the `ASCollectionNode` feed surface
/// - `FireTopicTimingTracker` lifecycle tied to viewWillAppear/viewDidDisappear
/// - Route-anchor and pending-scroll-target handling
/// - Toolbar chrome via `FireTopicDetailToolbarCoordinator`
///
/// Does NOT own:
/// - Store state (`FireTopicDetailStore` is the entity source of truth)
/// - Node creation details (delegated to feed coordinator in Task 4)
@MainActor
final class FireTopicDetailViewController: UIViewController {

    // MARK: - Inputs

    let viewModel: FireAppViewModel
    let topicDetailStore: FireTopicDetailStore
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    // MARK: - Owned State

    let rootNode: FireTopicDetailRootNode
    private let detailOwnerToken: String
    private let timingTracker: FireTopicTimingTracker

    // MARK: - Coordinators

    private lazy var toolbarCoordinator = FireTopicDetailToolbarCoordinator(
        viewController: self,
        viewModel: viewModel,
        row: row
    )

    // MARK: - In-flight Tasks

    private var initialLoadTask: Task<Void, Never>?
    private var subscriptionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

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
        self.rootNode = FireTopicDetailRootNode()
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

    // MARK: - View Lifecycle

    override func loadView() {
        view = rootNode.view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        toolbarCoordinator.configureNavigationItem(navigationItem)
        beginPageLifecycle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.setAPMRoute("topic.detail.\(row.topic.id)")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            await timingTracker.setSceneActive(true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Only end lifecycle if the controller is being truly removed, not just covered.
        // UIKit's isMovingFromParent / isBeingDismissed tells us this precisely.
        if isMovingFromParent || isBeingDismissed {
            endPageLifecycle()
        }
        viewModel.restoreTopLevelAPMRoute()
        Task {
            await timingTracker.stop()
            await topicDetailStore.endTopicReplyPresence(topicId: row.topic.id)
        }
    }

    // MARK: - Page Lifecycle

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

    // MARK: - Initial Load

    private func kickOffInitialLoad() {
        initialLoadTask?.cancel()
        initialLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadTopicDetail(targetPostNumber: self.scrollToPostNumber)
        }
    }

    func loadTopicDetail(
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        let detail = topicDetailStore.topicDetail(for: row.topic.id)
        let topicSlug = detail?.slug ?? row.topic.slug
        await topicDetailStore.loadTopicDetail(
            topicId: row.topic.id,
            topicSlug: topicSlug.isEmpty ? nil : topicSlug,
            targetPostNumber: targetPostNumber,
            force: force
        )
    }

    // MARK: - Message Bus Subscription

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

    // MARK: - Store Observation

    private func subscribeToStoreRevisions() {
        topicDetailStore.$topicCollectionRevisions
            .map { [topicId = row.topic.id] revisions in revisions[topicId] ?? 0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleCollectionRevisionChanged()
            }
            .store(in: &cancellables)
    }

    private func handleCollectionRevisionChanged() {
        toolbarCoordinator.update(
            detail: topicDetailStore.topicDetail(for: row.topic.id)
        )
        // Feed pipeline re-assembly handled in Task 3+.
    }

    // MARK: - Visible Posts

    func handleVisiblePostNumbersChanged(_ visiblePostNumbers: Set<UInt32>) {
        if !visiblePostNumbers.isEmpty {
            timingTracker.recordInteraction()
        }
        timingTracker.updateVisiblePostNumbers(visiblePostNumbers)
        topicDetailStore.handleVisiblePostNumbersChanged(
            topicId: row.topic.id,
            visiblePostNumbers: visiblePostNumbers
        )
    }

    // MARK: - Scroll Target

    func markScrollTargetSatisfied(_ postNumber: UInt32) {
        topicDetailStore.markScrollTargetSatisfied(topicId: row.topic.id, postNumber: postNumber)
    }
}
