import AsyncDisplayKit
import UIKit

private let fireTopicDetailAnimatedUpdateItemDeltaLimit = 4
private let fireTopicDetailVisiblePostPublishDebounce = Duration.milliseconds(240)
private let fireTopicDetailFooterLoadMoreDistance: CGFloat = 240

private struct FireTopicDetailDeferredRuntimeCallbacks {
    var preloadVisiblePostNumbers: Set<UInt32> = []
    var forceVisiblePostPublish = false
    var forceLoadMoreEvaluation = false
    var shouldRetryLoadMoreRestoreFooter = false

    var hasWork: Bool {
        !preloadVisiblePostNumbers.isEmpty
            || forceVisiblePostPublish
            || forceLoadMoreEvaluation
            || shouldRetryLoadMoreRestoreFooter
    }

    mutating func merge(
        preloadVisiblePostNumbers: Set<UInt32> = [],
        forceVisiblePostPublish: Bool = false,
        forceLoadMoreEvaluation: Bool = false,
        shouldRetryLoadMoreRestoreFooter: Bool = false
    ) {
        self.preloadVisiblePostNumbers.formUnion(preloadVisiblePostNumbers)
        self.forceVisiblePostPublish = self.forceVisiblePostPublish || forceVisiblePostPublish
        self.forceLoadMoreEvaluation = self.forceLoadMoreEvaluation || forceLoadMoreEvaluation
        self.shouldRetryLoadMoreRestoreFooter =
            self.shouldRetryLoadMoreRestoreFooter || shouldRetryLoadMoreRestoreFooter
    }
}


struct FireTopicDetailCollectionUpdatePlan: Equatable {
    let deletions: [IndexPath]
    let insertions: [IndexPath]
    let reloads: [IndexPath]

    var isEmpty: Bool {
        deletions.isEmpty && insertions.isEmpty && reloads.isEmpty
    }
}

func fireTopicDetailCollectionUpdatePlan(
    from current: [FireTopicDetailRuntimeItem],
    to next: [FireTopicDetailRuntimeItem]
) -> FireTopicDetailCollectionUpdatePlan {
    let currentIDs = current.map(\.id)
    let nextIDs = next.map(\.id)
    let difference = nextIDs.difference(from: currentIDs)

    let deletions = difference.compactMap { change -> IndexPath? in
        guard case .remove(let offset, _, _) = change else {
            return nil
        }
        return IndexPath(item: offset, section: 0)
    }
    .sorted()

    let insertions = difference.compactMap { change -> IndexPath? in
        guard case .insert(let offset, _, _) = change else {
            return nil
        }
        return IndexPath(item: offset, section: 0)
    }
    .sorted()

    let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
    let insertedItems = Set(insertions.map(\.item))
    let reloads = next.enumerated().compactMap { index, item -> IndexPath? in
        guard insertedItems.contains(index) == false,
              let previous = currentByID[item.id],
              previous.hasSameRenderedContent(as: item) == false else {
            return nil
        }
        return IndexPath(item: index, section: 0)
    }

    return FireTopicDetailCollectionUpdatePlan(
        deletions: deletions,
        insertions: insertions,
        reloads: reloads
    )
}

struct FireTopicDetailLoadMoreProbe: Equatable {
    let itemCount: Int
    let visibleMaxItem: Int?
    let footerDistanceBucket: Int?
}

func fireTopicDetailLoadMoreProbe(
    itemCount: Int,
    visibleMaxItem: Int?,
    footerDistanceToViewport: CGFloat?
) -> FireTopicDetailLoadMoreProbe {
    FireTopicDetailLoadMoreProbe(
        itemCount: itemCount,
        visibleMaxItem: visibleMaxItem,
        footerDistanceBucket: fireTopicDetailFooterDistanceBucket(footerDistanceToViewport)
    )
}

func fireTopicDetailFooterDistanceBucket(
    _ footerDistanceToViewport: CGFloat?,
    footerTriggerDistance: CGFloat = fireTopicDetailFooterLoadMoreDistance
) -> Int? {
    guard let footerDistanceToViewport, footerDistanceToViewport.isFinite else {
        return nil
    }
    return footerDistanceToViewport <= footerTriggerDistance ? 0 : 1
}

func fireTopicDetailShouldLoadMore(
    itemCount: Int,
    visibleMaxItem: Int?,
    footerDistanceToViewport: CGFloat? = nil,
    trailingThreshold: Int = 15,
    footerTriggerDistance: CGFloat = fireTopicDetailFooterLoadMoreDistance
) -> Bool {
    if let footerDistanceToViewport, footerDistanceToViewport.isFinite,
       footerDistanceToViewport <= footerTriggerDistance {
        return true
    }
    guard itemCount > 0, let visibleMaxItem else {
        return false
    }
    return itemCount - visibleMaxItem <= trailingThreshold
}

func fireTopicDetailShouldHoldLoadingFooter(
    previousFooterState: FireTopicDetailRuntimeReplyFooterState?,
    nextFooterState: FireTopicDetailRuntimeReplyFooterState?,
    itemCount: Int,
    visibleMaxItem: Int?,
    footerDistanceToViewport: CGFloat?
) -> Bool {
    guard previousFooterState == .loadingFooter,
          nextFooterState == .loadMore else {
        return false
    }
    return fireTopicDetailShouldLoadMore(
        itemCount: itemCount,
        visibleMaxItem: visibleMaxItem,
        footerDistanceToViewport: footerDistanceToViewport
    )
}

func fireTopicDetailVisibleNodeUpdateIndices(
    from current: [FireTopicDetailRuntimeItem],
    to next: [FireTopicDetailRuntimeItem]
) -> [Int] {
    guard current.count == next.count else {
        return []
    }
    return zip(current.indices, zip(current, next)).compactMap { index, pair in
        pair.1.needsVisibleNodeUpdate(comparedTo: pair.0) ? index : nil
    }
}

