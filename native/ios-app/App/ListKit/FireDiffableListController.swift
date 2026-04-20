import SwiftUI
import UIKit

struct FireCollectionScrollMetrics: Equatable {
    let remainingDistanceToBottom: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
}

struct FireCollectionScrollAnchor<ItemID: Hashable>: Equatable {
    let itemID: ItemID
    let offsetFromTop: CGFloat
}

struct FireCollectionScrollRequest<ItemID: Hashable>: Equatable {
    let requestID: AnyHashable
    let itemID: ItemID
    let animated: Bool

    init(itemID: ItemID, animated: Bool = true, requestID: AnyHashable? = nil) {
        self.requestID = requestID ?? AnyHashable(itemID)
        self.itemID = itemID
        self.animated = animated
    }
}

enum FireCollectionScrollAnchorRestorePolicy {
    case always
    case never
    case whenNotAnimatingDifferences

    func shouldRestore(animatingDifferences: Bool) -> Bool {
        switch self {
        case .always:
            return true
        case .never:
            return false
        case .whenNotAnimatingDifferences:
            return !animatingDifferences
        }
    }
}

func fireCollectionNeedsLayoutUpdate(
    currentVersion: AnyHashable?,
    incomingVersion: AnyHashable
) -> Bool {
    currentVersion != incomingVersion
}

func fireCollectionNeedsSectionUpdate<SectionID: Hashable, ItemID: Hashable>(
    current: [FireListSectionModel<SectionID, ItemID>],
    incoming: [FireListSectionModel<SectionID, ItemID>]
) -> Bool {
    current != incoming
}

func fireCollectionCommonItems<SectionID: Hashable, ItemID: Hashable>(
    current: [FireListSectionModel<SectionID, ItemID>],
    incoming: [FireListSectionModel<SectionID, ItemID>]
) -> [ItemID] {
    let existingItems = Set(current.flatMap(\.items))
    return incoming
        .flatMap(\.items)
        .filter { existingItems.contains($0) }
}

func fireCollectionChangedItems<SectionID: Hashable, ItemID: Hashable>(
    current: [FireListSectionModel<SectionID, ItemID>],
    incoming: [FireListSectionModel<SectionID, ItemID>],
    previousTokens: [ItemID: AnyHashable],
    currentTokens: [ItemID: AnyHashable]
) -> [ItemID] {
    let existingItems = Set(current.flatMap(\.items))
    return incoming
        .flatMap(\.items)
        .filter { item in
            existingItems.contains(item) && previousTokens[item] != currentTokens[item]
        }
}

func fireCollectionScrollRequestDidChange<ItemID: Hashable>(
    current: FireCollectionScrollRequest<ItemID>?,
    incoming: FireCollectionScrollRequest<ItemID>?
) -> Bool {
    current?.requestID != incoming?.requestID
}

func fireCollectionNeedsScrollRequest<ItemID: Hashable>(
    handledRequestID: AnyHashable?,
    incoming: FireCollectionScrollRequest<ItemID>?
) -> Bool {
    guard let incoming else { return false }
    return handledRequestID != incoming.requestID
}

