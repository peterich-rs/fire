import Combine
import SwiftUI
import UIKit

@MainActor
extension FirePrivateMessagesViewController {
    var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var contentVersion: ContentVersion {
        ContentVersion(
            selectedKind: Self.kindIdentifier(mailboxViewModel.selectedKind),
            renderedKind: mailboxViewModel.renderedKind.map(Self.kindIdentifier(_:)),
            rowIDs: mailboxViewModel.displayedRows.map(\.topic.id),
            userIDs: mailboxViewModel.displayedUsers.map(\.id),
            isLoading: mailboxViewModel.isLoading,
            isLoadingMore: mailboxViewModel.isLoadingMore,
            hasLoadedOnce: mailboxViewModel.hasLoadedOnce,
            errorMessage: mailboxViewModel.errorMessage
        )
    }

    var nonBlockingErrorMessage: String? {
        switch mailboxViewModel.currentKindDisplayState {
        case .empty(let message), .content(let message):
            return message
        case .loading, .blockingError:
            return nil
        }
    }

    func render() {
        let sections = makeSections()
        var tokens: [FirePrivateMessagesCollectionItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FirePrivateMessagesCollectionSection, FirePrivateMessagesCollectionItem>]
    {
        var sections: [FireListSectionModel<FirePrivateMessagesCollectionSection, FirePrivateMessagesCollectionItem>] = [
            .init(id: .controls, items: [.mailboxPicker]),
        ]

        var contentItems: [FirePrivateMessagesCollectionItem] = []
        if let errorMessage = nonBlockingErrorMessage {
            contentItems.append(.inlineErrorBanner(errorMessage))
        }

        switch mailboxViewModel.currentKindDisplayState {
        case .loading:
            contentItems.append(.loading)
        case let .blockingError(message):
            contentItems.append(.blockingError(message))
        case .empty:
            contentItems.append(.empty)
        case .content:
            contentItems.append(contentsOf: mailboxViewModel.displayedRows.map { .message($0.topic.id) })
            if mailboxViewModel.isLoadingMore {
                contentItems.append(.loadingMore)
            }
        }

        sections.append(.init(id: .content, items: contentItems))
        return sections
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FirePrivateMessagesCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .mailboxPicker:
            return collectionView.dequeueConfiguredReusableCell(
                using: pickerCellRegistration,
                for: indexPath,
                item: item
            )
        case .inlineErrorBanner:
            return collectionView.dequeueConfiguredReusableCell(
                using: bannerCellRegistration,
                for: indexPath,
                item: item
            )
        case .loading, .blockingError, .empty, .loadingMore:
            return collectionView.dequeueConfiguredReusableCell(
                using: stateCellRegistration,
                for: indexPath,
                item: item
            )
        case .message:
            return collectionView.dequeueConfiguredReusableCell(
                using: messageCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    func itemContentToken(for item: FirePrivateMessagesCollectionItem) -> AnyHashable {
        switch item {
        case .mailboxPicker:
            return AnyHashable(mailboxViewModel.selectedKind)
        case let .inlineErrorBanner(message), let .blockingError(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(mailboxViewModel.isLoading)
        case .empty:
            return AnyHashable("\(Self.kindIdentifier(mailboxViewModel.selectedKind))|\(mailboxViewModel.hasLoadedOnce)")
        case let .message(topicID):
            guard let row = row(topicID: topicID) else {
                return AnyHashable("missing|\(topicID)")
            }
            return AnyHashable(MessageContentToken(
                topicID: topicID,
                title: row.topic.title,
                replyCount: row.topic.replyCount,
                excerptText: row.excerptText,
                activityTimestampUnixMs: row.activityTimestampUnixMs,
                participants: resolvedParticipants(for: row.topic).map {
                    ParticipantToken(
                        userID: $0.userId,
                        username: $0.username,
                        name: $0.name,
                        avatarTemplate: $0.avatarTemplate
                    )
                }
            ))
        case .loadingMore:
            return AnyHashable(mailboxViewModel.isLoadingMore)
        }
    }

    static func kindIdentifier(_ kind: TopicListKindState) -> String {
        String(describing: kind)
    }

    func row(topicID: UInt64) -> TopicRowState? {
        mailboxViewModel.displayedRows.first { $0.topic.id == topicID }
    }
}
