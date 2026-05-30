import IGListKit
import SwiftUI
import UIKit

private let fireTopicDetailAnimatedUpdateItemDeltaLimit = 4

@MainActor
final class FireTopicDetailListViewController: UIViewController,
    ListAdapterDataSource,
    ListAdapterPerformanceDelegate,
    ListAdapterUpdateListener,
    UIScrollViewDelegate
{
    private var collectionView: UICollectionView!
    private lazy var adapter = ListAdapter(
        updater: ListAdapterUpdater(),
        viewController: self,
        workingRangeSize: 8
    )
    private var configuration: FireTopicDetailRuntimeConfiguration?
    private var currentItems: [FireTopicDetailRuntimeItem] = []
    private var currentObjects: [FireTopicDetailListObject] = []
    private var layoutCache: [FirePostCellLayoutKey: FirePostCellLayout] = [:]
    private var hostedHeightCache: [FireTopicDetailHostedHeightKey: CGFloat] = [:]
    private var handledScrollTarget: UInt32?
    private var lastPublishedVisiblePostNumbers: Set<UInt32> = []
    private var lastLoadMoreProbe: (itemCount: Int, visibleMaxSection: Int)?
    private let imagePrefetchCoordinator = FireTopicImagePrefetchCoordinator()

    override func loadView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.estimatedItemSize = .zero

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        adapter.collectionView = collectionView
        adapter.dataSource = self
        adapter.performanceDelegate = self
        adapter.scrollViewDelegate = self
        adapter.add(self)

        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.performRefresh()
        }, for: .valueChanged)
        collectionView.refreshControl = refreshControl
    }

    func update(configuration: FireTopicDetailRuntimeConfiguration) {
        self.configuration = configuration

        let runtimeSnapshot = configuration.makeSnapshot()
        guard !Self.itemsHaveSameRenderedContent(runtimeSnapshot.items, currentItems) else {
            handlePendingScrollTargetIfNeeded()
            publishVisiblePostNumbersIfChanged()
            return
        }

        let animated = shouldAnimateUpdate(to: runtimeSnapshot.items)
        currentItems = runtimeSnapshot.items
        currentObjects = runtimeSnapshot.items.map(FireTopicDetailListObject.init(item:))
        lastLoadMoreProbe = nil

        adapter.performUpdates(animated: animated) { [weak self] _ in
            guard let self else { return }
            self.publishVisiblePostNumbersIfChanged()
            self.handlePendingScrollTargetIfNeeded()
        }
    }

    nonisolated static func itemsHaveSameRenderedContent(
        _ lhs: [FireTopicDetailRuntimeItem],
        _ rhs: [FireTopicDetailRuntimeItem]
    ) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { $0.hasSameRenderedContent(as: $1) }
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

    private func shouldAnimateUpdate(to items: [FireTopicDetailRuntimeItem]) -> Bool {
        Self.allowsAnimatedUpdate(
            isViewAttached: collectionView.window != nil,
            isScrollInteractionActive: collectionView.isDragging
                || collectionView.isDecelerating
                || collectionView.isTracking,
            hasCurrentItems: !currentItems.isEmpty,
            itemDelta: abs(items.count - currentItems.count)
        )
    }

    // MARK: - ListAdapterDataSource

    func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        currentObjects
    }

    func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        FireTopicDetailItemSectionController(owner: self)
    }

    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        nil
    }

    // MARK: - ListAdapterUpdateListener

    func listAdapter(_ listAdapter: ListAdapter, didFinish update: IGListAdapterUpdateType, animated: Bool) {
        publishVisiblePostNumbersIfChanged(force: true)
    }

    // MARK: - ListAdapterPerformanceDelegate

    nonisolated func listAdapterWillCallDequeueCell(_ listAdapter: ListAdapter) {}

    nonisolated func listAdapter(
        _ listAdapter: ListAdapter,
        didCallDequeue cell: UICollectionViewCell,
        on sectionController: ListSectionController,
        at index: Int
    ) {}

    nonisolated func listAdapterWillCallDisplayCell(_ listAdapter: ListAdapter) {}

    nonisolated func listAdapter(
        _ listAdapter: ListAdapter,
        didCallDisplay cell: UICollectionViewCell,
        on sectionController: ListSectionController,
        at index: Int
    ) {}

    nonisolated func listAdapterWillCallEndDisplayCell(_ listAdapter: ListAdapter) {}

    nonisolated func listAdapter(
        _ listAdapter: ListAdapter,
        didCallEndDisplay cell: UICollectionViewCell,
        on sectionController: ListSectionController,
        at index: Int
    ) {}

    nonisolated func listAdapterWillCallSize(_ listAdapter: ListAdapter) {}

    nonisolated func listAdapter(
        _ listAdapter: ListAdapter,
        didCallSizeOn sectionController: ListSectionController,
        at index: Int
    ) {}

    nonisolated func listAdapterWillCallScroll(_ listAdapter: ListAdapter) {}

    nonisolated func listAdapter(_ listAdapter: ListAdapter, didCallScroll scrollView: UIScrollView) {}

    // MARK: - Cells

    fileprivate func cell(
        collectionContext: ListCollectionContext,
        sectionController: ListSectionController,
        item: FireTopicDetailRuntimeItem,
        index: Int
    ) -> UICollectionViewCell {
        guard let configuration else {
            return collectionContext.dequeueReusableCell(
                of: FireTopicDetailTextCell.self,
                for: sectionController,
                at: index
            )
        }

        if shouldUseHostedCell(for: item, configuration: configuration) {
            let cell = collectionContext.dequeueReusableCell(
                of: FireTopicDetailHostingCell.self,
                for: sectionController,
                at: index
            ) as! FireTopicDetailHostingCell
            cell.configure(configuration: configuration, item: item)
            return cell
        }

        if let postContext = configuration.postContext(for: item),
           let layout = layout(for: postContext, item: item, containerWidth: collectionContext.containerSize.width) {
            let cell = collectionContext.dequeueReusableCell(
                of: FirePostTextureCell.self,
                for: sectionController,
                at: index
            ) as! FirePostTextureCell
            cell.bind(
                layout: layout,
                payload: FirePostCellRenderPayload(
                    post: postContext.post,
                    renderContent: postContext.renderContent,
                    baseURLString: configuration.baseURLString,
                    canWriteInteractions: configuration.canWriteInteractions,
                    isMutating: configuration.isMutatingPost(postContext.post.id),
                    replyContext: postContext.replyContext,
                    replyTargetPostNumber: postContext.replyTargetPostNumber,
                    showsDivider: postContext.showsDivider
                ),
                callbacks: postCallbacks(configuration: configuration)
            )
            return cell
        }

        switch item.kind {
        case .replyFooter:
            let cell = collectionContext.dequeueReusableCell(
                of: FireTopicDetailActionCell.self,
                for: sectionController,
                at: index
            ) as! FireTopicDetailActionCell
            let title = configuration.isLoadingMoreTopicPosts ? "正在加载更多回复..." : "加载更多回复"
            cell.configure(title: title) {
                configuration.onLoadMoreTopicPosts()
            }
            return cell

        case .bodyState:
            let cell = collectionContext.dequeueReusableCell(
                of: FireTopicDetailActionCell.self,
                for: sectionController,
                at: index
            ) as! FireTopicDetailActionCell
            let title = configuration.isLoadingTopic ? "正在加载话题..." : (configuration.detailError ?? "重新加载")
            cell.configure(title: title) {
                Task {
                    await configuration.onLoadTopicDetail()
                }
            }
            return cell

        default:
            let cell = collectionContext.dequeueReusableCell(
                of: FireTopicDetailTextCell.self,
                for: sectionController,
                at: index
            ) as! FireTopicDetailTextCell
            configureTextCell(cell, item: item, configuration: configuration)
            return cell
        }
    }

    fileprivate func size(
        for item: FireTopicDetailRuntimeItem,
        collectionContext: ListCollectionContext?
    ) -> CGSize {
        let width = collectionContext?.containerSize.width ?? collectionView.bounds.width
        if let configuration, shouldUseHostedCell(for: item, configuration: configuration) {
            return CGSize(
                width: width,
                height: hostedRowHeight(for: item, configuration: configuration, width: width)
            )
        }
        if let configuration,
           let context = configuration.postContext(for: item),
           let layout = layout(for: context, item: item, containerWidth: width) {
            return CGSize(width: width, height: layout.totalHeight)
        }
        return CGSize(width: width, height: estimatedHeight(for: item))
    }

    private func configureTextCell(
        _ cell: FireTopicDetailTextCell,
        item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration
    ) {
        switch item.kind {
        case .header:
            let status = configuration.row.statusLabels.joined(separator: " · ")
            cell.configure(
                title: configuration.displayedTopicTitle,
                body: status.isEmpty ? nil : status
            )
        case .aiSummary:
            if let summary = configuration.topicAiSummary {
                cell.configure(title: "AI 摘要", body: summary.summarizedText)
            } else if configuration.isLoadingTopicAiSummary {
                cell.configure(title: "AI 摘要", body: "正在加载摘要...")
            } else {
                cell.configure(title: "AI 摘要", body: configuration.topicAiSummaryError ?? "加载失败")
            }
        case .stats:
            cell.configure(
                title: nil,
                body: "\(configuration.displayedReplyCount) 回复 · \(configuration.displayedViewsCount) 浏览"
            )
        case .repliesHeader:
            cell.configure(title: "回复", body: "\(configuration.replyRows.count) / \(max(Int(configuration.displayedReplyCount), 0))")
        case .notice:
            cell.configure(title: nil, body: "正在显示缓存内容")
        default:
            cell.configure(title: nil, body: nil)
        }
    }

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
            onVotePoll: configuration.onVotePoll,
            onUnvotePoll: configuration.onUnvotePoll,
            onSwipeReply: { post in
                configuration.onOpenComposer(post)
            }
        )
    }

    private func shouldUseHostedCell(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> Bool {
        switch item.kind {
        case .header, .aiSummary, .stats, .topicVote, .repliesHeader, .bodyState, .replyFooter, .notice:
            return true
        case .originalPost:
            return true
        case .reply:
            return configuration.postContext(for: item)?.post.polls.isEmpty == false
        }
    }

    private func hostedRowHeight(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration,
        width: CGFloat
    ) -> CGFloat {
        let resolvedWidth = max(width, 1)
        let key = FireTopicDetailHostedHeightKey(
            itemID: item.id,
            contentToken: item.contentToken,
            widthPixels: Int(resolvedWidth.rounded(.up)),
            contentSizeCategory: traitCollection.preferredContentSizeCategory.rawValue,
            userInterfaceStyle: traitCollection.userInterfaceStyle.rawValue
        )
        if let cached = hostedHeightCache[key] {
            return cached
        }

        let colorScheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        let controller = UIHostingController(
            rootView: FireTopicDetailHostedRow(configuration: configuration, item: item)
                .environment(\.colorScheme, colorScheme)
        )
        controller.view.backgroundColor = .clear
        let measuredSize = controller.sizeThatFits(
            in: CGSize(width: resolvedWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        let height = ceil(max(measuredSize.height, estimatedHeight(for: item)))
        hostedHeightCache[key] = height
        return height
    }

    private func layout(
        for context: FireTopicDetailRuntimePostContext,
        item: FireTopicDetailRuntimeItem,
        containerWidth: CGFloat
    ) -> FirePostCellLayout? {
        let width = containerWidth - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right
        guard width > 0 else { return nil }
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: Int(width.rounded()),
            contentSizeCategory: traitCollection.preferredContentSizeCategory.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: context.post.id,
            depth: context.depth,
            showsThreadLine: context.showsThreadLine,
            showsDivider: context.showsDivider,
            replyTargetPostNumber: context.replyTargetPostNumber,
            replyContext: context.replyContext,
            textContentID: "post:\(context.post.id)|render:\(context.renderContent.signature.token)",
            imageSignature: context.renderContent.imageAttachments.map(\.id),
            pollSignature: context.post.polls.map { UInt64(bitPattern: Int64($0.name.hashValue)) },
            hasReactions: !context.post.reactions.isEmpty,
            acceptedAnswer: context.post.acceptedAnswer,
            trait: trait
        )
        if let cached = layoutCache[key] {
            return cached
        }
        let availableWidth = FirePostCellLayoutCalculator.availableContentWidth(for: key, trait: trait)
        let textHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: context.renderContent.attributedText,
            containerWidth: availableWidth,
            contentSizeCategory: traitCollection.preferredContentSizeCategory
        )
        let imageHeights = context.renderContent.imageAttachments.map {
            FirePostCellLayoutCalculator.imageHeight(for: $0, availableWidth: availableWidth)
        }
        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: textHeight,
            imageHeights: imageHeights,
            trait: trait
        )
        layoutCache[key] = layout
        _ = item
        return layout
    }

    // MARK: - Refresh and Scrolling

    private func performRefresh() {
        guard let configuration else { return }
        Task { [weak self] in
            await configuration.onRefresh()
            await MainActor.run {
                self?.collectionView.refreshControl?.endRefreshing()
            }
        }
    }

    private func handlePendingScrollTargetIfNeeded() {
        guard let configuration,
              let target = configuration.pendingScrollTarget,
              handledScrollTarget != target,
              let section = currentItems.firstIndex(where: { $0.postNumber == target }) else {
            return
        }
        handledScrollTarget = target
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: section),
            at: .centeredVertically,
            animated: true
        )
        configuration.onScrollTargetHandled(target)
    }

    private func publishVisiblePostNumbersIfChanged(force: Bool = false) {
        guard let configuration else { return }
        let postNumbers = Set(collectionView.indexPathsForVisibleItems.compactMap { indexPath -> UInt32? in
            guard indexPath.section < currentItems.count else { return nil }
            return currentItems[indexPath.section].postNumber
        })
        guard force || postNumbers != lastPublishedVisiblePostNumbers else {
            return
        }
        lastPublishedVisiblePostNumbers = postNumbers
        configuration.onVisiblePostNumbersChanged(postNumbers)
    }

    private func loadMoreIfNeeded() {
        guard let configuration,
              configuration.detail != nil,
              configuration.hasMoreTopicPosts,
              !configuration.isLoadingMoreTopicPosts else {
            return
        }
        let visibleMaxSection = collectionView.indexPathsForVisibleItems.map(\.section).max() ?? 0
        let probe = (itemCount: currentItems.count, visibleMaxSection: visibleMaxSection)
        guard lastLoadMoreProbe?.itemCount != probe.itemCount
            || lastLoadMoreProbe?.visibleMaxSection != probe.visibleMaxSection else {
            return
        }
        lastLoadMoreProbe = probe
        if currentItems.count - visibleMaxSection <= 8 {
            configuration.onLoadMoreTopicPosts()
        }
    }

    fileprivate func prefetch(items: [FireTopicDetailRuntimeItem]) {
        guard let configuration else { return }
        let postNumbers = Set(items.compactMap(\.postNumber))
        if !postNumbers.isEmpty {
            configuration.onPreloadTopicPosts(postNumbers)
        }

        var requests: [FireTopicImagePrefetchKey] = []
        for item in items {
            guard let context = configuration.postContext(for: item) else { continue }
            if let avatar = FireTopicImageRequestBuilder.avatarRequest(
                avatarTemplate: context.post.avatarTemplate,
                username: context.post.username,
                depth: context.depth,
                baseURLString: configuration.baseURLString
            ) {
                requests.append(FireTopicImagePrefetchKey(ownerID: item.id, request: avatar))
            }
            if let firstImage = context.renderContent.imageAttachments.first {
                requests.append(FireTopicImagePrefetchKey(
                    ownerID: item.id,
                    request: FireTopicImageRequestBuilder.cookedImageRequest(firstImage)
                ))
            }
        }
        imagePrefetchCoordinator.prefetch(requests)
    }

    fileprivate func cancelPrefetch(for item: FireTopicDetailRuntimeItem) {
        imagePrefetchCoordinator.cancel(ownerID: item.id)
    }

    private func estimatedHeight(for item: FireTopicDetailRuntimeItem) -> CGFloat {
        switch item.kind {
        case .header: 74
        case .aiSummary: 96
        case .topicVote: 96
        case .originalPost: 44
        case .stats, .repliesHeader, .replyFooter, .bodyState, .notice: 48
        default: 44
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        publishVisiblePostNumbersIfChanged()
        loadMoreIfNeeded()
    }
}

