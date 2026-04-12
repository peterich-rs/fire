import SwiftUI
import UIKit

struct FireCollectionHost<SectionID: Hashable, ItemID: Hashable, RowContent: View>:
    UIViewControllerRepresentable
{
    let sections: [FireListSectionModel<SectionID, ItemID>]
    let makeLayout: () -> UICollectionViewLayout
    let showsVerticalScrollIndicator: Bool
    let backgroundColor: UIColor
    let animatingDifferences: Bool
    let onSelectItem: ((ItemID) -> Void)?
    let canSelectItem: ((ItemID) -> Bool)?
    let onVisibleItemsChanged: (([ItemID]) -> Void)?
    let onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)?
    let onRefresh: (() async -> Void)?
    let rowContent: (ItemID) -> RowContent

    init(
        sections: [FireListSectionModel<SectionID, ItemID>],
        showsVerticalScrollIndicator: Bool = true,
        backgroundColor: UIColor = .clear,
        animatingDifferences: Bool = true,
        onSelectItem: ((ItemID) -> Void)? = nil,
        canSelectItem: ((ItemID) -> Bool)? = nil,
        onVisibleItemsChanged: (([ItemID]) -> Void)? = nil,
        onScrollMetricsChanged: ((FireCollectionScrollMetrics) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil,
        makeLayout: @escaping () -> UICollectionViewLayout,
        rowContent: @escaping (ItemID) -> RowContent
    ) {
        self.sections = sections
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.backgroundColor = backgroundColor
        self.animatingDifferences = animatingDifferences
        self.onSelectItem = onSelectItem
        self.canSelectItem = canSelectItem
        self.onVisibleItemsChanged = onVisibleItemsChanged
        self.onScrollMetricsChanged = onScrollMetricsChanged
        self.onRefresh = onRefresh
        self.makeLayout = makeLayout
        self.rowContent = rowContent
    }

    func makeUIViewController(context: Context)
        -> FireDiffableListController<SectionID, ItemID, RowContent>
    {
        let controller: FireDiffableListController<SectionID, ItemID, RowContent> =
            FireDiffableListController(
                layout: makeLayout(),
                showsVerticalScrollIndicator: showsVerticalScrollIndicator,
                backgroundColor: backgroundColor,
                onSelectItem: onSelectItem,
                canSelectItem: canSelectItem,
                onVisibleItemsChanged: onVisibleItemsChanged,
                onScrollMetricsChanged: onScrollMetricsChanged,
                onRefresh: onRefresh,
                rowContent: rowContent
            )
        return controller
    }

    func updateUIViewController(
        _ uiViewController: FireDiffableListController<SectionID, ItemID, RowContent>,
        context: Context
    ) {
        uiViewController.updateLayout(makeLayout())
        uiViewController.updateAppearance(
            showsVerticalScrollIndicator: showsVerticalScrollIndicator,
            backgroundColor: backgroundColor
        )
        uiViewController.setSections(
            sections,
            animatingDifferences: animatingDifferences
        )
    }
}
