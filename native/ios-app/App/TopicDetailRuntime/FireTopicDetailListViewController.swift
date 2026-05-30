import UIKit

@MainActor
final class FireTopicDetailListViewController: UIViewController,
    UICollectionViewDelegateFlowLayout,
    UICollectionViewDataSourcePrefetching
{
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<FireTopicDetailRuntimeSection, FireTopicDetailRuntimeItem>!
    private var configuration: FireTopicDetailRuntimeConfiguration?
    private var currentItems: [FireTopicDetailRuntimeItem] = []
    private var currentTokens: [String: AnyHashable] = [:]
    private var layoutCache: [FirePostCellLayoutKey: FirePostCellLayout] = [:]
    private var handledScrollTarget: UInt32?
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
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(
            FirePostTextureCell.self,
            forCellWithReuseIdentifier: FirePostTextureCell.reuseID
        )
        collectionView.register(
            FireTopicDetailTextCell.self,
            forCellWithReuseIdentifier: FireTopicDetailTextCell.reuseID
        )
        collectionView.register(
            FireTopicDetailActionCell.self,
            forCellWithReuseIdentifier: FireTopicDetailActionCell.reuseID
        )
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureDataSource()

        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.performRefresh()
        }, for: .valueChanged)
        collectionView.refreshControl = refreshControl
    }

    func update(configuration: FireTopicDetailRuntimeConfiguration) {
        self.configuration = configuration
        applySnapshot(animated: true)
        handlePendingScrollTargetIfNeeded()
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else {
                return UICollectionViewCell()
            }
            return self.cell(collectionView: collectionView, indexPath: indexPath, item: item)
        }
    }

    private func applySnapshot(animated: Bool) {
        guard let configuration else { return }
        let runtimeSnapshot = configuration.makeSnapshot()
        let previousTokens = currentTokens
        currentItems = runtimeSnapshot.items
        currentTokens = Dictionary(uniqueKeysWithValues: currentItems.map { ($0.id, $0.contentToken) })

        var snapshot = NSDiffableDataSourceSnapshot<FireTopicDetailRuntimeSection, FireTopicDetailRuntimeItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(currentItems, toSection: .main)

        let changedItems = currentItems.filter { previousTokens[$0.id] != nil && previousTokens[$0.id] != $0.contentToken }
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }
            if #available(iOS 15.0, *), !changedItems.isEmpty {
                var reconfigureSnapshot = self.dataSource.snapshot()
                reconfigureSnapshot.reconfigureItems(changedItems)
                self.dataSource.apply(reconfigureSnapshot, animatingDifferences: false)
            }
            self.publishVisiblePostNumbers()
        }
    }

    private func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireTopicDetailRuntimeItem
    ) -> UICollectionViewCell {
        guard let configuration else {
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: FireTopicDetailTextCell.reuseID,
                for: indexPath
            )
        }

        if let postContext = configuration.postContext(for: item),
           let layout = layout(for: postContext, item: item) {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FirePostTextureCell.reuseID,
                for: indexPath
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
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FireTopicDetailActionCell.reuseID,
                for: indexPath
            ) as! FireTopicDetailActionCell
            let title = configuration.isLoadingMoreTopicPosts ? "正在加载更多回复…" : "加载更多回复"
            cell.configure(title: title) {
                configuration.onLoadMoreTopicPosts()
            }
            return cell

        case .bodyState:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FireTopicDetailActionCell.reuseID,
                for: indexPath
            ) as! FireTopicDetailActionCell
            let title = configuration.isLoadingTopic ? "正在加载话题…" : (configuration.detailError ?? "重新加载")
            cell.configure(title: title) {
                Task {
                    await configuration.onLoadTopicDetail()
                }
            }
            return cell

        default:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FireTopicDetailTextCell.reuseID,
                for: indexPath
            ) as! FireTopicDetailTextCell
            configureTextCell(cell, item: item, configuration: configuration)
            return cell
        }
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
                cell.configure(title: "AI 摘要", body: "正在加载摘要…")
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

    private func layout(
        for context: FireTopicDetailRuntimePostContext,
        item: FireTopicDetailRuntimeItem
    ) -> FirePostCellLayout? {
        let width = collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right
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
            textContentID: "post:\(context.post.id)|\(context.post.cooked.hashValue)|\(context.renderContent.imageAttachments.count)",
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
              let item = configuration.scrollItem(for: target),
              let index = currentItems.firstIndex(of: item) else {
            return
        }
        handledScrollTarget = target
        collectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredVertically,
            animated: true
        )
        configuration.onScrollTargetHandled(target)
    }

    private func publishVisiblePostNumbers() {
        guard let configuration else { return }
        let postNumbers = Set(collectionView.indexPathsForVisibleItems.compactMap { indexPath -> UInt32? in
            guard indexPath.item < currentItems.count else { return nil }
            return currentItems[indexPath.item].postNumber
        })
        configuration.onVisiblePostNumbersChanged(postNumbers)
    }

    private func loadMoreIfNeeded() {
        guard let configuration,
              configuration.detail != nil,
              configuration.hasMoreTopicPosts,
              !configuration.isLoadingMoreTopicPosts else {
            return
        }
        let visibleMaxIndex = collectionView.indexPathsForVisibleItems.map(\.item).max() ?? 0
        if currentItems.count - visibleMaxIndex <= 8 {
            configuration.onLoadMoreTopicPosts()
        }
    }

    private func prefetch(items: [FireTopicDetailRuntimeItem]) {
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

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard indexPath.item < currentItems.count else {
            return CGSize(width: collectionView.bounds.width, height: 44)
        }
        let item = currentItems[indexPath.item]
        if let configuration,
           let context = configuration.postContext(for: item),
           let layout = layout(for: context, item: item) {
            return CGSize(width: collectionView.bounds.width, height: layout.totalHeight)
        }
        return CGSize(width: collectionView.bounds.width, height: estimatedHeight(for: item))
    }

    private func estimatedHeight(for item: FireTopicDetailRuntimeItem) -> CGFloat {
        switch item.kind {
        case .header: 74
        case .aiSummary: 96
        case .stats, .repliesHeader, .replyFooter, .bodyState, .notice: 48
        default: 44
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        publishVisiblePostNumbers()
        loadMoreIfNeeded()
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        prefetch(items: indexPaths.compactMap { indexPath in
            guard indexPath.item < currentItems.count else { return nil }
            return currentItems[indexPath.item]
        })
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths where indexPath.item < currentItems.count {
            imagePrefetchCoordinator.cancel(ownerID: currentItems[indexPath.item].id)
        }
    }
}
