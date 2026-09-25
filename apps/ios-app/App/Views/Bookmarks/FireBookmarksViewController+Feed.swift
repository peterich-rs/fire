import Combine
import SwiftUI
import UIKit

@MainActor
extension FireBookmarksViewController {
    var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var contentVersion: ContentVersion {
        ContentVersion(
            rows: bookmarksViewModel.rows,
            nextPage: bookmarksViewModel.nextPage,
            isLoading: bookmarksViewModel.isLoading,
            isLoadingMore: bookmarksViewModel.isLoadingMore,
            hasLoadedOnce: bookmarksViewModel.hasLoadedOnce,
            errorMessage: bookmarksViewModel.errorMessage
        )
    }

    func render() {
        let sections = makeSections()
        var tokens: [FireBookmarksCollectionItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FireBookmarksCollectionSection, FireBookmarksCollectionItem>]
    {
        var items: [FireBookmarksCollectionItem] = []

        if let errorMessage = bookmarksViewModel.errorMessage,
           bookmarksViewModel.hasLoadedOnce {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if !bookmarksViewModel.hasLoadedOnce {
            if let errorMessage = bookmarksViewModel.errorMessage {
                items.append(.blockingError(errorMessage))
            } else {
                items.append(.loading)
            }
        } else if bookmarksViewModel.rows.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: bookmarksViewModel.rows.map {
                .bookmark(FireBookmarksViewModel.rowID(for: $0))
            })

            if bookmarksViewModel.isLoadingMore {
                items.append(.loadingMore)
            }
        }

        return [.init(id: .content, items: items)]
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireBookmarksCollectionItem
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
        case .bookmark:
            return collectionView.dequeueConfiguredReusableCell(
                using: topicCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    func itemContentToken(for item: FireBookmarksCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(bookmarksViewModel.isLoading)
        case .empty:
            return AnyHashable(bookmarksViewModel.hasLoadedOnce)
        case let .bookmark(id):
            guard let row = bookmarksViewModel.row(for: id) else {
                return AnyHashable("missing|\(id.value)")
            }
            return AnyHashable(bookmarkRowContentToken(row))
        case .loadingMore:
            return AnyHashable(bookmarksViewModel.isLoadingMore)
        }
    }

    func bookmarkRowContentToken(_ row: FireTopicRowPresentation) -> String {
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
