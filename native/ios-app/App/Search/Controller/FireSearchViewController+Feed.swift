import UIKit

extension FireSearchViewController {
    func render() {
        let sections = makeSections()
        var tokens: [FireSearchCollectionItem: AnyHashable] = [:]
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
        -> [FireListSectionModel<FireSearchCollectionSection, FireSearchCollectionItem>]
    {
        var items: [FireSearchCollectionItem] = []

        if searchStore.isSearching && searchStore.result == nil {
            items.append(.sectionHeader("话题"))
            items.append(contentsOf: (0..<3).map(FireSearchCollectionItem.loading))
            items.append(.sectionHeader("帖子"))
            items.append(contentsOf: (3..<6).map(FireSearchCollectionItem.loading))
            return [.init(id: .content, items: items)]
        }

        if let result = searchStore.result {
            if let errorMessage = searchStore.errorMessage {
                items.append(.inlineErrorBanner(errorMessage))
            }

            if !result.topics.isEmpty {
                items.append(.sectionHeader("话题"))
                items.append(contentsOf: result.topics.map { .topic($0.id) })
            }

            if !result.posts.isEmpty {
                items.append(.sectionHeader("帖子"))
                items.append(contentsOf: result.posts.map { .post($0.id) })
            }

            if !result.users.isEmpty {
                items.append(.sectionHeader("用户"))
                items.append(contentsOf: result.users.map { .user($0.id) })
            }

            if searchStore.canLoadMoreResults {
                items.append(.loadMore)
            }

            if result.posts.isEmpty && result.topics.isEmpty && result.users.isEmpty {
                items.append(.empty)
            }

            return [.init(id: .content, items: items)]
        }

        if let errorMessage = searchStore.errorMessage {
            items.append(.blockingError(errorMessage))
        } else {
            items.append(.placeholder)
        }

        return [.init(id: .content, items: items)]
    }

    func cell(
        collectionView: UICollectionView,
        indexPath: IndexPath,
        item: FireSearchCollectionItem
    ) -> UICollectionViewCell {
        switch item {
        case .placeholder, .loading, .blockingError, .empty:
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
        case .sectionHeader:
            return collectionView.dequeueConfiguredReusableCell(
                using: sectionHeaderCellRegistration,
                for: indexPath,
                item: item
            )
        case .topic:
            return collectionView.dequeueConfiguredReusableCell(
                using: topicCellRegistration,
                for: indexPath,
                item: item
            )
        case .post:
            return collectionView.dequeueConfiguredReusableCell(
                using: postCellRegistration,
                for: indexPath,
                item: item
            )
        case .user:
            return collectionView.dequeueConfiguredReusableCell(
                using: userCellRegistration,
                for: indexPath,
                item: item
            )
        case .loadMore:
            return collectionView.dequeueConfiguredReusableCell(
                using: loadMoreCellRegistration,
                for: indexPath,
                item: item
            )
        }
    }

    func canSelect(_ item: FireSearchCollectionItem) -> Bool {
        switch item {
        case .topic, .post, .user:
            return true
        case .placeholder, .loading, .blockingError, .inlineErrorBanner, .sectionHeader, .loadMore, .empty:
            return false
        }
    }

    func handleSelection(_ item: FireSearchCollectionItem) {
        switch item {
        case let .topic(topicID):
            guard let topic = topic(for: topicID) else { return }
            let row = topicRow(for: topic)
            presentRoute(.topic(
                topicId: topic.id,
                postNumber: nil,
                preview: FireTopicRoutePreview(row: row)
            ))
        case let .post(postID):
            guard let post = post(for: postID),
                  let row = postRow(for: post, topicIndex: topicIndex)
            else {
                return
            }
            presentRoute(.topic(
                topicId: row.topic.id,
                postNumber: post.postNumber,
                preview: FireTopicRoutePreview(row: row)
            ))
        case let .user(userID):
            guard let user = user(for: userID) else { return }
            presentRoute(.profile(username: user.username))
        case .placeholder, .loading, .blockingError, .inlineErrorBanner, .sectionHeader, .loadMore, .empty:
            break
        }
    }

    func handlePrefetchItems(_ items: [FireSearchCollectionItem]) {
        guard items.contains(.loadMore),
              searchStore.canLoadMoreResults,
              !searchStore.isSearching,
              !searchStore.isAppending
        else {
            return
        }
        searchStore.submit(reset: false)
    }
    func itemContentToken(for item: FireSearchCollectionItem) -> AnyHashable {
        switch item {
        case .placeholder:
            return AnyHashable("placeholder|\(searchStore.query)")
        case let .loading(index):
            return AnyHashable(index)
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case let .sectionHeader(title):
            return AnyHashable(title)
        case let .topic(topicID):
            guard let topic = topic(for: topicID) else {
                return AnyHashable("missing-topic|\(topicID)")
            }
            return AnyHashable(topicContentToken(topic))
        case let .post(postID):
            guard let post = post(for: postID) else {
                return AnyHashable("missing-post|\(postID)")
            }
            return AnyHashable(postContentToken(post))
        case let .user(userID):
            guard let user = user(for: userID) else {
                return AnyHashable("missing-user|\(userID)")
            }
            return AnyHashable(userContentToken(user))
        case .loadMore:
            return AnyHashable("\(searchStore.isAppending)|\(searchStore.canLoadMoreResults)")
        case .empty:
            return AnyHashable("empty|\(searchStore.query)|\(searchStore.scope.rawValue)")
        }
    }

    func topic(for topicID: UInt64) -> SearchTopicState? {
        searchStore.result?.topics.first { $0.id == topicID }
    }

    func post(for postID: UInt64) -> SearchPostState? {
        searchStore.result?.posts.first { $0.id == postID }
    }

    func user(for userID: UInt64) -> SearchUserState? {
        searchStore.result?.users.first { $0.id == userID }
    }
    func postRow(
        for post: SearchPostState,
        topicIndex: [UInt64: SearchTopicState]
    ) -> FireTopicRowPresentation? {
        guard let topicID = post.topicId else {
            return nil
        }
        let topic = topicIndex[topicID]
            ?? SearchTopicState(
                id: topicID,
                title: post.topicTitleHeadline ?? "话题 \(topicID)",
                slug: "",
                categoryId: nil,
                tags: [],
                postsCount: max(post.postNumber, 1),
                views: 0,
                closed: false,
                archived: false
            )
        let excerpt = previewTextFromHtml(rawHtml: post.blurb)
        return topicRow(for: topic, excerptText: excerpt)
    }

    func topicRow(
        for topic: SearchTopicState,
        excerptText: String? = nil
    ) -> FireTopicRowPresentation {
        let statusLabels = {
            var labels: [String] = []
            if topic.closed {
                labels.append("已关闭")
            }
            if topic.archived {
                labels.append("已归档")
            }
            return labels
        }()

        return TopicRowState(
            topic: TopicSummaryState(
                id: topic.id,
                title: topic.title,
                slug: topic.slug,
                postsCount: topic.postsCount,
                replyCount: topic.postsCount > 0 ? topic.postsCount - 1 : 0,
                views: topic.views,
                likeCount: 0,
                excerpt: excerptText,
                createdAt: nil,
                lastPostedAt: nil,
                lastPosterUsername: nil,
                categoryId: topic.categoryId,
                pinned: false,
                visible: true,
                closed: topic.closed,
                archived: topic.archived,
                tags: topic.tags.map { TopicTagState(id: nil, name: $0, slug: nil) },
                posters: [],
                participants: [],
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: nil,
                highestPostNumber: max(topic.postsCount, 1),
                bookmarkedPostNumber: nil,
                bookmarkId: nil,
                bookmarkName: nil,
                bookmarkReminderAt: nil,
                bookmarkableType: nil,
                hasAcceptedAnswer: false,
                canHaveAnswer: false
            ),
            excerptText: excerptText,
            originalPosterUsername: nil,
            originalPosterAvatarTemplate: nil,
            tagNames: topic.tags,
            statusLabels: statusLabels,
            isPinned: false,
            isClosed: topic.closed,
            isArchived: topic.archived,
            hasAcceptedAnswer: false,
            hasUnreadPosts: false,
            createdTimestampUnixMs: nil,
            activityTimestampUnixMs: nil,
            lastPosterUsername: nil
        )
    }

    func topicContentToken(_ topic: SearchTopicState) -> String {
        var components: [String] = []
        components.reserveCapacity(9)
        components.append(String(topic.id))
        components.append(topic.title)
        components.append(topic.slug)
        components.append(topic.categoryId.map(String.init) ?? "")
        components.append(topic.tags.joined(separator: ","))
        components.append(String(topic.postsCount))
        components.append(String(topic.views))
        components.append(String(topic.closed))
        components.append(String(topic.archived))
        return components.joined(separator: "\u{1F}")
    }

    func postContentToken(_ post: SearchPostState) -> String {
        var components: [String] = []
        components.reserveCapacity(10)
        components.append(String(post.id))
        components.append(post.topicId.map(String.init) ?? "")
        components.append(post.username)
        components.append(post.avatarTemplate ?? "")
        components.append(post.createdAt ?? "")
        components.append(post.createdTimestampUnixMs.map(String.init) ?? "")
        components.append(String(post.likeCount))
        components.append(post.blurb)
        components.append(String(post.postNumber))
        components.append(post.topicTitleHeadline ?? "")
        return components.joined(separator: "\u{1F}")
    }

    func userContentToken(_ user: SearchUserState) -> String {
        var components: [String] = []
        components.reserveCapacity(4)
        components.append(String(user.id))
        components.append(user.username)
        components.append(user.name ?? "")
        components.append(user.avatarTemplate ?? "")
        return components.joined(separator: "\u{1F}")
    }
}
