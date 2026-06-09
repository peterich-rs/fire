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

enum FireCollectionUpdatePolicy {
    case applyImmediately
    case deferWhileScrolling
    case deferDuringRefresh
}

func fireCollectionShouldDeferSectionUpdate(
    updatePolicy: FireCollectionUpdatePolicy,
    isActivelyScrolling: Bool,
    isInRefreshLifecycle: Bool,
    hasCurrentSections: Bool
) -> Bool {
    guard hasCurrentSections else {
        return false
    }
    switch updatePolicy {
    case .applyImmediately:
        return false
    case .deferWhileScrolling:
        return isActivelyScrolling || isInRefreshLifecycle
    case .deferDuringRefresh:
        return isInRefreshLifecycle
    }
}

private struct FirePendingSectionUpdate<SectionID: Hashable, ItemID: Hashable> {
    let sections: [FireListSectionModel<SectionID, ItemID>]
    let contentVersion: AnyHashable
    let itemContentTokens: [ItemID: AnyHashable]?
    let animatingDifferences: Bool
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

func fireCollectionChangedCellRoutingItems<ItemID: Hashable>(
    changedItems: [ItemID],
    previousRouting: [ItemID: Bool],
    incomingRouting: [ItemID: Bool]
) -> [ItemID] {
    changedItems.filter { item in
        previousRouting[item] != incomingRouting[item]
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
    UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching
{
    private var rowContent: (ItemID) -> RowContent
    private var shouldUseNativeCell: ((ItemID) -> Bool)?
    private var nativeCellProvider: ((UICollectionView, IndexPath, ItemID) -> UICollectionViewCell?)?
    private let onSelectItem: ((ItemID) -> Void)?
    private let canSelectItem: ((ItemID) -> Bool)?
    private let onVisibleItemsChanged: (([ItemID]) -> Void)?
    private let onPrefetchItems: (([ItemID]) -> Void)?
    private let onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)?
    private let onRefresh: (() async -> Void)?
    private var onContentWidthChanged: ((CGFloat) -> Void)?
    private let scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy
    private let updatePolicy: FireCollectionUpdatePolicy
    private var onScrollRequestCompleted: ((ItemID) -> Void)?
    private var listLayout: UICollectionViewLayout
    private var layoutVersion: AnyHashable
    private var contentVersion: AnyHashable
    private var showsVerticalScrollIndicator: Bool
    private var backgroundColor: UIColor
    private var scrollRequest: FireCollectionScrollRequest<ItemID>?

    private var collectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, ItemID>?
    private var hostedCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, ItemID>?
    private var currentSections: [FireListSectionModel<SectionID, ItemID>] = []
    private var currentItemContentTokens: [ItemID: AnyHashable] = [:]
    private var currentNativeCellUsage: [ItemID: Bool] = [:]
    private var lastVisibleItemIDs: [ItemID] = []
    private var lastScrollMetrics: FireCollectionScrollMetrics?
    private var lastContentWidth: CGFloat?
    private var isRefreshing = false
    // Set when `endRefreshing()` starts the refresh control's retraction animation,
    // and cleared once the scroll view finishes the post-rebound deceleration (or a
    // safety timeout fires). While set, we keep deferring our own scroll-anchor
    // restoration at the top edge so UIKit can own the rebound and SwiftUI's
    // large-title navigation chrome can track contentOffset/inset transitions
    // without us interrupting them via setContentOffset(animated: false).
    private var isSettlingAfterRefresh = false
    private var refreshSettlingTimeoutTask: Task<Void, Never>?
    private var handledScrollRequestID: AnyHashable?
    private var animatingScrollRequest: FireCollectionScrollRequest<ItemID>?
    private var pendingSectionUpdate: FirePendingSectionUpdate<SectionID, ItemID>?
    init(
        layout: UICollectionViewLayout,
        layoutVersion: AnyHashable = 0,
        contentVersion: AnyHashable = 0,
        showsVerticalScrollIndicator: Bool = true,
        backgroundColor: UIColor = .clear,
        onSelectItem: ((ItemID) -> Void)? = nil,
        canSelectItem: ((ItemID) -> Bool)? = nil,
        onVisibleItemsChanged: (([ItemID]) -> Void)? = nil,
        onPrefetchItems: (([ItemID]) -> Void)? = nil,
        onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil,
        onContentWidthChanged: ((CGFloat) -> Void)? = nil,
        scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy = .whenNotAnimatingDifferences,
        updatePolicy: FireCollectionUpdatePolicy = .applyImmediately,
        scrollRequest: FireCollectionScrollRequest<ItemID>? = nil,
        onScrollRequestCompleted: ((ItemID) -> Void)? = nil,
        shouldUseNativeCell: ((ItemID) -> Bool)? = nil,
        nativeCellProvider: ((UICollectionView, IndexPath, ItemID) -> UICollectionViewCell?)? = nil,
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
        self.onPrefetchItems = onPrefetchItems
        self.onScrollMetricsChanged = onScrollMetricsChanged
        self.onRefresh = onRefresh
        self.onContentWidthChanged = onContentWidthChanged
        self.scrollAnchorRestorePolicy = scrollAnchorRestorePolicy
        self.updatePolicy = updatePolicy
        self.scrollRequest = scrollRequest
        self.onScrollRequestCompleted = onScrollRequestCompleted
        self.shouldUseNativeCell = shouldUseNativeCell
        self.nativeCellProvider = nativeCellProvider
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
        collectionView.prefetchDataSource = self
        self.collectionView = collectionView
        view = collectionView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        publishContentWidthChangeIfNeeded()
    }

    private func publishContentWidthChangeIfNeeded() {
        guard let collectionView else { return }
        let width = collectionView.bounds.width
            - collectionView.adjustedContentInset.left
            - collectionView.adjustedContentInset.right
        guard width > 0, width != lastContentWidth else {
            return
        }
        lastContentWidth = width
        onContentWidthChanged?(width)
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

        let hostedReg = UICollectionView.CellRegistration<UICollectionViewListCell, ItemID> {
            [weak self] cell, _, itemID in
            guard let self else { return }
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            cell.contentConfiguration = UIHostingConfiguration {
                self.rowContent(itemID)
            }
            .margins(.all, 0)
        }
        hostedCellRegistration = hostedReg

        dataSource = UICollectionViewDiffableDataSource<SectionID, ItemID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, itemID in
            guard let self else {
                return collectionView.dequeueConfiguredReusableCell(
                    using: hostedReg, for: indexPath, item: itemID
                )
            }

            if let shouldUseNativeCell = self.shouldUseNativeCell,
               shouldUseNativeCell(itemID),
               let nativeCellProvider = self.nativeCellProvider,
               let nativeCell = nativeCellProvider(collectionView, indexPath, itemID) {
                return nativeCell
            }

            return collectionView.dequeueConfiguredReusableCell(
                using: hostedReg, for: indexPath, item: itemID
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

    func updateNativeCellRouting(
        shouldUseNativeCell: ((ItemID) -> Bool)?,
        nativeCellProvider: ((UICollectionView, IndexPath, ItemID) -> UICollectionViewCell?)?
    ) {
        self.shouldUseNativeCell = shouldUseNativeCell
        self.nativeCellProvider = nativeCellProvider
    }

    func updateOnContentWidthChanged(_ handler: ((CGFloat) -> Void)?) {
        self.onContentWidthChanged = handler
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
        let sectionsChanged = fireCollectionNeedsSectionUpdate(
            current: currentSections,
            incoming: sections
        )
        let legacyContentChanged = self.contentVersion != contentVersion
        let incomingNativeCellUsage = resolveNativeCellUsage(for: sections)

        let reconfiguredItems: [ItemID]
        let reloadedItems: [ItemID]
        let contentChanged: Bool
        if let itemContentTokens {
            let changed = fireCollectionChangedItems(
                current: currentSections,
                incoming: sections,
                previousTokens: currentItemContentTokens,
                currentTokens: itemContentTokens
            )
            reloadedItems = fireCollectionChangedCellRoutingItems(
                changedItems: changed,
                previousRouting: currentNativeCellUsage,
                incomingRouting: incomingNativeCellUsage
            )
            reconfiguredItems = changed.filter { !reloadedItems.contains($0) }
            contentChanged = !changed.isEmpty
        } else {
            let changedItems = legacyContentChanged
                ? fireCollectionCommonItems(current: currentSections, incoming: sections)
                : []
            reloadedItems = fireCollectionChangedCellRoutingItems(
                changedItems: changedItems,
                previousRouting: currentNativeCellUsage,
                incomingRouting: incomingNativeCellUsage
            )
            reconfiguredItems = changedItems.filter { !reloadedItems.contains($0) }
            contentChanged = legacyContentChanged
        }

        guard sectionsChanged || contentChanged else {
            return
        }

        // Suppress diffable applies for the full pull-to-refresh lifecycle
        // (drag → release → refresh-control showing → onRefresh work →
        // endRefreshing rebound → deceleration). UIKit owns the contentOffset
        // and contentInset during all of these phases and SwiftUI's
        // large-title navigation chrome reads from those same values, so
        // landing a snapshot apply mid-cycle either flickers visible cells via
        // reconfigure or wedges the nav chrome into a half-collapsed state.
        let isActivelyScrolling = collectionView.map { $0.isDragging || $0.isDecelerating } ?? false
        let isInRefreshLifecycle =
            isRefreshing
            || isSettlingAfterRefresh
            || collectionView?.refreshControl?.isRefreshing == true
        if fireCollectionShouldDeferSectionUpdate(
            updatePolicy: updatePolicy,
            isActivelyScrolling: isActivelyScrolling,
            isInRefreshLifecycle: isInRefreshLifecycle,
            hasCurrentSections: !currentSections.isEmpty
        ) {
            pendingSectionUpdate = FirePendingSectionUpdate(
                sections: sections,
                contentVersion: contentVersion,
                itemContentTokens: itemContentTokens,
                animatingDifferences: animatingDifferences
            )
            return
        }

        pendingSectionUpdate = nil
        applySectionUpdate(
            sections: sections,
            contentVersion: contentVersion,
            itemContentTokens: itemContentTokens,
            nativeCellUsage: incomingNativeCellUsage,
            animatingDifferences: animatingDifferences,
            sectionsChanged: sectionsChanged,
            reloadedItems: reloadedItems,
            reconfiguredItems: reconfiguredItems
        )
    }

    private func applySectionUpdate(
        sections: [FireListSectionModel<SectionID, ItemID>],
        contentVersion: AnyHashable,
        itemContentTokens: [ItemID: AnyHashable]?,
        nativeCellUsage: [ItemID: Bool],
        animatingDifferences: Bool,
        sectionsChanged: Bool,
        reloadedItems: [ItemID],
        reconfiguredItems: [ItemID]
    ) {
        guard let dataSource else { return }

        currentSections = sections
        self.contentVersion = contentVersion
        currentNativeCellUsage = nativeCellUsage
        if let itemContentTokens {
            currentItemContentTokens = itemContentTokens
        }

        // Diffable animations during an active drag or fling steal momentum from the
        // user's gesture, so we only animate insertions when the scroll view is idle.
        let isActivelyScrolling = collectionView.map { $0.isDragging || $0.isDecelerating } ?? false
        let effectiveAnimatingDifferences =
            sectionsChanged && animatingDifferences && !isActivelyScrolling
        let shouldRestoreScrollAnchor =
            scrollAnchorRestorePolicy.shouldRestore(animatingDifferences: effectiveAnimatingDifferences)
            && !shouldDeferScrollAnchorRestoreDuringTopRefresh()
        let scrollAnchor = shouldRestoreScrollAnchor ? currentScrollAnchor() : nil
        let snapshotApplySignpost = FireAPMSignpost.begin("collection.snapshot_apply")
        var snapshot = NSDiffableDataSourceSnapshot<SectionID, ItemID>()
        for section in sections {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.items, toSection: section.id)
        }
        if !reloadedItems.isEmpty {
            snapshot.reloadItems(reloadedItems)
        }
        if !reconfiguredItems.isEmpty {
            snapshot.reconfigureItems(reconfiguredItems)
        }

        dataSource.apply(snapshot, animatingDifferences: effectiveAnimatingDifferences) { [weak self] in
            FireAPMSignpost.end(snapshotApplySignpost)
            guard let self else { return }
            self.restoreScrollAnchor(scrollAnchor)
            self.applyScrollRequestIfNeeded()
            self.publishVisibleItems()
            self.publishScrollMetrics()
        }
    }

    private func resolveNativeCellUsage(
        for sections: [FireListSectionModel<SectionID, ItemID>]
    ) -> [ItemID: Bool] {
        guard let shouldUseNativeCell else {
            return [:]
        }

        var nativeCellUsage: [ItemID: Bool] = [:]
        nativeCellUsage.reserveCapacity(sections.reduce(0) { $0 + $1.items.count })
        for section in sections {
            for item in section.items {
                nativeCellUsage[item] = shouldUseNativeCell(item)
            }
        }
        return nativeCellUsage
    }

    private func applyPendingSectionUpdateIfNeeded() {
        guard let pendingSectionUpdate else {
            return
        }
        self.pendingSectionUpdate = nil
        setSections(
            pendingSectionUpdate.sections,
            contentVersion: pendingSectionUpdate.contentVersion,
            itemContentTokens: pendingSectionUpdate.itemContentTokens,
            animatingDifferences: pendingSectionUpdate.animatingDifferences
        )
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

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let onPrefetchItems, let dataSource else { return }
        let itemIDs = indexPaths
            .sorted()
            .compactMap { dataSource.itemIdentifier(for: $0) }
        guard !itemIDs.isEmpty else { return }
        onPrefetchItems(itemIDs)
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
        // If the user starts dragging during the post-refresh rebound, UIKit
        // hands control back to the gesture and our settling window is no
        // longer meaningful. Clearing it here keeps subsequent snapshot
        // applies from over-deferring anchor restoration during a real scroll.
        endPostRefreshSettling()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            // The user lifted their finger and there's no fling, so the scroll
            // view is settled. Any post-refresh rebound that finishes via this
            // path should release the settling flag *before* flushing pending
            // updates, otherwise the flush would re-defer itself because
            // isInRefreshLifecycle still treats us as in-flight.
            endPostRefreshSettling()
            applyPendingSectionUpdateIfNeeded()
            publishVisibleItems()
            publishScrollMetrics()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // UIKit's post-refresh rebound completes via deceleration; once it
        // finishes the inset/contentOffset are back in their resting
        // relationship and we can safely take over anchor restoration again.
        // Clear the settling flag before flushing so the deferred update
        // actually lands instead of being re-deferred by setSections.
        endPostRefreshSettling()
        applyPendingSectionUpdateIfNeeded()
        publishVisibleItems()
        publishScrollMetrics()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        endPostRefreshSettling()
        applyPendingSectionUpdateIfNeeded()
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
            // SwiftUI's native `.refreshable` paces the system refresh control
            // to remain visible for ~0.5s even when the awaited work returns
            // immediately. Mirror that pacing here so Home's pull-to-refresh
            // feel matches the profile tab's `.refreshable` list — without it
            // a fast cache-warm refresh flashes the spinner for a single
            // frame and the gesture feels broken.
            let clock = ContinuousClock()
            let started = clock.now
            await onRefresh()
            let elapsed = clock.now - started
            let minimum: Duration = .milliseconds(500)
            if elapsed < minimum {
                try? await Task.sleep(for: minimum - elapsed)
            }
            await MainActor.run {
                guard let self else { return }
                FireMotionHaptics.impact(.light)
                self.collectionView?.refreshControl?.endRefreshing()
                self.isRefreshing = false
                self.beginPostRefreshSettling()
                self.publishScrollMetrics()
            }
        }
    }

    // After endRefreshing() the refresh control's retraction animates the
    // contentInset and contentOffset back toward the natural top edge. UIKit
    // also drives the SwiftUI large-title navigation chrome from those values,
    // so calling setContentOffset(animated: false) ourselves during this window
    // — which restoreScrollAnchor() does when geometry shifts — visibly wedges
    // Home's "首页" large title against the chips beneath it. Hold the
    // post-refresh settling flag until the scroll view actually settles so the
    // anchor-restore guard keeps deferring through the rebound. The timeout is
    // a safety net for the case where UIKit doesn't emit a settle callback
    // (e.g. content fits the viewport so deceleration never starts).
    private func beginPostRefreshSettling() {
        isSettlingAfterRefresh = true
        refreshSettlingTimeoutTask?.cancel()
        refreshSettlingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.endPostRefreshSettlingViaTimeout()
        }
    }

    private func endPostRefreshSettling() {
        guard isSettlingAfterRefresh else { return }
        isSettlingAfterRefresh = false
        refreshSettlingTimeoutTask?.cancel()
        refreshSettlingTimeoutTask = nil
    }

    // The 500ms safety net path: UIKit may not emit a deceleration callback
    // when the post-refresh rebound is short or the content fits in the
    // viewport. When the timeout fires, drain any update we deferred during
    // the refresh lifecycle so the table doesn't get stuck on stale rows.
    private func endPostRefreshSettlingViaTimeout() {
        guard isSettlingAfterRefresh else { return }
        endPostRefreshSettling()
        applyPendingSectionUpdateIfNeeded()
    }

    private func shouldDeferScrollAnchorRestoreDuringTopRefresh() -> Bool {
        guard let collectionView else { return false }
        let refreshControlActive =
            isRefreshing
            || isSettlingAfterRefresh
            || collectionView.refreshControl?.isRefreshing == true
        guard refreshControlActive else { return false }

        let topOffsetY = -collectionView.adjustedContentInset.top
        // Let UIKit own the top-edge rebound while the refresh control is still
        // contributing inset; forcing our own anchor restore here makes Home's
        // large-title shell easier to wedge into an in-between state.
        return collectionView.contentOffset.y <= topOffsetY + 1
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