private struct FireTopicDetailHostedHeightKey: Hashable {
    let itemID: String
    let contentToken: AnyHashable
    let widthPixels: Int
    let contentSizeCategory: String
    let userInterfaceStyle: Int
}

private final class FireTopicDetailListObject: NSObject, ListDiffable {
    let item: FireTopicDetailRuntimeItem

    init(item: FireTopicDetailRuntimeItem) {
        self.item = item
    }

    func diffIdentifier() -> NSObjectProtocol {
        item.id as NSString
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let other = object as? FireTopicDetailListObject else {
            return false
        }
        return item.id == other.item.id
            && item.kind == other.item.kind
            && item.postID == other.item.postID
            && item.postNumber == other.item.postNumber
            && item.replyIndex == other.item.replyIndex
            && item.contentToken == other.item.contentToken
    }
}

private final class FireTopicDetailItemSectionController: ListSectionController,
    ListWorkingRangeDelegate,
    ListDisplayDelegate
{
    private weak var owner: FireTopicDetailListViewController?
    private var object: FireTopicDetailListObject?

    init(owner: FireTopicDetailListViewController) {
        self.owner = owner
        super.init()
        workingRangeDelegate = self
        displayDelegate = self
    }

    override func numberOfItems() -> Int {
        1
    }

    override func sizeForItem(at index: Int) -> CGSize {
        guard let item = object?.item else {
            return CGSize(width: collectionContext?.containerSize.width ?? 0, height: 44)
        }
        return owner?.size(for: item, collectionContext: collectionContext)
            ?? CGSize(width: collectionContext?.containerSize.width ?? 0, height: 44)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let item = object?.item, let collectionContext else {
            return UICollectionViewCell()
        }
        return owner?.cell(
            collectionContext: collectionContext,
            sectionController: self,
            item: item,
            index: index
        ) ?? UICollectionViewCell()
    }

    override func didUpdate(to object: Any) {
        self.object = object as? FireTopicDetailListObject
    }

    func listAdapter(
        _ listAdapter: ListAdapter,
        sectionControllerWillEnterWorkingRange sectionController: ListSectionController
    ) {
        guard let item = object?.item else { return }
        owner?.prefetch(items: [item])
    }

    func listAdapter(
        _ listAdapter: ListAdapter,
        sectionControllerDidExitWorkingRange sectionController: ListSectionController
    ) {
        guard let item = object?.item else { return }
        owner?.cancelPrefetch(for: item)
    }

    func listAdapter(_ listAdapter: ListAdapter, willDisplay sectionController: ListSectionController) {}

    func listAdapter(_ listAdapter: ListAdapter, didEndDisplaying sectionController: ListSectionController) {
        guard let item = object?.item else { return }
        owner?.cancelPrefetch(for: item)
    }

    func listAdapter(
        _ listAdapter: ListAdapter,
        willDisplay sectionController: ListSectionController,
        cell: UICollectionViewCell,
        at index: Int
    ) {}

    func listAdapter(
        _ listAdapter: ListAdapter,
        didEndDisplaying sectionController: ListSectionController,
        cell: UICollectionViewCell,
        at index: Int
    ) {
        guard let item = object?.item else { return }
        owner?.cancelPrefetch(for: item)
    }
}
