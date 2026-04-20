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
    let onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)?
    let onRefresh: (() async -> Void)?
    let scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy
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
        onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil,
        scrollAnchorRestorePolicy: FireCollectionScrollAnchorRestorePolicy = .whenNotAnimatingDifferences,
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
        self.onScrollMetricsChanged = onScrollMetricsChanged
        self.onRefresh = onRefresh
        self.scrollAnchorRestorePolicy = scrollAnchorRestorePolicy
        self.scrollRequest = scrollRequest
        self.onScrollRequestCompleted = onScrollRequestCompleted
        self.makeLayout = makeLayout
        self.rowContent = rowContent
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
                onScrollMetricsChanged: onScrollMetricsChanged,
                onRefresh: onRefresh,
                scrollAnchorRestorePolicy: scrollAnchorRestorePolicy,
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
        let itemContentTokens: [ItemID: AnyHashable]?
        if let itemContentToken {
            var tokens: [ItemID: AnyHashable] = [:]
            tokens.reserveCapacity(sections.reduce(0) { $0 + $1.items.count })
            for section in sections {
                for item in section.items {
                    tokens[item] = itemContentToken(item)
                }
            }
            itemContentTokens = tokens
        } else {
            itemContentTokens = nil
        }
        uiViewController.setSections(
            sections,
            contentVersion: contentVersion,
            itemContentTokens: itemContentTokens,
            animatingDifferences: animatingDifferences
        )
    }
}
