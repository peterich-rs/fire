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

@MainActor
final class FireDiffableListController<SectionID: Hashable, ItemID: Hashable, RowContent: View>: UIViewController,
    UICollectionViewDelegate
{
    private let rowContent: (ItemID) -> RowContent
    private let onSelectItem: ((ItemID) -> Void)?
    private let canSelectItem: ((ItemID) -> Bool)?
    private let onVisibleItemsChanged: (([ItemID]) -> Void)?
    private let onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)?
    private let onRefresh: (() async -> Void)?
    private let scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy
    private var listLayout: UICollectionViewLayout
    private var layoutVersion: AnyHashable
    private var contentVersion: AnyHashable
    private var showsVerticalScrollIndicator: Bool
    private var backgroundColor: UIColor

    private var collectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, ItemID>?
    private var currentSections: [FireListSectionModel<SectionID, ItemID>] = []
    private var lastVisibleItemIDs: [ItemID] = []
    private var lastScrollMetrics: FireCollectionScrollMetrics?
    private var isRefreshing = false

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

    func updateAppearance(
        showsVerticalScrollIndicator: Bool,
        backgroundColor: UIColor
    ) {
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.backgroundColor = backgroundColor
        collectionView?.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        collectionView?.backgroundColor = backgroundColor
    }

    func setSections(
        _ sections: [FireListSectionModel<SectionID, ItemID>],
        contentVersion: AnyHashable,
        animatingDifferences: Bool
    ) {
        guard let dataSource else { return }
        let sectionsChanged = fireCollectionNeedsSectionUpdate(
            current: currentSections,
            incoming: sections
        )
        let contentChanged = self.contentVersion != contentVersion
        guard sectionsChanged || contentChanged else {
            return
        }
        let reconfiguredItems = contentChanged
            ? fireCollectionCommonItems(current: currentSections, incoming: sections)
            : []
        currentSections = sections
        self.contentVersion = contentVersion

        // Animated diffable updates should keep UIKit's insertion/reorder animation intact.
        // Restoring contentOffset after those animations turns local diffs into visible snaps.
        let effectiveAnimatingDifferences = sectionsChanged && animatingDifferences
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
        let targetOffsetY = attributes.frame.minY - adjustedTop + scrollAnchor.offsetFromTop

        collectionView.setContentOffset(
            CGPoint(
                x: collectionView.contentOffset.x,
                y: min(max(targetOffsetY, minOffsetY), maxOffsetY)
            ),
            animated: false
        )
    }
}