func fireTopicDetailVisiblePostRelayoutIndexPaths(
    reloads: [IndexPath],
    nextItems: [FireTopicDetailRuntimeItem],
    visibleIndexPaths: Set<IndexPath>
) -> [IndexPath] {
    reloads.filter { indexPath in
        guard visibleIndexPaths.contains(indexPath),
              indexPath.item >= 0,
              indexPath.item < nextItems.count else {
            return false
        }
        switch nextItems[indexPath.item].kind {
        case .originalPost, .reply:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class FireTopicDetailListViewController: UIViewController,
    @preconcurrency ASCollectionDataSource,
    @preconcurrency ASCollectionDelegate,
    UIScrollViewDelegate
{
    private let collectionNode = ASCollectionNode(
        collectionViewLayout: FireTopicDetailListViewController.makeCollectionLayout()
    )
    private var configuration: FireTopicDetailRuntimeConfiguration?
    private var currentItems: [FireTopicDetailRuntimeItem] = []
    private var handledScrollTarget: UInt32?
    private var lastPublishedVisiblePostNumbers: Set<UInt32> = []
    private var lastLoadMoreProbe: FireTopicDetailLoadMoreProbe?
    private var lastRejectedLoadMoreProbe: FireTopicDetailLoadMoreProbe?
    private var layoutInvalidationTask: Task<Void, Never>?
    private var visiblePostNumbersPublishTask: Task<Void, Never>?
    private var pendingVisiblePostNumbers: Set<UInt32>?
    private var lastEmptyReplyFooterPreloadKey: AnyHashable?
    private var lastLayoutContentWidth: CGFloat?
    private var loadMoreRetryTask: Task<Void, Never>?
    private var deferredRuntimeCallbacks = FireTopicDetailDeferredRuntimeCallbacks()
    private var hasDeferredRuntimeCallbacksScheduled = false

    deinit {
        layoutInvalidationTask?.cancel()
        visiblePostNumbersPublishTask?.cancel()
        loadMoreRetryTask?.cancel()
    }

    private static func makeCollectionLayout() -> UICollectionViewFlowLayout {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.estimatedItemSize = .zero
        return flowLayout
    }

    private func configureTextureRanges() {
        collectionNode.leadingScreensForBatching = 1.5

        var displayTuning = ASRangeTuningParameters()
        displayTuning.leadingBufferScreenfuls = 1.0
        displayTuning.trailingBufferScreenfuls = 0.5
        collectionNode.setTuningParameters(displayTuning, for: .display)

        var preloadTuning = ASRangeTuningParameters()
        preloadTuning.leadingBufferScreenfuls = 1.5
        preloadTuning.trailingBufferScreenfuls = 1.0
        collectionNode.setTuningParameters(preloadTuning, for: .preload)
    }

    override func loadView() {
        collectionNode.backgroundColor = .systemBackground
        collectionNode.view.backgroundColor = .systemBackground
        collectionNode.view.alwaysBounceVertical = true
        collectionNode.view.keyboardDismissMode = .interactive
        view = collectionNode.view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionNode.dataSource = self
        collectionNode.delegate = self
        configureTextureRanges()

        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.performRefresh()
        }, for: .valueChanged)
        collectionNode.view.refreshControl = refreshControl
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        invalidateLayoutIfWidthChanged()
    }

    func update(configuration: FireTopicDetailRuntimeConfiguration) {
        let previousInvalidationToken = self.configuration?.snapshotInvalidationToken
        let previousItems = currentItems
        if previousInvalidationToken != configuration.snapshotInvalidationToken {
            lastRejectedLoadMoreProbe = nil
        }
        self.configuration = configuration

        if Self.canReuseCurrentSnapshot(
            previousInvalidationToken: previousInvalidationToken,
            nextInvalidationToken: configuration.snapshotInvalidationToken,
            hasCurrentItems: !currentItems.isEmpty
        ) {
            handlePendingScrollTargetIfNeeded()
            scheduleDeferredRuntimeCallbacks(
                forceLoadMoreEvaluation: false
            )
            return
        }

        let runtimeSnapshot = configuration.makeSnapshot()
        guard !Self.itemsHaveSameRenderedContent(runtimeSnapshot.items, previousItems) else {
            currentItems = runtimeSnapshot.items
            applyVisibleNodeUpdatesIfNeeded(
                from: previousItems,
                to: runtimeSnapshot.items,
                configuration: configuration
            )
            handlePendingScrollTargetIfNeeded()
            scheduleDeferredRuntimeCallbacks(
                forceLoadMoreEvaluation: false
            )
            return
        }

        currentItems = runtimeSnapshot.items
        lastLoadMoreProbe = nil
        applyCollectionUpdate(
            from: previousItems,
            to: runtimeSnapshot.items
        )
    }

    nonisolated static func itemsHaveSameRenderedContent(
        _ lhs: [FireTopicDetailRuntimeItem],
        _ rhs: [FireTopicDetailRuntimeItem]
    ) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { $0.hasSameRenderedContent(as: $1) }
    }

    nonisolated static func canReuseCurrentSnapshot(
        previousInvalidationToken: AnyHashable?,
        nextInvalidationToken: AnyHashable,
        hasCurrentItems: Bool
    ) -> Bool {
        hasCurrentItems && previousInvalidationToken == nextInvalidationToken
    }

    nonisolated static func allowsAnimatedUpdate(
        isViewAttached: Bool,
        isScrollInteractionActive: Bool,
        hasCurrentItems: Bool,
        itemDelta: Int
    ) -> Bool {
        let absoluteItemDelta = abs(itemDelta)
        return isViewAttached
            && !isScrollInteractionActive
            && hasCurrentItems
            && absoluteItemDelta <= fireTopicDetailAnimatedUpdateItemDeltaLimit
    }

    private var isScrollInteractionActive: Bool {
        collectionNode.view.isDragging
            || collectionNode.view.isDecelerating
            || collectionNode.view.isTracking
    }

    // MARK: - ASCollectionDataSource

    func numberOfSections(in collectionNode: ASCollectionNode) -> Int {
        1
    }

    func collectionNode(_ collectionNode: ASCollectionNode, numberOfItemsInSection section: Int) -> Int {
        currentItems.count
    }

    func collectionNode(_ collectionNode: ASCollectionNode, nodeForItemAt indexPath: IndexPath) -> ASCellNode {
        guard indexPath.item < currentItems.count else {
            return ASCellNode()
        }
        let item = currentItems[indexPath.item]
        guard let configuration else {
            return ASCellNode()
        }

        return makeCellNode(for: item, configuration: configuration)
    }

    func collectionNode(_ collectionNode: ASCollectionNode, constrainedSizeForItemAt indexPath: IndexPath) -> ASSizeRange {
        let width = layoutContentWidth()
        return ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
    }

    // MARK: - ASCollectionDelegate

    func collectionNode(_ collectionNode: ASCollectionNode, willBeginBatchFetchWith context: ASBatchContext) {
        if let configuration,
           configuration.detail != nil,
           configuration.hasMoreTopicPosts,
           !configuration.isLoadingMoreTopicPosts,
           let probe = currentLoadMoreProbe() {
            _ = attemptLoadMore(
                configuration: configuration,
                probe: probe,
                allowRetry: true,
                bypassRejectedProbeGuard: false
            )
        }
        context.completeBatchFetching(true)
    }

    func shouldBatchFetch(for collectionNode: ASCollectionNode) -> Bool {
        guard let configuration else {
            return false
        }
        guard configuration.detail != nil
            && configuration.hasMoreTopicPosts
            && !configuration.isLoadingMoreTopicPosts else {
            return false
        }
        guard let probe = currentLoadMoreProbe() else {
            return false
        }
        return lastRejectedLoadMoreProbe != probe
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        publishVisiblePostNumbersIfChanged()
        loadMoreIfNeeded()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {}

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {}

    // MARK: - Cell Node Factory

    private func makeCellNode(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> ASCellNode {
        if let postContext = configuration.postContext(for: item) {
            return makePostCellNode(for: postContext, configuration: configuration)
        }

        switch item.kind {
        case .header:
            return FireTopicDetailHeaderCellNode(configuration: configuration)
        case .aiSummary:
            return FireTopicDetailAISummaryCellNode(configuration: configuration)
        case .stats:
            return makeStatsCellNode(configuration: configuration)
        case .topicVote:
            return makeTopicVoteCellNode(configuration: configuration)
        case .repliesHeader:
            return makeRepliesHeaderCellNode(configuration: configuration)
        case .replyFooter:
            triggerEmptyReplyFooterPreloadIfNeeded(configuration: configuration)
            return makeReplyFooterCellNode(configuration: configuration)
        case .bodyState:
            return makeBodyStateCellNode(configuration: configuration)
        case .originalPost, .reply:
            return makeMissingPostCellNode()
        case .notice:
            return makeTextCellNode(for: item, configuration: configuration)
        }
    }

    private func makePostCellNode(
        for context: FireTopicDetailRuntimePostContext,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> ASCellNode {
        let node = FirePostCellNode()
        configurePostCellNode(
            node,
            with: context,
            configuration: configuration
        )
        return node
    }

    private func configurePostCellNode(
        _ node: FirePostCellNode,
        with context: FireTopicDetailRuntimePostContext,
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        node.configure(
            payload: FirePostCellRenderPayload(
                post: context.post,
                renderContent: context.renderContent,
                baseURLString: configuration.baseURLString,
                canWriteInteractions: configuration.canWriteInteractions,
                isMutating: configuration.isMutatingPost(context.post.id),
                replyContext: context.replyContext,
                replyTargetPostNumber: context.replyTargetPostNumber,
                replyShortcutCount: context.replyShortcutCount,
                isLoadingReplyContext: context.isLoadingReplyContext,
                textExpansionState: context.textExpansionState,
                showsDivider: context.showsDivider,
                layoutWidth: layoutContentWidth()
            ),
            callbacks: postCallbacks(configuration: configuration),
            depth: context.depth,
            showsThreadLine: context.showsThreadLine,
            showsDivider: context.showsDivider
        )
    }

    private func applyVisibleNodeUpdatesIfNeeded(
        from previousItems: [FireTopicDetailRuntimeItem],
        to nextItems: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        let indices = fireTopicDetailVisibleNodeUpdateIndices(
            from: previousItems,
            to: nextItems
        )
        guard !indices.isEmpty else {
            return
        }

        for index in indices {
            guard index < nextItems.count,
                  let postContext = configuration.postContext(for: nextItems[index]),
                  let node = collectionNode.nodeForItem(at: IndexPath(item: index, section: 0)) as? FirePostCellNode else {
                continue
            }
            configurePostCellNode(
                node,
                with: postContext,
                configuration: configuration
            )
            node.invalidateCalculatedLayout()
            node.setNeedsLayout()
        }
    }

    private func makeStatsCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true

        let dividerNode = ASDisplayNode()
        dividerNode.backgroundColor = .separator
        dividerNode.style.preferredSize = CGSize(width: max(layoutContentWidth(), 1), height: 0.5)

        let replyNode = makeStatNode(
            value: "\(configuration.displayedReplyCount)",
            label: "回复"
        )
        let viewNode = makeStatNode(
            value: "\(configuration.displayedViewsCount)",
            label: "浏览"
        )
        let interactionNode = makeStatNode(
            value: configuration.displayedInteractionCount.map(String.init) ?? "...",
            label: "互动"
        )

        node.layoutSpecBlock = { _, _ in
            let stack = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 0,
                justifyContent: .spaceBetween,
                alignItems: .center,
                children: [replyNode, viewNode, interactionNode]
            )
            stack.style.flexGrow = 1.0
            let rootStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 0,
                justifyContent: .start,
                alignItems: .stretch,
                children: [dividerNode, stack]
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 12, left: 16, bottom: 8, right: 16),
                child: rootStack
            )
        }
        return node
    }

    private func makeStatNode(value: String, label: String) -> ASDisplayNode {
        let valueNode = ASTextNode()
        let captionFont = UIFont.preferredFont(forTextStyle: .subheadline)
        valueNode.attributedText = NSAttributedString(
            string: value,
            attributes: [
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                    for: UIFont.monospacedDigitSystemFont(ofSize: captionFont.pointSize, weight: .semibold)
                ),
                .foregroundColor: UIColor.label,
            ]
        )

        let labelNode = ASTextNode()
        labelNode.attributedText = NSAttributedString(
            string: label,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption2),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )

        let wrapper = ASDisplayNode()
        wrapper.automaticallyManagesSubnodes = true
        wrapper.layoutSpecBlock = { _, _ in
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 2,
                justifyContent: .start,
                alignItems: .stretch,
                children: [valueNode, labelNode]
            )
            stack.style.flexGrow = 1.0
            return stack
        }
        return wrapper
    }

    private func makeTopicVoteCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        guard let detail = configuration.detail else { return ASCellNode() }

        let wrapperNode = ASCellNode()
        wrapperNode.automaticallyManagesSubnodes = true
        wrapperNode.backgroundColor = .systemBackground

        let containerNode = ASDisplayNode()
        containerNode.backgroundColor = .secondarySystemBackground
        containerNode.cornerRadius = 8
        containerNode.automaticallyManagesSubnodes = true

        let titleNode = ASTextNode()
        titleNode.attributedText = NSAttributedString(
            string: "\(detail.voteCount) 票",
            attributes: [
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                    for: UIFont.systemFont(
                        ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                        weight: .semibold
                    )
                ),
                .foregroundColor: FireTopicDetailRuntimeCellColors.accent,
            ]
        )

        let statusNode = ASTextNode()
        if detail.userVoted {
            statusNode.attributedText = NSAttributedString(
                string: "你已投票",
                attributes: [
                    .font: UIFontMetrics(forTextStyle: .caption1).scaledFont(
                        for: UIFont.systemFont(
                            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                            weight: .semibold
                        )
                    ),
                    .foregroundColor: UIColor.systemGreen,
                ]
            )
        }
        statusNode.isHidden = !detail.userVoted
        statusNode.style.flexShrink = 1.0

        let toggleNode = ASButtonNode()
        toggleNode.setTitle(
            detail.userVoted ? "取消投票" : "投一票",
            with: UIFont.preferredFont(forTextStyle: .caption1),
            with: detail.userVoted ? .label : .white,
            for: .normal
        )
        toggleNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        toggleNode.backgroundColor = detail.userVoted ? .tertiarySystemFill : FireTopicDetailRuntimeCellColors.accent
        toggleNode.cornerRadius = 16
        toggleNode.clipsToBounds = true
        toggleNode.isEnabled = configuration.canWriteInteractions
        toggleNode.addTarget(self, action: #selector(handleToggleTopicVote), forControlEvents: .touchUpInside)

        let votersNode = ASButtonNode()
        votersNode.setImage(UIImage(systemName: "person.3"), for: .normal)
        votersNode.setTitle(
            "查看投票用户",
            with: UIFont.preferredFont(forTextStyle: .caption1),
            with: FireTopicDetailRuntimeCellColors.accent,
            for: .normal
        )
        votersNode.contentSpacing = 6
        votersNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        votersNode.addTarget(self, action: #selector(handleShowTopicVoters), forControlEvents: .touchUpInside)

        containerNode.layoutSpecBlock = { _, _ in
            let spacer = ASLayoutSpec()
            spacer.style.flexGrow = 1.0
            let headerChildren: [ASLayoutElement] = detail.userVoted
                ? [titleNode, spacer, statusNode]
                : [titleNode, spacer]
            let headerRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 10,
                justifyContent: .start,
                alignItems: .center,
                children: headerChildren
            )
            let buttonRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 10,
                justifyContent: .start,
                alignItems: .center,
                children: [toggleNode, votersNode]
            )
            let innerStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 10,
                justifyContent: .start,
                alignItems: .stretch,
                children: [headerRow, buttonRow]
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14),
                child: innerStack
            )
        }

        wrapperNode.layoutSpecBlock = { _, _ in
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 8, left: 16, bottom: 4, right: 16),
                child: containerNode
            )
        }
        return wrapperNode
    }

    private func makeRepliesHeaderCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let titleNode = ASTextNode()
        titleNode.attributedText = NSAttributedString(
            string: "回复",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.label,
            ]
        )

        let countNode = ASTextNode()
        let countText: String
        if configuration.detail != nil {
            if configuration.loadedReplyCount < configuration.totalReplyCount {
                countText = "已加载 \(configuration.loadedReplyCount) / \(configuration.totalReplyCount) 条"
            } else {
                countText = "\(configuration.totalReplyCount) 条 · \(configuration.displayedFloorCount) 楼"
            }
        } else {
            countText = ""
        }
        countNode.attributedText = NSAttributedString(
            string: countText,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )
        countNode.style.flexShrink = 1.0

        node.layoutSpecBlock = { _, _ in
            let spacer = ASLayoutSpec()
            spacer.style.flexGrow = 1.0
            let stack = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 12,
                justifyContent: .start,
                alignItems: .center,
                children: [titleNode, spacer, countNode]
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 18, left: 16, bottom: 14, right: 16),
                child: stack
            )
        }
        return node
    }

    private func makeReplyFooterCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let state = configuration.replyFooterState

        let childElement: ASLayoutElement?
        switch state {
        case .none:
            childElement = nil
        case .empty:
            let label = ASTextNode()
            label.attributedText = NSAttributedString(
                string: "还没有回复",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
            childElement = label
        case .loadMore:
            let buttonNode = ASButtonNode()
            buttonNode.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
            buttonNode.setTitle(
                "查看更多回复",
                with: UIFont.preferredFont(forTextStyle: .subheadline),
                with: FireTopicDetailRuntimeCellColors.accent,
                for: .normal
            )
            buttonNode.contentSpacing = 6
            buttonNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            buttonNode.isEnabled = true
            buttonNode.addTarget(self, action: #selector(handleLoadMoreReplies), forControlEvents: .touchUpInside)
            childElement = buttonNode
        case .loadingFooter:
            let label = ASTextNode()
            label.attributedText = NSAttributedString(
                string: "正在加载更多回复...",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
            let indicator = ASDisplayNode(viewBlock: {
                let view = UIActivityIndicatorView(style: .medium)
                view.startAnimating()
                return view
            })
            indicator.style.preferredSize = CGSize(width: 20, height: 20)
            childElement = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 8,
                justifyContent: .center,
                alignItems: .center,
                children: [indicator, label]
            )
        }

        node.layoutSpecBlock = { _, constrainedSize in
            let height = max(constrainedSize.min.height, 44)
            let child = childElement ?? ASLayoutSpec()
            let sized = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 0,
                justifyContent: .center,
                alignItems: .center,
                children: [child]
            )
            sized.style.preferredSize = CGSize(width: constrainedSize.max.width, height: height)
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16),
                child: sized
            )
        }
        return node
    }

    private func makeBodyStateCellNode(configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let stackChildren: [ASLayoutElement]
        if configuration.isLoadingTopic {
            let label = ASTextNode()
            label.attributedText = NSAttributedString(
                string: "加载中...",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .caption1),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
            stackChildren = [label]
        } else {
            let messageNode = ASTextNode()
            messageNode.attributedText = NSAttributedString(
                string: configuration.detailError ?? "加载帖子",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .caption1),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
            messageNode.maximumNumberOfLines = 0

            let buttonNode = ASButtonNode()
            buttonNode.setTitle(
                configuration.detailError == nil ? "加载" : "重试",
                with: UIFont.preferredFont(forTextStyle: .subheadline),
                with: FireTopicDetailRuntimeCellColors.accent,
                for: .normal
            )
            buttonNode.addTarget(self, action: #selector(handleLoadTopicDetail), forControlEvents: .touchUpInside)

            stackChildren = [messageNode, buttonNode]
        }

        node.layoutSpecBlock = { _, constrainedSize in
            let height = max(constrainedSize.min.height, 96)
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 8,
                justifyContent: .center,
                alignItems: .center,
                children: stackChildren
            )
            let sized = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 8,
                justifyContent: .center,
                alignItems: .center,
                children: [stack]
            )
            sized.style.preferredSize = CGSize(width: constrainedSize.max.width, height: height)
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
                child: sized
            )
        }
        return node
    }

    private func makeTextCellNode(for item: FireTopicDetailRuntimeItem, configuration: FireTopicDetailRuntimeConfiguration) -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let titleNode = ASTextNode()
        titleNode.maximumNumberOfLines = 0
        let bodyNode = ASTextNode()
        bodyNode.maximumNumberOfLines = 0

        switch item.kind {
        case .header:
            let status = configuration.row.statusLabels.joined(separator: " · ")
            titleNode.attributedText = NSAttributedString(
                string: configuration.displayedTopicTitle,
                attributes: [.font: UIFont.preferredFont(forTextStyle: .headline), .foregroundColor: UIColor.label]
            )
            bodyNode.attributedText = status.isEmpty ? nil : NSAttributedString(
                string: status,
                attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: UIColor.secondaryLabel]
            )
        case .aiSummary:
            let title = "AI 摘要"
            let body: String
            if let summary = configuration.topicAiSummary {
                body = summary.summarizedText
            } else if configuration.isLoadingTopicAiSummary {
                body = "正在加载摘要..."
            } else {
                body = configuration.topicAiSummaryError ?? "加载失败"
            }
            titleNode.attributedText = NSAttributedString(
                string: title,
                attributes: [.font: UIFont.preferredFont(forTextStyle: .headline), .foregroundColor: UIColor.label]
            )
            bodyNode.attributedText = NSAttributedString(
                string: body,
                attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: UIColor.secondaryLabel]
            )
        case .notice:
            let statusMessage = item.statusMessage
            let title = statusMessage?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTitle = (title?.isEmpty == false) ? title : nil
            let messageColor = statusMessage?.emphasizesError == true
                ? UIColor.systemRed
                : UIColor.secondaryLabel
            bodyNode.attributedText = NSAttributedString(
                string: statusMessage?.message ?? "正在显示缓存内容",
                attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: messageColor]
            )
            if let trimmedTitle {
                titleNode.attributedText = NSAttributedString(
                    string: trimmedTitle,
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .headline),
                        .foregroundColor: statusMessage?.emphasizesError == true
                            ? UIColor.systemRed
                            : UIColor.label,
                    ]
                )
            }
        default:
            break
        }

        var children: [ASLayoutElement] = [
            titleNode.attributedText != nil ? titleNode : nil,
            bodyNode.attributedText != nil ? bodyNode : nil,
        ].compactMap { $0 }
        if item.kind == .notice, item.statusMessage?.retryable == true {
            let buttonNode = ASButtonNode()
            buttonNode.setTitle(
                "重试",
                with: UIFont.preferredFont(forTextStyle: .subheadline),
                with: FireTopicDetailRuntimeCellColors.accent,
                for: .normal
            )
            buttonNode.addTarget(self, action: #selector(handleLoadTopicDetail), forControlEvents: .touchUpInside)
            children.append(buttonNode)
        }

        node.layoutSpecBlock = { _, _ in
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 6,
                justifyContent: .start,
                alignItems: .stretch,
                children: children
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16),
                child: stack
            )
        }
        return node
    }

    private func makeMissingPostCellNode() -> ASCellNode {
        let node = ASCellNode()
        node.automaticallyManagesSubnodes = true
        node.backgroundColor = .systemBackground

        let textNode = ASTextNode()
        textNode.attributedText = NSAttributedString(
            string: "帖子内容加载中...",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )

        node.layoutSpecBlock = { _, _ in
            ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                child: textNode
            )
        }
        return node
    }

    // MARK: - Actions

    @objc private func handleToggleTopicVote() {
        guard let configuration else { return }
        Task { await configuration.onToggleTopicVote() }
    }

    @objc private func handleShowTopicVoters() {
        guard let configuration else { return }
        Task { await configuration.onShowTopicVoters() }
    }

    @objc private func handleLoadMoreReplies() {
        guard let configuration else { return }
        if let probe = currentLoadMoreProbe() {
            _ = attemptLoadMore(
                configuration: configuration,
                probe: probe,
                allowRetry: true,
                bypassRejectedProbeGuard: true
            )
        }
    }

    @objc private func handleLoadTopicDetail() {
        guard let configuration else { return }
        Task { await configuration.onLoadTopicDetail() }
    }

    // MARK: - Helpers

    private func postCallbacks(configuration: FireTopicDetailRuntimeConfiguration) -> FirePostCellCallbacks {
        FirePostCellCallbacks(
            onLinkTapped: configuration.onLinkTapped,
            onOpenImage: configuration.onOpenImage,
            onToggleLike: configuration.onToggleLike,
            onSelectReaction: configuration.onSelectReaction,
            onEditPost: configuration.onEditPost,
            onBookmarkPost: configuration.onBookmarkPost,
            onDeletePost: configuration.onDeletePost,
            onRecoverPost: configuration.onRecoverPost,
            onFlagPost: configuration.onFlagPost,
            onOpenReplyTarget: configuration.onOpenPostNumber,
            onOpenReplies: configuration.onOpenPostReplies,
            onExpandText: configuration.onExpandPostText,
            onVotePoll: configuration.onVotePoll,
            onUnvotePoll: configuration.onUnvotePoll,
            onSwipeReply: { post in
                configuration.onOpenComposer(post)
            }
        )
    }

    private func layoutContentWidth(proposedWidth: CGFloat? = nil) -> CGFloat {
        let adjustedBoundsWidth = collectionNode.view.bounds.width
            - collectionNode.view.adjustedContentInset.left
            - collectionNode.view.adjustedContentInset.right
        if adjustedBoundsWidth > 0 {
            return adjustedBoundsWidth
        }
        return max(proposedWidth ?? collectionNode.view.bounds.width, 1)
    }

    private func invalidateLayoutIfWidthChanged() {
        let width = layoutContentWidth()
        guard width > 1 else {
            return
        }
        if let lastLayoutContentWidth,
           abs(lastLayoutContentWidth - width) < 0.5 {
            return
        }
        let hadMeasuredWidth = lastLayoutContentWidth != nil
        lastLayoutContentWidth = width
        collectionNode.view.collectionViewLayout.invalidateLayout()
        if hadMeasuredWidth, !currentItems.isEmpty {
            collectionNode.reloadData()
        }
    }

    private func performRefresh() {
        guard let configuration else { return }
        Task { [weak self] in
            await configuration.onRefresh()
            await MainActor.run {
                self?.collectionNode.view.refreshControl?.endRefreshing()
            }
        }
    }

    private func applyCollectionUpdate(
        from previousItems: [FireTopicDetailRuntimeItem],
        to nextItems: [FireTopicDetailRuntimeItem]
    ) {
        let footerDistanceToViewport = replyFooterDistanceToViewport()
        var updatePlan = fireTopicDetailCollectionUpdatePlan(
            from: previousItems,
            to: nextItems
        )
        let shouldHoldLoadingFooter = fireTopicDetailShouldHoldLoadingFooter(
            previousFooterState: replyFooterState(in: previousItems),
            nextFooterState: replyFooterState(in: nextItems),
            itemCount: nextItems.count,
            visibleMaxItem: collectionNode.indexPathsForVisibleItems.map(\.item).max(),
            footerDistanceToViewport: footerDistanceToViewport
        )
        if shouldHoldLoadingFooter,
           let replyFooterIndexPath = replyFooterIndexPath(in: nextItems) {
            updatePlan = FireTopicDetailCollectionUpdatePlan(
                deletions: updatePlan.deletions,
                insertions: updatePlan.insertions,
                reloads: updatePlan.reloads.filter { $0 != replyFooterIndexPath }
            )
        }
        let inPlacePostRelayouts = fireTopicDetailVisiblePostRelayoutIndexPaths(
            reloads: updatePlan.reloads,
            nextItems: nextItems,
            visibleIndexPaths: Set(collectionNode.indexPathsForVisibleItems)
        )
        if !inPlacePostRelayouts.isEmpty {
            let relayoutSet = Set(inPlacePostRelayouts)
            updatePlan = FireTopicDetailCollectionUpdatePlan(
                deletions: updatePlan.deletions,
                insertions: updatePlan.insertions,
                reloads: updatePlan.reloads.filter { !relayoutSet.contains($0) }
            )
        }

        let completion = { [weak self] in
            guard let self else { return }
            if let configuration = self.configuration {
                self.applyVisiblePostRelayoutsIfNeeded(
                    at: inPlacePostRelayouts,
                    items: nextItems,
                    configuration: configuration
                )
            }
            self.handlePendingScrollTargetIfNeeded()
            self.scheduleDeferredRuntimeCallbacks(
                forceVisiblePostPublish: previousItems.isEmpty,
                forceLoadMoreEvaluation: true,
                shouldRetryLoadMoreRestoreFooter: shouldHoldLoadingFooter
            )
        }

        guard !updatePlan.isEmpty else {
            completion()
            return
        }

        let animated = Self.allowsAnimatedUpdate(
            isViewAttached: collectionNode.view.window != nil,
            isScrollInteractionActive: isScrollInteractionActive,
            hasCurrentItems: !previousItems.isEmpty,
            itemDelta: nextItems.count - previousItems.count
        )

        guard previousItems.isEmpty == false,
              collectionNode.view.window != nil,
              collectionNode.isProcessingUpdates == false else {
            collectionNode.reloadData(completion: {
                completion()
            })
            return
        }

        collectionNode.performBatch(animated: animated, updates: { [self] in
            if !updatePlan.deletions.isEmpty {
                collectionNode.deleteItems(at: updatePlan.deletions)
            }
            if !updatePlan.insertions.isEmpty {
                collectionNode.insertItems(at: updatePlan.insertions)
            }
            if !updatePlan.reloads.isEmpty {
                collectionNode.reloadItems(at: updatePlan.reloads)
            }
        }, completion: { _ in
            completion()
        })
    }

    private func handlePendingScrollTargetIfNeeded() {
        guard let configuration,
              let target = configuration.pendingScrollTarget,
              handledScrollTarget != target,
              let index = currentItems.firstIndex(where: { $0.postNumber == target }) else {
            return
        }
        handledScrollTarget = target
        collectionNode.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredVertically,
            animated: true
        )
        configuration.onScrollTargetHandled(target)
    }

    private func scheduleDeferredRuntimeCallbacks(
        preloadVisiblePostNumbers: Set<UInt32> = [],
        forceVisiblePostPublish: Bool = false,
        forceLoadMoreEvaluation: Bool = false,
        shouldRetryLoadMoreRestoreFooter: Bool = false
    ) {
        // SwiftUI calls updateUIViewController inside its view-update pass.
        // Defer any callback that can mutate ObservableObject state until the
        // next main-runloop turn so Texture/UI work never publishes mid-update.
        // Using Task instead of DispatchQueue.main.async ensures the work runs
        // after the current SwiftUI update pass completes.
        deferredRuntimeCallbacks.merge(
            preloadVisiblePostNumbers: preloadVisiblePostNumbers,
            forceVisiblePostPublish: forceVisiblePostPublish,
            forceLoadMoreEvaluation: forceLoadMoreEvaluation,
            shouldRetryLoadMoreRestoreFooter: shouldRetryLoadMoreRestoreFooter
        )
        guard deferredRuntimeCallbacks.hasWork,
              hasDeferredRuntimeCallbacksScheduled == false else {
            return
        }

        hasDeferredRuntimeCallbacksScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.hasDeferredRuntimeCallbacksScheduled = false
            let callbacks = self.deferredRuntimeCallbacks
            self.deferredRuntimeCallbacks = FireTopicDetailDeferredRuntimeCallbacks()

            guard let configuration = self.configuration else {
                return
            }

            if !callbacks.preloadVisiblePostNumbers.isEmpty {
                configuration.onPreloadTopicPosts(callbacks.preloadVisiblePostNumbers)
            }

            self.publishVisiblePostNumbersIfChanged(force: callbacks.forceVisiblePostPublish)
            let requestedMore = self.loadMoreIfNeeded(
                forceEvaluation: callbacks.forceLoadMoreEvaluation
            )
            if callbacks.shouldRetryLoadMoreRestoreFooter, !requestedMore {
                self.scheduleLoadMoreRetryOrRestoreFooter()
            }
        }
    }

    private func publishVisiblePostNumbersIfChanged(force: Bool = false) {
        let postNumbers = Set(collectionNode.indexPathsForVisibleItems.compactMap { indexPath -> UInt32? in
            guard indexPath.item < currentItems.count else { return nil }
            return currentItems[indexPath.item].postNumber
        })

        if force {
            visiblePostNumbersPublishTask?.cancel()
            visiblePostNumbersPublishTask = nil
            pendingVisiblePostNumbers = nil
            publishVisiblePostNumbersImmediately(postNumbers, force: true)
            return
        }

        guard postNumbers != lastPublishedVisiblePostNumbers else {
            pendingVisiblePostNumbers = nil
            visiblePostNumbersPublishTask?.cancel()
            visiblePostNumbersPublishTask = nil
            return
        }
        pendingVisiblePostNumbers = postNumbers
        guard visiblePostNumbersPublishTask == nil else {
            return
        }

        visiblePostNumbersPublishTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: fireTopicDetailVisiblePostPublishDebounce)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            let latestPostNumbers = self.pendingVisiblePostNumbers ?? postNumbers
            self.pendingVisiblePostNumbers = nil
            self.visiblePostNumbersPublishTask = nil
            self.publishVisiblePostNumbersImmediately(latestPostNumbers)
        }
    }

    private func publishVisiblePostNumbersImmediately(_ postNumbers: Set<UInt32>, force: Bool = false) {
        guard let configuration,
              force || postNumbers != lastPublishedVisiblePostNumbers else {
            return
        }
        lastPublishedVisiblePostNumbers = postNumbers
        configuration.onVisiblePostNumbersChanged(postNumbers)
    }

    private func replyFooterIndexPath(
        in items: [FireTopicDetailRuntimeItem]
    ) -> IndexPath? {
        guard let index = items.firstIndex(where: { $0.kind == .replyFooter }) else {
            return nil
        }
        return IndexPath(item: index, section: 0)
    }

    private func replyFooterDistanceToViewport() -> CGFloat? {
        guard let indexPath = replyFooterIndexPath(in: currentItems),
              let attributes = collectionNode.view.layoutAttributesForItem(at: indexPath) else {
            return nil
        }
        let visibleMaxY = collectionNode.view.contentOffset.y
            + collectionNode.view.bounds.height
            - collectionNode.view.adjustedContentInset.bottom
        return attributes.frame.minY - visibleMaxY
    }

    private func replyFooterState(
        in items: [FireTopicDetailRuntimeItem]
    ) -> FireTopicDetailRuntimeReplyFooterState? {
        guard let item = items.first(where: { $0.kind == .replyFooter }),
              let token = item.contentToken.base as? String else {
            return nil
        }
        switch token {
        case FireTopicDetailRuntimeReplyFooterState.loadMore.contentToken:
            return .loadMore
        case FireTopicDetailRuntimeReplyFooterState.loadingFooter.contentToken:
            return .loadingFooter
        case FireTopicDetailRuntimeReplyFooterState.empty.contentToken:
            return .empty
        case FireTopicDetailRuntimeReplyFooterState.none.contentToken:
            return FireTopicDetailRuntimeReplyFooterState.none
        default:
            return nil
        }
    }

    private func reloadReplyFooterIfNeeded() {
        guard let indexPath = replyFooterIndexPath(in: currentItems) else {
            return
        }
        if collectionNode.isProcessingUpdates {
            DispatchQueue.main.async { [weak self] in
                self?.reloadReplyFooterIfNeeded()
            }
            return
        }
        collectionNode.reloadItems(at: [indexPath])
    }

    @discardableResult
    private func loadMoreIfNeeded(forceEvaluation: Bool = false) -> Bool {
        guard let configuration,
              configuration.detail != nil,
              configuration.hasMoreTopicPosts,
              !configuration.isLoadingMoreTopicPosts else {
            loadMoreRetryTask?.cancel()
            loadMoreRetryTask = nil
            return false
        }
        guard let probe = currentLoadMoreProbe() else {
            return false
        }
        guard forceEvaluation || lastLoadMoreProbe != probe else {
            return false
        }
        if fireTopicDetailShouldLoadMore(
            itemCount: probe.itemCount,
            visibleMaxItem: probe.visibleMaxItem,
            footerDistanceToViewport: probe.footerDistanceBucket == nil
                ? nil
                : replyFooterDistanceToViewport()
        ) {
            return attemptLoadMore(
                configuration: configuration,
                probe: probe,
                allowRetry: true,
                bypassRejectedProbeGuard: forceEvaluation
            )
        }
        lastLoadMoreProbe = probe
        lastRejectedLoadMoreProbe = nil
        return false
    }

    private func currentLoadMoreProbe() -> FireTopicDetailLoadMoreProbe? {
        guard let configuration,
              configuration.detail != nil else {
            return nil
        }
        return fireTopicDetailLoadMoreProbe(
            itemCount: currentItems.count,
            visibleMaxItem: collectionNode.indexPathsForVisibleItems.map(\.item).max(),
            footerDistanceToViewport: replyFooterDistanceToViewport()
        )
    }

    @discardableResult
    private func attemptLoadMore(
        configuration: FireTopicDetailRuntimeConfiguration,
        probe: FireTopicDetailLoadMoreProbe,
        allowRetry: Bool,
        bypassRejectedProbeGuard: Bool
    ) -> Bool {
        if !bypassRejectedProbeGuard, lastRejectedLoadMoreProbe == probe {
            return false
        }
        if configuration.onLoadMoreTopicPosts() {
            lastLoadMoreProbe = probe
            lastRejectedLoadMoreProbe = nil
            loadMoreRetryTask?.cancel()
            loadMoreRetryTask = nil
            return true
        }

        lastLoadMoreProbe = probe
        lastRejectedLoadMoreProbe = probe
        if allowRetry {
            scheduleLoadMoreRetryOrRestoreFooter()
        }
        return false
    }

    private func triggerEmptyReplyFooterPreloadIfNeeded(configuration: FireTopicDetailRuntimeConfiguration) {
        guard configuration.replyFooterState == .loadingFooter,
              configuration.replyRows.isEmpty else {
            return
        }
        let preloadKey = AnyHashable([
            String(configuration.topic.id),
            String(configuration.topicCollectionRevision),
        ])
        guard lastEmptyReplyFooterPreloadKey != preloadKey else {
            return
        }
        lastEmptyReplyFooterPreloadKey = preloadKey
        let seedVisiblePostNumbers = configuration.originalPost.map { Set([$0.postNumber]) } ?? []
        scheduleDeferredRuntimeCallbacks(
            preloadVisiblePostNumbers: seedVisiblePostNumbers
        )
    }

    private func applyVisiblePostRelayoutsIfNeeded(
        at indexPaths: [IndexPath],
        items: [FireTopicDetailRuntimeItem],
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        guard !indexPaths.isEmpty else {
            return
        }

        for indexPath in indexPaths {
            guard indexPath.item >= 0,
                  indexPath.item < items.count,
                  let postContext = configuration.postContext(for: items[indexPath.item]),
                  let node = collectionNode.nodeForItem(at: indexPath) as? FirePostCellNode else {
                continue
            }
            configurePostCellNode(
                node,
                with: postContext,
                configuration: configuration
            )
            node.invalidateCalculatedLayout()
            node.setNeedsLayout()
        }
    }

    private func scheduleLoadMoreRetryOrRestoreFooter() {
        guard loadMoreRetryTask == nil else {
            return
        }
        loadMoreRetryTask?.cancel()
        loadMoreRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }
            self.loadMoreRetryTask = nil
            guard let configuration = self.configuration,
                  let probe = self.currentLoadMoreProbe() else {
                return
            }
            let accepted = self.attemptLoadMore(
                configuration: configuration,
                probe: probe,
                allowRetry: false,
                bypassRejectedProbeGuard: true
            )
            if !accepted {
                self.reloadReplyFooterIfNeeded()
            }
        }
    }
}
