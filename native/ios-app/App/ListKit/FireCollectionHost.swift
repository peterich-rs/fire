import SwiftUI
import UIKit

enum FireCollectionLayouts {
    static func plainList(
        backgroundColor: UIColor = .clear,
        showsSeparators: Bool = false
    ) -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = backgroundColor
        configuration.showsSeparators = showsSeparators
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }
}

struct FireCollectionHost<SectionID: Hashable, ItemID: Hashable, RowContent: View>:
    UIViewControllerRepresentable
{
    final class Coordinator {
        private var cachedSections: [FireListSectionModel<SectionID, ItemID>] = []
        private var cachedContentVersion: AnyHashable?
        private var cachedItemContentTokens: [ItemID: AnyHashable]?

        func resolveItemContentTokens(
            sections: [FireListSectionModel<SectionID, ItemID>],
            contentVersion: AnyHashable,
            itemContentToken: ((ItemID) -> AnyHashable)?
        ) -> [ItemID: AnyHashable]? {
            guard let itemContentToken else {
                cachedSections = []
                cachedContentVersion = nil
                cachedItemContentTokens = nil
                return nil
            }

            if cachedSections == sections,
               cachedContentVersion == contentVersion,
               let cachedItemContentTokens {
                return cachedItemContentTokens
            }

            var tokens: [ItemID: AnyHashable] = [:]
            tokens.reserveCapacity(sections.reduce(0) { $0 + $1.items.count })
            for section in sections {
                for item in section.items {
                    tokens[item] = itemContentToken(item)
                }
            }

            cachedSections = sections
            cachedContentVersion = contentVersion
            cachedItemContentTokens = tokens
            return tokens
        }
    }

    let sections: [FireListSectionModel<SectionID, ItemID>]
    let layoutVersion: AnyHashable
    let contentVersion: AnyHashable
    let itemContentToken: ((ItemID) -> AnyHashable)?
    let makeLayout: () -> UICollectionViewLayout
    let showsVerticalScrollIndicator: Bool
    let backgroundColor: UIColor
    let animatingDifferences: Bool
    let onSelectItem: ((ItemID) -> Void)?
    let canSelectItem: ((ItemID) -> Bool)?
    let onVisibleItemsChanged: (([ItemID]) -> Void)?
    let onPrefetchItems: (([ItemID]) -> Void)?
    let onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)?
    let onRefresh: (() async -> Void)?
    let scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy
    let updatePolicy: FireCollectionUpdatePolicy
    let scrollRequest: FireCollectionScrollRequest<ItemID>?
    let onScrollRequestCompleted: ((ItemID) -> Void)?
    let rowContent: (ItemID) -> RowContent

    init(
        sections: [FireListSectionModel<SectionID, ItemID>],
        layoutVersion: AnyHashable = 0,
        contentVersion: AnyHashable = 0,
        itemContentToken: ((ItemID) -> AnyHashable)? = nil,
        showsVerticalScrollIndicator: Bool = true,
        backgroundColor: UIColor = .clear,
        animatingDifferences: Bool = true,
        onSelectItem: ((ItemID) -> Void)? = nil,
        canSelectItem: ((ItemID) -> Bool)? = nil,
        onVisibleItemsChanged: (([ItemID]) -> Void)? = nil,
        onPrefetchItems: (([ItemID]) -> Void)? = nil,
        onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil,
        scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy = .whenNotAnimatingDifferences,
        updatePolicy: FireCollectionUpdatePolicy = .applyImmediately,
        scrollRequest: FireCollectionScrollRequest<ItemID>? = nil,
        onScrollRequestCompleted: ((ItemID) -> Void)? = nil,
        makeLayout: @escaping () -> UICollectionViewLayout,
        rowContent: @escaping (ItemID) -> RowContent
    ) {
        self.sections = sections
        self.layoutVersion = layoutVersion
        self.contentVersion = contentVersion
        self.itemContentToken = itemContentToken
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.backgroundColor = backgroundColor
        self.animatingDifferences = animatingDifferences
        self.onSelectItem = onSelectItem
        self.canSelectItem = canSelectItem
        self.onVisibleItemsChanged = onVisibleItemsChanged
        self.onPrefetchItems = onPrefetchItems
        self.onScrollMetricsChanged = onScrollMetricsChanged
        self.onRefresh = onRefresh
        self.scrollAnchorRestorePolicy = scrollAnchorRestorePolicy
        self.updatePolicy = updatePolicy
        self.scrollRequest = scrollRequest
        self.onScrollRequestCompleted = onScrollRequestCompleted
        self.makeLayout = makeLayout
        self.rowContent = rowContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context)
        -> FireDiffableListController<SectionID, ItemID, RowContent>
    {
        let controller: FireDiffableListController<SectionID, ItemID, RowContent> =
            FireDiffableListController(
                layout: makeLayout(),
                layoutVersion: layoutVersion,
                contentVersion: contentVersion,
                showsVerticalScrollIndicator: showsVerticalScrollIndicator,
                backgroundColor: backgroundColor,
                onSelectItem: onSelectItem,
                canSelectItem: canSelectItem,
                onVisibleItemsChanged: onVisibleItemsChanged,
                onPrefetchItems: onPrefetchItems,
                onScrollMetricsChanged: onScrollMetricsChanged,
                onRefresh: onRefresh,
                scrollAnchorRestorePolicy: scrollAnchorRestorePolicy,
                updatePolicy: updatePolicy,
                scrollRequest: scrollRequest,
                onScrollRequestCompleted: onScrollRequestCompleted,
                rowContent: rowContent
            )
        return controller
    }

    func updateUIViewController(
        _ uiViewController: FireDiffableListController<SectionID, ItemID, RowContent>,
        context: Context
    ) {
        uiViewController.updateRowContent(rowContent)
        uiViewController.updateScrollRequest(
            scrollRequest,
            onCompleted: onScrollRequestCompleted
        )
        uiViewController.updateLayoutIfNeeded(
            version: layoutVersion,
            makeLayout: makeLayout
        )
        uiViewController.updateAppearance(
            showsVerticalScrollIndicator: showsVerticalScrollIndicator,
            backgroundColor: backgroundColor
        )
        let itemContentTokens = context.coordinator.resolveItemContentTokens(
            sections: sections,
            contentVersion: contentVersion,
            itemContentToken: itemContentToken
        )
        uiViewController.setSections(
            sections,
            contentVersion: contentVersion,
            itemContentTokens: itemContentTokens,
            animatingDifferences: animatingDifferences
        )
    }
}
