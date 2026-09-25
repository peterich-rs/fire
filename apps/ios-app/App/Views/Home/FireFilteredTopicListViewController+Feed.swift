import Combine
import SwiftUI
import UIKit

@MainActor
extension FireFilteredTopicListViewController {
    var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var contentVersion: ContentVersion {
        ContentVersion(
            selectedKind: listViewModel.selectedKind,
            rows: listViewModel.displayedRows.map(\.topic.id),
            nextPage: listViewModel.currentKindNextPage,
            isLoading: listViewModel.isLoading,
            isLoadingMore: listViewModel.isLoadingMore,
            hasResolved: listViewModel.hasResolvedCurrentKind,
            errorMessage: listViewModel.errorMessage,
            displayState: listViewModel.currentKindDisplayState
        )
    }

    func render() {
        let sections = makeSections()
        var tokens: [FireFilteredTopicItem: AnyHashable] = [:]
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

    func makeSections()
        -> [FireListSectionModel<FireFilteredTopicSection, FireFilteredTopicItem>]
    {
        var sections: [FireListSectionModel<FireFilteredTopicSection, FireFilteredTopicItem>] = [
            .init(id: .feedSelector, items: [.feedSelector]),
        ]

        var items: [FireFilteredTopicItem] = []
        switch listViewModel.currentKindDisplayState {
        case .loading:
            items.append(contentsOf: (0..<6).map { .loadingSkeleton($0) })
        case let .blockingError(message):
            items.append(.blockingError(message))
        case let .empty(nonBlocking):
            if let nonBlocking {
                items.append(.inlineErrorBanner(nonBlocking))
            }
            items.append(.empty)
        case let .content(nonBlocking):
            if let nonBlocking {
                items.append(.inlineErrorBanner(nonBlocking))
            }
            items.append(contentsOf: listViewModel.displayedRows.map { .topic($0.topic.id) })
            if listViewModel.currentKindNextPage != nil {
                items.append(.loadingMore)
            }
        }
        sections.append(.init(id: .content, items: items))
        return sections
    }

    func itemContentToken(for item: FireFilteredTopicItem) -> AnyHashable {
        switch item {
        case .feedSelector:
            return listViewModel.selectedKind
        case let .blockingError(message), let .inlineErrorBanner(message):
            return message
        case let .loadingSkeleton(index):
            return index
        case .empty:
            return "empty"
        case let .topic(id):
            if let row = listViewModel.displayedRows.first(where: { $0.topic.id == id }) {
                return "\(id)-\(row.topic.likeCount)-\(row.topic.replyCount)-\(row.topic.bookmarkId ?? 0)"
            }
            return id
        case .loadingMore:
            return listViewModel.isLoadingMore
        }
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireFilteredTopicItem
    ) -> UICollectionViewCell {
        switch item {
        case .feedSelector:
            return collectionView.dequeueConfiguredReusableCell(
                using: feedSelectorCellRegistration,
                for: indexPath,
                item: item
            )
        case .blockingError, .empty, .loadingMore:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .loadingSkeleton:
            return collectionView.dequeueConfiguredReusableCell(
                using: skeletonCellRegistration,
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
}