@MainActor
final class FireDiffableListController<SectionID: Hashable, ItemID: Hashable, RowContent: View>: UIViewController,
    UICollectionViewDelegate
{
    private var rowContent: (ItemID) -> RowContent
    private let onSelectItem: ((ItemID) -> Void)?
    private let canSelectItem: ((ItemID) -> Bool)?
    private let onVisibleItemsChanged: (([ItemID]) -> Void)?
    private let onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)?
    private let onRefresh: (() async -> Void)?
    private let scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy
    private var onScrollRequestCompleted: ((ItemID) -> Void)?
    private var listLayout: UICollectionViewLayout
    private var layoutVersion: AnyHashable
    private var contentVersion: AnyHashable
    private var showsVerticalScrollIndicator: Bool
    private var backgroundColor: UIColor
    private var scrollRequest: FireCollectionScrollRequest<ItemID>?

    private var collectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, ItemID>?
    private var currentSections: [FireListSectionModel<SectionID, ItemID>] = []
    private var currentItemContentTokens: [ItemID: AnyHashable] = [:]
    private var lastVisibleItemIDs: [ItemID] = []
    private var lastScrollMetrics: FireCollectionScrollMetrics?
    private var isRefreshing = false
    private var handledScrollRequestID: AnyHashable?
    private var animatingScrollRequest: FireCollectionScrollRequest<ItemID>?

    init(
        layout: UICollectionViewLayout,
        layoutVersion: AnyHashable = 0,
        contentVersion: AnyHashable = 0,
        showsVerticalScrollIndicator: Bool = true,
        backgroundColor: UIColor = .clear,
        onSelectItem: ((ItemID) -> Void)? = nil,
        canSelectItem: ((ItemID) -> Bool)? = nil,
        onVisibleItemsChanged: (([ItemID]) -> Void)? = nil,
        onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil,
        scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy = .whenNotAnimatingDifferences,
        scrollRequest: FireCollectionScrollRequest<ItemID>? = nil,
        onScrollRequestCompleted: ((ItemID) -> Void)? = nil,
        rowContent: @escaping (ItemID) -> RowContent
    ) {
        self.listLayout = layout
        self.layoutVersion = layoutVersion
        self.contentVersion = contentVersion
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.backgroundColor = backgroundColor
        self.onSelectItem = onSelectItem
        self.canSelectItem = canSelectItem
        self.onVisibleItemsChanged = onVisibleItemsChanged
        self.onScrollMetricsChanged = onScrollMetricsChanged
        self.onRefresh = onRefresh
        self.scrollAnchorRestorePolicy = scrollAnchorRestorePolicy
        self.scrollRequest = scrollRequest
        self.onScrollRequestCompleted = onScrollRequestCompleted
        self.rowContent = rowContent
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: listLayout)
        collectionView.backgroundColor = backgroundColor
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        collectionView.allowsSelection = onSelectItem != nil
        collectionView.delegate = self
        self.collectionView = collectionView
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let collectionView else { return }

        if onRefresh != nil {
            let refreshControl = UIRefreshControl()
            refreshControl.addAction(
                UIAction { [weak self] _ in
                    self?.triggerRefresh()
                },
                for: .valueChanged
            )
            collectionView.refreshControl = refreshControl
        }

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, ItemID> {
            [weak self] cell, _, itemID in
            guard let self else { return }
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            cell.contentConfiguration = UIHostingConfiguration {
                self.rowContent(itemID)
            }
            .margins(.all, 0)
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, ItemID>(
            collectionView: collectionView
        ) { collectionView, indexPath, itemID in
            collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: itemID
            )
        }
    }

    func updateLayoutIfNeeded(
        version: AnyHashable,
        makeLayout: () -> UICollectionViewLayout
    ) {
        guard fireCollectionNeedsLayoutUpdate(currentVersion: layoutVersion, incomingVersion: version)
        else {
            return
        }
        layoutVersion = version
        let layout = makeLayout()
        listLayout = layout
        collectionView?.setCollectionViewLayout(layout, animated: false)
    }

    func updateRowContent(_ rowContent: @escaping (ItemID) -> RowContent) {
        self.rowContent = rowContent
    }

    func updateAppearance(
        showsVerticalScrollIndicator: Bool,
        backgroundColor: UIColor
    ) {
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.backgroundColor = backgroundColor
        collectionView?.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        collectionView?.backgroundColor = backgroundColor
    }

    func updateScrollRequest(
        _ scrollRequest: FireCollectionScrollRequest<ItemID>?,
        onCompleted: ((ItemID) -> Void)?
    ) {
        if let currentScrollRequest = self.scrollRequest,
           let scrollRequest,
           currentScrollRequest.requestID == scrollRequest.requestID,
           currentScrollRequest.itemID != scrollRequest.itemID {
            assertionFailure("FireCollectionScrollRequest request IDs must stay bound to one item ID.")
        }

        let requestChanged = fireCollectionScrollRequestDidChange(
            current: self.scrollRequest,
            incoming: scrollRequest
        )
        self.scrollRequest = scrollRequest
        self.onScrollRequestCompleted = onCompleted

        if requestChanged {
            animatingScrollRequest = nil
        }

        if scrollRequest == nil {
            handledScrollRequestID = nil
            animatingScrollRequest = nil
        } else {
            applyScrollRequestIfNeeded()
        }
    }

    func setSections(
        _ sections: [FireListSectionModel<SectionID, ItemID>],
        contentVersion: AnyHashable,
        itemContentTokens: [ItemID: AnyHashable]?,
        animatingDifferences: Bool
    ) {
        guard let dataSource else { return }
        let sectionsChanged = fireCollectionNeedsSectionUpdate(
            current: currentSections,
            incoming: sections
        )
        let legacyContentChanged = self.contentVersion != contentVersion

        let reconfiguredItems: [ItemID]
        let contentChanged: Bool
        if let itemContentTokens {
            let changed = fireCollectionChangedItems(
                current: currentSections,
                incoming: sections,
                previousTokens: currentItemContentTokens,
                currentTokens: itemContentTokens
            )
            reconfiguredItems = changed
            contentChanged = !changed.isEmpty
        } else {
            reconfiguredItems = legacyContentChanged
                ? fireCollectionCommonItems(current: currentSections, incoming: sections)
                : []
            contentChanged = legacyContentChanged
        }

        guard sectionsChanged || contentChanged else {
            return
        }

        currentSections = sections
        self.contentVersion = contentVersion
        if let itemContentTokens {
            currentItemContentTokens = itemContentTokens
        }

        // Diffable animations during an active drag or fling steal momentum from the
        // user's gesture, so we only animate insertions when the scroll view is idle.
        let isActivelyScrolling = collectionView.map { $0.isDragging || $0.isDecelerating } ?? false
        let effectiveAnimatingDifferences =
            sectionsChanged && animatingDifferences && !isActivelyScrolling
        let shouldRestoreScrollAnchor = scrollAnchorRestorePolicy.shouldRestore(
            animatingDifferences: effectiveAnimatingDifferences
        )
        let scrollAnchor = shouldRestoreScrollAnchor ? currentScrollAnchor() : nil
        var snapshot = NSDiffableDataSourceSnapshot<SectionID, ItemID>()
        for section in sections {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.items, toSection: section.id)
        }
        if !reconfiguredItems.isEmpty {
            snapshot.reconfigureItems(reconfiguredItems)
        }

        dataSource.apply(snapshot, animatingDifferences: effectiveAnimatingDifferences) { [weak self] in
            guard let self else { return }
            self.restoreScrollAnchor(scrollAnchor)
            self.applyScrollRequestIfNeeded()
            self.publishVisibleItems()
            self.publishScrollMetrics()
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath)
        -> Bool
    {
        guard let itemID = dataSource?.itemIdentifier(for: indexPath) else { return false }
        return canSelectItem?(itemID) ?? true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let itemID = dataSource?.itemIdentifier(for: indexPath) else { return }
        onSelectItem?(itemID)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        publishVisibleItems()
        publishScrollMetrics()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A user-initiated drag cancels any animated scroll request; UIKit won't fire
        // scrollViewDidEndScrollingAnimation, so complete the request here so the
        // caller can clear its pending target.
        completeAnimatedScrollRequestIfNeeded()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            publishVisibleItems()
            publishScrollMetrics()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        publishVisibleItems()
        publishScrollMetrics()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        publishVisibleItems()
        publishScrollMetrics()
        completeAnimatedScrollRequestIfNeeded()
    }

    private func publishVisibleItems() {
        guard let collectionView, let dataSource else { return }

        let visibleItemIDs = collectionView.indexPathsForVisibleItems
            .sorted()
            .compactMap { dataSource.itemIdentifier(for: $0) }

        guard visibleItemIDs != lastVisibleItemIDs else { return }
        lastVisibleItemIDs = visibleItemIDs
        onVisibleItemsChanged?(visibleItemIDs)
    }

    private func publishScrollMetrics() {
        guard let collectionView else { return }

        let visibleHeight = max(
            collectionView.bounds.height
                - collectionView.adjustedContentInset.top
                - collectionView.adjustedContentInset.bottom,
            0
        )
        let visibleTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let visibleBottom = visibleTop + visibleHeight
        let metrics = FireCollectionScrollMetrics(
            remainingDistanceToBottom: max(0, collectionView.contentSize.height - visibleBottom),
            contentHeight: collectionView.contentSize.height,
            visibleHeight: visibleHeight
        )

        guard metrics != lastScrollMetrics else { return }
        lastScrollMetrics = metrics
        onScrollMetricsChanged?(metrics)
    }

    private func triggerRefresh() {
        guard !isRefreshing else { return }
        guard let onRefresh else { return }
        isRefreshing = true

        Task { [weak self] in
            await onRefresh()
            await MainActor.run {
                guard let self else { return }
                self.collectionView?.refreshControl?.endRefreshing()
                self.isRefreshing = false
                self.publishScrollMetrics()
            }
        }
    }

    private func currentScrollAnchor() -> FireCollectionScrollAnchor<ItemID>? {
        guard let collectionView, let dataSource else { return nil }

        let topIndexPath = collectionView.indexPathsForVisibleItems
            .sorted {
                if $0.section == $1.section {
                    return $0.item < $1.item
                }
                return $0.section < $1.section
            }
            .first

        guard
            let topIndexPath,
            let itemID = dataSource.itemIdentifier(for: topIndexPath),
            let attributes = collectionView.layoutAttributesForItem(at: topIndexPath)
        else {
            return nil
        }

        let offsetFromTop =
            collectionView.contentOffset.y
            + collectionView.adjustedContentInset.top
            - attributes.frame.minY

        return FireCollectionScrollAnchor(
            itemID: itemID,
            offsetFromTop: offsetFromTop
        )
    }

    private func restoreScrollAnchor(_ scrollAnchor: FireCollectionScrollAnchor<ItemID>?) {
        guard
            let collectionView,
            let dataSource,
            let scrollAnchor,
            let indexPath = dataSource.indexPath(for: scrollAnchor.itemID)
        else {
            return
        }

        collectionView.layoutIfNeeded()

        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            return
        }

        let adjustedTop = collectionView.adjustedContentInset.top
        let minOffsetY = -adjustedTop
        let maxOffsetY = max(
            minOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        let targetOffsetY = min(
            max(attributes.frame.minY - adjustedTop + scrollAnchor.offsetFromTop, minOffsetY),
            maxOffsetY
        )

        // setContentOffset(animated: false) cancels the user's in-flight drag or fling.
        // When the anchor hasn't shifted (items added only below the viewport, or no
        // geometry change), skip the write so mid-scroll updates don't break momentum.
        // When it has shifted (e.g. backward pagination prepended replies), restore so
        // the reader stays locked to the same post instead of jumping.
        if abs(collectionView.contentOffset.y - targetOffsetY) < 0.5 {
            return
        }

        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
            animated: false
        )
    }

    private func applyScrollRequestIfNeeded() {
        guard
            let collectionView,
            let dataSource,
            let scrollRequest,
            fireCollectionNeedsScrollRequest(
                handledRequestID: handledScrollRequestID,
                incoming: scrollRequest
            ),
            let indexPath = dataSource.indexPath(for: scrollRequest.itemID)
        else {
            return
        }

        collectionView.layoutIfNeeded()
        handledScrollRequestID = scrollRequest.requestID

        // scrollToItem is a no-op when the target is already aligned at .top — UIKit
        // won't fire scrollViewDidEndScrollingAnimation in that case, so detect it
        // here and complete synchronously. Reading contentOffset after an animated
        // scrollToItem returns the pre-animation value, so compare against the
        // clamped target offset we expect UIKit to settle on instead.
        let willMove = scrollToItemWillMove(indexPath: indexPath)
        collectionView.scrollToItem(at: indexPath, at: .top, animated: scrollRequest.animated)

        if scrollRequest.animated && willMove {
            animatingScrollRequest = scrollRequest
        } else {
            onScrollRequestCompleted?(scrollRequest.itemID)
        }
    }

    private func scrollToItemWillMove(indexPath: IndexPath) -> Bool {
        guard let collectionView,
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            return true
        }
        let adjustedTop = collectionView.adjustedContentInset.top
        let minOffsetY = -adjustedTop
        let maxOffsetY = max(
            minOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        let targetOffsetY = min(max(attributes.frame.minY - adjustedTop, minOffsetY), maxOffsetY)
        return abs(collectionView.contentOffset.y - targetOffsetY) >= 0.5
    }

    private func completeAnimatedScrollRequestIfNeeded() {
        guard let scrollRequest = animatingScrollRequest else { return }
        animatingScrollRequest = nil
        onScrollRequestCompleted?(scrollRequest.itemID)
    }
}
