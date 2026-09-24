import UIKit

extension FireHomeViewController {
    func render() {
        let sections = makeSections()
        var tokens: [FireHomeCollectionItem: AnyHashable] = [:]
        tokens.reserveCapacity(sections.reduce(0) { $0 + $1.items.count })
        for section in sections {
            for item in section.items {
                tokens[item] = itemContentToken(for: item)
            }
        }
        listController.setSections(
            sections,
            contentVersion: contentVersion,
            itemContentTokens: tokens,
            animatingDifferences: true
        )
    }

    func makeSections() -> [FireListSectionModel<FireHomeCollectionSection, FireHomeCollectionItem>] {
        var sections: [FireListSectionModel<FireHomeCollectionSection, FireHomeCollectionItem>] = [
            .init(id: .scopeStatus, items: [.scopeStatus]),
        ]

        let contentItems: [FireHomeCollectionItem]
        switch homeFeedStore.topicListDisplayState {
        case .loading:
            contentItems = (0..<6).map(FireHomeCollectionItem.loadingSkeleton)
        case let .blockingError(message):
            contentItems = [.blockingError(message)]
        case let .empty(nonBlockingErrorMessage):
            contentItems =
                (nonBlockingErrorMessage.map { [.inlineErrorBanner($0)] } ?? [])
                + [.emptyState]
        case let .content(nonBlockingErrorMessage):
            contentItems =
                (nonBlockingErrorMessage.map { [.inlineErrorBanner($0)] } ?? [])
                + homeFeedStore.topicRows.map { .topic($0.topic.id) }
                + (homeFeedStore.currentScopeNextTopicsPage != nil && homeFeedStore.isAppendingTopics
                    ? [.appendingFooter]
                    : [])
        }

        sections.append(.init(id: .content, items: contentItems))
        return sections
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireHomeCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .scopeStatus:
            return collectionView.dequeueConfiguredReusableCell(
                using: scopeStatusCellRegistration,
                for: indexPath,
                item: item
            )
        case .blockingError, .emptyState, .appendingFooter:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .loadingSkeleton:
            return collectionView.dequeueConfiguredReusableCell(
                using: loadingSkeletonCellRegistration,
                for: indexPath,
                item: item
            )
        case .inlineErrorBanner:
            return collectionView.dequeueConfiguredReusableCell(
                using: bannerCellRegistration,
                for: indexPath,
                item: item
            )
        case .topic:
            return collectionView.dequeueConfiguredReusableCell(
                using: topicCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    func canSelect(_ item: FireHomeCollectionItem) -> Bool {
        if case .topic = item {
            return true
        }
        return false
    }

    func handleSelection(_ item: FireHomeCollectionItem) {
        guard case let .topic(topicID) = item else {
            appViewModel.topicRouteLogger()?.debug("home controller ignored selection item=\(String(describing: item))")
            return
        }
        guard let row = homeFeedStore.topicRow(for: topicID) else {
            appViewModel.topicRouteLogger()?.warning(
                "home controller selected missing topic row topic_id=\(topicID) visible_topic_count=\(homeFeedStore.visibleTopicIDs.count) row_count=\(homeFeedStore.topicRows.count)"
            )
            return
        }
        appViewModel.topicRouteLogger()?.info(
            "home controller selected topic topic_id=\(topicID) selected_kind=\(String(describing: homeFeedStore.selectedTopicKind)) selected_category_id=\(homeFeedStore.selectedHomeCategoryId.map(String.init) ?? "nil") selected_tag_count=\(homeFeedStore.selectedHomeTags.count) row_count=\(homeFeedStore.topicRows.count)"
        )
        presentRoute(.topic(row: row))
    }
    func itemContentToken(for item: FireHomeCollectionItem) -> AnyHashable {
        switch item {
        case .scopeStatus:
            let scope = homeFeedStore.scopePresentation
            return AnyHashable(
                [
                    scope.categoryPathTitle,
                    scope.kindTitle,
                    scope.tags.joined(separator: ","),
                    scope.showsChildShortcutStrip ? "children" : "parent-only",
                    scope.categoryAccentHex ?? "",
                ].joined(separator: "\u{1F}")
            )
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case let .topic(topicID):
            return AnyHashable(
                homeFeedStore.topicRowContentToken(for: topicID) ?? "missing|\(topicID)"
            )
        case let .loadingSkeleton(index):
            return AnyHashable(index)
        case .emptyState:
            return AnyHashable(homeFeedStore.topicListDisplayState)
        case .appendingFooter:
            return AnyHashable(homeFeedStore.isAppendingTopics)
        }
    }
}
