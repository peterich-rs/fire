import Combine
import SwiftUI
import UIKit

@MainActor
extension FireDraftsViewController {
    var contentVersion: ContentVersion {
        ContentVersion(
            drafts: draftsViewModel.drafts.map(FireDraftContentToken.init),
            hasMore: draftsViewModel.hasMore,
            isLoading: draftsViewModel.isLoading,
            isLoadingMore: draftsViewModel.isLoadingMore,
            hasLoadedOnce: draftsViewModel.hasLoadedOnce,
            errorMessage: draftsViewModel.errorMessage
        )
    }

    func render() {
        let sections = makeSections()
        var tokens: [FireDraftsCollectionItem: AnyHashable] = [:]
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

    func makeSections() -> [FireListSectionModel<FireDraftsCollectionSection, FireDraftsCollectionItem>] {
        var items: [FireDraftsCollectionItem] = []

        if !draftsViewModel.hasLoadedOnce {
            if let errorMessage = draftsViewModel.errorMessage {
                items.append(.blockingError(errorMessage))
            } else {
                items.append(.loading)
            }
            return [.init(id: .content, items: items)]
        }

        if let errorMessage = draftsViewModel.errorMessage {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if draftsViewModel.drafts.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: draftsViewModel.drafts.map { .draft($0.draftKey) })
            if draftsViewModel.isLoadingMore {
                items.append(.loadingMore)
            }
        }

        return [.init(id: .content, items: items)]
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireDraftsCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .blockingError, .loading, .empty, .loadingMore:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .inlineErrorBanner:
            return collectionView.dequeueConfiguredReusableCell(
                using: bannerCellRegistration,
                for: indexPath,
                item: item
            )
        case .draft:
            return collectionView.dequeueConfiguredReusableCell(
                using: draftCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    func draft(key: String) -> DraftState? {
        draftsViewModel.drafts.first { $0.draftKey == key }
    }

    func itemContentToken(for item: FireDraftsCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(draftsViewModel.isLoading)
        case .empty:
            return AnyHashable(draftsViewModel.hasLoadedOnce)
        case let .draft(key):
            guard let draft = draft(key: key) else {
                return AnyHashable("missing|\(key)")
            }
            return AnyHashable(FireDraftContentToken(draft))
        case .loadingMore:
            return AnyHashable(draftsViewModel.isLoadingMore)
        }
    }
}
