import Combine
import SwiftUI
import UIKit

@MainActor
extension FireReadHistoryViewController {
    var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var contentVersion: ContentVersion {
        ContentVersion(
            rows: historyViewModel.rows,
            nextPage: historyViewModel.nextPage,
            isLoading: historyViewModel.isLoading,
            isLoadingMore: historyViewModel.isLoadingMore,
            hasLoadedOnce: historyViewModel.hasLoadedOnce,
            errorMessage: historyViewModel.errorMessage
        )
    }

    func render() {
        let sections = makeSections()
        var tokens: [FireReadHistoryCollectionItem: AnyHashable] = [:]
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

    func makeSections()
        -> [FireListSectionModel<FireReadHistoryCollectionSection, FireReadHistoryCollectionItem>]
    {
        var items: [FireReadHistoryCollectionItem] = []

        if let errorMessage = historyViewModel.errorMessage,
           historyViewModel.hasLoadedOnce {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if !historyViewModel.hasLoadedOnce {
            if let errorMessage = historyViewModel.errorMessage {
                items.append(.blockingError(errorMessage))
            } else {
                items.append(.loading)
            }
        } else if historyViewModel.rows.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: historyViewModel.rows.map {
                .topic($0.topic.id)
            })

            if historyViewModel.isLoadingMore {
                items.append(.loadingMore)
            }
        }

        return [.init(id: .content, items: items)]
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireReadHistoryCollectionItem
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
        case .topic:
            return collectionView.dequeueConfiguredReusableCell(
                using: topicCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    func itemContentToken(for item: FireReadHistoryCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(historyViewModel.isLoading)
        case .empty:
            return AnyHashable(historyViewModel.hasLoadedOnce)
        case let .topic(topicID):
            guard let row = historyViewModel.row(for: topicID) else {
                return AnyHashable("missing|\(topicID)")
            }
            return AnyHashable(topicRowContentToken(row))
        case .loadingMore:
            return AnyHashable(historyViewModel.isLoadingMore)
        }
    }

    func topicRowContentToken(_ row: FireTopicRowPresentation) -> String {
        let topic = row.topic
        let category = appViewModel.categoryPresentation(for: topic.categoryId)
        var parts: [String] = []
        parts.reserveCapacity(31)
        parts.append(String(topic.id))
        parts.append(topic.title)
        parts.append(topic.slug)
        parts.append(String(topic.postsCount))
        parts.append(String(topic.replyCount))
        parts.append(String(topic.views))
        parts.append(String(topic.likeCount))
        parts.append(topic.excerpt ?? "")
        parts.append(topic.createdAt ?? "")
        parts.append(topic.lastPostedAt ?? "")
        parts.append(topic.lastPosterUsername ?? "")
        parts.append(topic.categoryId.map(String.init) ?? "")
        parts.append(String(topic.pinned))
        parts.append(String(topic.closed))
        parts.append(String(topic.archived))
        parts.append(String(topic.unseen))
        parts.append(String(topic.unreadPosts))
        parts.append(String(topic.newPosts))
        parts.append(topic.lastReadPostNumber.map(String.init) ?? "")
        parts.append(String(topic.highestPostNumber))
        parts.append(topic.bookmarkedPostNumber.map(String.init) ?? "")
        parts.append(topic.bookmarkId.map(String.init) ?? "")
        parts.append(topic.bookmarkName ?? "")
        parts.append(topic.bookmarkReminderAt ?? "")
        parts.append(topic.bookmarkableType ?? "")
        parts.append(row.excerptText ?? "")
        parts.append(row.originalPosterUsername ?? "")
        parts.append(row.originalPosterAvatarTemplate ?? "")
        parts.append(row.tagNames.joined(separator: ","))
        parts.append(row.statusLabels.joined(separator: ","))
        parts.append(category.map { "\($0.id)|\($0.displayName)|\($0.colorHex ?? "")" } ?? "")
        return parts.joined(separator: "\u{1F}")
    }
}
