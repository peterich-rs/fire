import AsyncDisplayKit
import UIKit

@MainActor
final class FireTopicDetailFeedController: NSObject,
    @preconcurrency ASCollectionDataSource,
    @preconcurrency ASCollectionDelegate,
    UIScrollViewDelegate
{
    struct PendingCollectionUpdate {
        let updatePlan: FireTopicDetailCollectionUpdatePlan
        let previousItems: [FireTopicDetailRuntimeItem]
        let nextItems: [FireTopicDetailRuntimeItem]
        let animated: Bool
        let completion: () -> Void
    }

    static let collectionUpdateRetryDelay: TimeInterval = 0.05
    static let maxPendingCollectionUpdateAttempts = 8
    static let maxReplyFooterReloadAttempts = 8

    let collectionNode = ASCollectionNode(
        collectionViewLayout: FireTopicDetailFeedController.makeCollectionLayout()
    )

    var currentItems: [FireTopicDetailRuntimeItem] = []
    var currentConfiguration: FireTopicDetailRuntimeConfiguration?
    var lastLayoutContentWidth: CGFloat?
    var pendingCollectionUpdate: PendingCollectionUpdate?
    var pendingCollectionUpdateAttempts = 0
    var isPendingCollectionUpdateDrainScheduled = false
    let cellFactory = FireTopicDetailFeedCellFactory()
    lazy var dismissKeyboardTapGestureRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleBackgroundTap)
    )

    weak var paginationCoordinator: FireTopicDetailPaginationCoordinator?
    weak var visibilityCoordinator: FireTopicDetailVisibilityCoordinator?
    var layoutManager: FirePostLayoutManager?
    var diagnosticsLogger: FireHostLogger?

    var onRefresh: (() async -> Void)?
    var onBackgroundTap: (() -> Void)?
    var onScrollInteractionChanged: ((Bool) -> Void)?
    /// Reports whether the in-feed topic title has scrolled under the nav bar.
    var onTitlePinStateChanged: ((Bool) -> Void)?
    var lastPublishedScrollInteractionActive = false
    var lastPublishedTitlePinned = false
    var deferredIdleCheckGeneration: UInt64 = 0

    var isTitleCurrentlyPinned: Bool {
        resolveIsTitlePinned()
    }

    func setup() {
        collectionNode.dataSource = self
        collectionNode.delegate = self
        configureTextureRanges()

        assertFeedShellAppearance()
        collectionNode.view.alwaysBounceVertical = true
        collectionNode.view.showsVerticalScrollIndicator = false
        collectionNode.view.showsHorizontalScrollIndicator = false
        collectionNode.view.keyboardDismissMode = .interactive
        dismissKeyboardTapGestureRecognizer.cancelsTouchesInView = false
        collectionNode.view.addGestureRecognizer(dismissKeyboardTapGestureRecognizer)

        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.performPullToRefresh()
        }, for: .valueChanged)
        collectionNode.view.refreshControl = refreshControl
        // Tint tracks dynamic accent; shell canvas is re-asserted on theme/PTR.

        cellFactory.onRequestLoadMore = { [weak self] in
            guard let self else { return }
            self.paginationCoordinator?.requestLoadMore(
                forceEvaluation: true,
                allowRetry: true
            )
        }
    }
}
