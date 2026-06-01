import AsyncDisplayKit
import SwiftUI
import UIKit

private let fireTopicDetailAnimatedUpdateItemDeltaLimit = 4
private let fireTopicDetailVisiblePostPublishDebounce = Duration.milliseconds(240)

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
    private var lastLoadMoreProbe: (itemCount: Int, visibleMaxSection: Int)?
    private var layoutInvalidationTask: Task<Void, Never>?
    private var visiblePostNumbersPublishTask: Task<Void, Never>?
    private var pendingVisiblePostNumbers: Set<UInt32>?
    private var lastEmptyReplyFooterPreloadKey: AnyHashable?
    private var hostedHeightCache: [FireTopicDetailHostedHeightKey: CGFloat] = [:]

    deinit {
        layoutInvalidationTask?.cancel()
        visiblePostNumbersPublishTask?.cancel()
    }

    private static func makeCollectionLayout() -> UICollectionViewFlowLayout {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.estimatedItemSize = .zero
        return flowLayout
    }

    override func loadView() {
        collectionNode.backgroundColor = .systemBackground
        collectionNode.view.backgroundColor = .systemBackground
        collectionNode.view.alwaysBounceVertical = true
        collectionNode.view.delaysContentTouches = false
        collectionNode.view.keyboardDismissMode = .interactive
        view = collectionNode.view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionNode.dataSource = self
        collectionNode.delegate = self

        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.performRefresh()
        }, for: .valueChanged)
        collectionNode.view.refreshControl = refreshControl
    }

    func update(configuration: FireTopicDetailRuntimeConfiguration) {
        let previousInvalidationToken = self.configuration?.snapshotInvalidationToken
        self.configuration = configuration

        if Self.canReuseCurrentSnapshot(
            previousInvalidationToken: previousInvalidationToken,
            nextInvalidationToken: configuration.snapshotInvalidationToken,
            hasCurrentItems: !currentItems.isEmpty
        ) {
            handlePendingScrollTargetIfNeeded()
            publishVisiblePostNumbersIfChanged()
            return
        }

        let runtimeSnapshot = configuration.makeSnapshot()
        guard !Self.itemsHaveSameRenderedContent(runtimeSnapshot.items, currentItems) else {
            handlePendingScrollTargetIfNeeded()
            publishVisiblePostNumbersIfChanged()
            return
        }

        currentItems = runtimeSnapshot.items
        lastLoadMoreProbe = nil

        collectionNode.reloadData()
        handlePendingScrollTargetIfNeeded()
        publishVisiblePostNumbersIfChanged(force: true)
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
        context.completeBatchFetching(true)
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
        if shouldUseHostedCell(for: item, configuration: configuration) {
            return makeHostedCellNode(for: item, configuration: configuration)
        }

        if let postContext = configuration.postContext(for: item) {
            return makePostCellNode(for: postContext, configuration: configuration)
        }

        switch item.kind {
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
        default:
            return makeTextCellNode(for: item, configuration: configuration)
        }
    }

    private func makePostCellNode(
        for context: FireTopicDetailRuntimePostContext,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> ASCellNode {
        let node = FirePostCellNode()
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
        return node
    }

    private func makeHostedCellNode(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> ASCellNode {
        let colorScheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        let hostedView = FireTopicDetailHostedRow(configuration: configuration, item: item)
            .environment(\.colorScheme, colorScheme)
        let hostingController = UIHostingController(rootView: hostedView)
        hostingController.view.backgroundColor = .clear

        let width = layoutContentWidth()
        let measuredSize = hostingController.sizeThatFits(
            in: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)
        )
        hostingController.view.frame = CGRect(
            origin: .zero,
            size: CGSize(width: max(width, 1), height: ceil(measuredSize.height))
        )

        let cellNode = ASCellNode(viewControllerBlock: {
            hostingController
        }, didLoad: nil)
        cellNode.style.preferredSize = CGSize(width: max(width, 1), height: ceil(measuredSize.height))
        return cellNode
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
                spacing: 20,
                justifyContent: .start,
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
            childElement = label
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
            bodyNode.attributedText = NSAttributedString(
                string: "正在显示缓存内容",
                attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: UIColor.secondaryLabel]
            )
        default:
            break
        }

        let children: [ASLayoutElement] = [
            titleNode.attributedText != nil ? titleNode : nil,
            bodyNode.attributedText != nil ? bodyNode : nil,
        ].compactMap { $0 }

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
        configuration?.onLoadMoreTopicPosts()
    }

    @objc private func handleLoadTopicDetail() {
        guard let configuration else { return }
        Task { await configuration.onLoadTopicDetail() }
    }

    // MARK: - Helpers

    private func shouldUseHostedCell(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> Bool {
        switch item.kind {
        case .header, .aiSummary:
            return true
        case .stats, .topicVote, .repliesHeader, .bodyState, .replyFooter, .notice, .originalPost, .reply:
            return false
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

    private func performRefresh() {
        guard let configuration else { return }
        Task { [weak self] in
            await configuration.onRefresh()
            await MainActor.run {
                self?.collectionNode.view.refreshControl?.endRefreshing()
            }
        }
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

    private func loadMoreIfNeeded() {
        guard let configuration,
              configuration.detail != nil,
              configuration.hasMoreTopicPosts,
              !configuration.isLoadingMoreTopicPosts else {
            return
        }
        let visibleMaxItem = collectionNode.indexPathsForVisibleItems.map(\.item).max() ?? 0
        let probe = (itemCount: currentItems.count, visibleMaxSection: visibleMaxItem)
        guard lastLoadMoreProbe?.itemCount != probe.itemCount
            || lastLoadMoreProbe?.visibleMaxSection != probe.visibleMaxSection else {
            return
        }
        lastLoadMoreProbe = probe
        if currentItems.count - visibleMaxItem <= 8 {
            configuration.onLoadMoreTopicPosts()
        }
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
        configuration.onPreloadTopicPosts(seedVisiblePostNumbers)
    }
}

private struct FireTopicDetailHostedHeightKey: Hashable {
    let itemID: String
    let contentToken: AnyHashable
    let widthPixels: Int
    let contentSizeCategory: String
    let userInterfaceStyle: Int
}
