import Foundation

struct FireTopicRoutePreview: Hashable {
    let title: String
    let slug: String
    let categoryId: UInt64?
    let tagNames: [String]
    let statusLabels: [String]
    let excerptText: String?
    let isPinned: Bool
    let isClosed: Bool
    let isArchived: Bool
    let hasAcceptedAnswer: Bool
    let hasUnreadPosts: Bool

    init(
        title: String,
        slug: String,
        categoryId: UInt64?,
        tagNames: [String] = [],
        statusLabels: [String] = [],
        excerptText: String? = nil,
        isPinned: Bool = false,
        isClosed: Bool = false,
        isArchived: Bool = false,
        hasAcceptedAnswer: Bool = false,
        hasUnreadPosts: Bool = false
    ) {
        self.title = Self.normalizedText(title) ?? ""
        self.slug = Self.normalizedText(slug) ?? ""
        self.categoryId = categoryId
        self.tagNames = tagNames.compactMap(Self.normalizedText)
        self.statusLabels = statusLabels.compactMap(Self.normalizedText)
        self.excerptText = Self.normalizedText(excerptText)
        self.isPinned = isPinned
        self.isClosed = isClosed
        self.isArchived = isArchived
        self.hasAcceptedAnswer = hasAcceptedAnswer
        self.hasUnreadPosts = hasUnreadPosts
    }

    init(row: TopicRowState) {
        self.init(
            title: row.topic.title,
            slug: row.topic.slug,
            categoryId: row.topic.categoryId,
            tagNames: row.tagNames,
            statusLabels: row.statusLabels,
            excerptText: row.excerptText,
            isPinned: row.isPinned,
            isClosed: row.isClosed,
            isArchived: row.isArchived,
            hasAcceptedAnswer: row.hasAcceptedAnswer,
            hasUnreadPosts: row.hasUnreadPosts
        )
    }

    static func fromMetadata(
        title: String?,
        slug: String?,
        categoryId: UInt64? = nil,
        tagNames: [String] = [],
        statusLabels: [String] = [],
        excerptText: String? = nil,
        isPinned: Bool = false,
        isClosed: Bool = false,
        isArchived: Bool = false,
        hasAcceptedAnswer: Bool = false,
        hasUnreadPosts: Bool = false
    ) -> FireTopicRoutePreview? {
        let normalizedTitle = normalizedText(title) ?? ""
        let normalizedSlug = normalizedText(slug) ?? ""
        let normalizedTagNames = tagNames.compactMap(normalizedText)
        let normalizedStatusLabels = statusLabels.compactMap(normalizedText)
        let normalizedExcerpt = normalizedText(excerptText)
        let hasMetadata = !normalizedTitle.isEmpty
            || !normalizedSlug.isEmpty
            || categoryId != nil
            || !normalizedTagNames.isEmpty
            || !normalizedStatusLabels.isEmpty
            || normalizedExcerpt != nil
            || isPinned
            || isClosed
            || isArchived
            || hasAcceptedAnswer
            || hasUnreadPosts
        guard hasMetadata else {
            return nil
        }

        return FireTopicRoutePreview(
            title: normalizedTitle,
            slug: normalizedSlug,
            categoryId: categoryId,
            tagNames: normalizedTagNames,
            statusLabels: normalizedStatusLabels,
            excerptText: normalizedExcerpt,
            isPinned: isPinned,
            isClosed: isClosed,
            isArchived: isArchived,
            hasAcceptedAnswer: hasAcceptedAnswer,
            hasUnreadPosts: hasUnreadPosts
        )
    }

    func makeTopicRow(topicId: UInt64) -> TopicRowState {
        TopicRowState.routeStub(
            topicId: topicId,
            title: title,
            slug: slug,
            categoryId: categoryId,
            tagNames: tagNames,
            statusLabels: statusLabels,
            excerptText: excerptText,
            isPinned: isPinned,
            isClosed: isClosed,
            isArchived: isArchived,
            hasAcceptedAnswer: hasAcceptedAnswer,
            hasUnreadPosts: hasUnreadPosts
        )
    }

    private static func normalizedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct FireTopicRoutePayload: Hashable {
    let topicId: UInt64
    let postNumber: UInt32?
    let preview: FireTopicRoutePreview?

    var row: TopicRowState {
        preview?.makeTopicRow(topicId: topicId) ?? .routeStub(topicId: topicId)
    }
}

enum FireAppRoute: Hashable, Identifiable {
    case topic(payload: FireTopicRoutePayload)
    case profile(username: String)
    case badge(id: UInt64, slug: String?)

    static func topic(
        topicId: UInt64,
        postNumber: UInt32?,
        preview: FireTopicRoutePreview? = nil
    ) -> FireAppRoute {
        .topic(payload: FireTopicRoutePayload(topicId: topicId, postNumber: postNumber, preview: preview))
    }

    var id: String {
        switch self {
        case .topic(let payload):
            return "topic:\(payload.topicId):\(payload.postNumber.map(String.init) ?? "nil")"
        case .profile(let username):
            return "profile:\(username.lowercased())"
        case .badge(let id, let slug):
            return "badge:\(id):\(slug?.lowercased() ?? "nil")"
        }
    }
}

extension TopicRowState {
    static func stub(
        topicId: UInt64,
        title: String,
        slug: String,
        categoryId: UInt64?
    ) -> TopicRowState {
        routeStub(
            topicId: topicId,
            title: title,
            slug: slug,
            categoryId: categoryId
        )
    }

    static func routeStub(
        topicId: UInt64,
        title: String = "",
        slug: String = "",
        categoryId: UInt64? = nil,
        tagNames: [String] = [],
        statusLabels: [String] = [],
        excerptText: String? = nil,
        isPinned: Bool = false,
        isClosed: Bool = false,
        isArchived: Bool = false,
        hasAcceptedAnswer: Bool = false,
        hasUnreadPosts: Bool = false
    ) -> TopicRowState {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "话题 \(topicId)"
            : title
        return TopicRowState(
            topic: TopicSummaryState(
                id: topicId,
                title: resolvedTitle,
                slug: slug,
                postsCount: 0,
                replyCount: 0,
                views: 0,
                likeCount: 0,
                excerpt: excerptText,
                createdAt: nil,
                lastPostedAt: nil,
                lastPosterUsername: nil,
                categoryId: categoryId,
                pinned: isPinned,
                visible: true,
                closed: isClosed,
                archived: isArchived,
                tags: tagNames.map { TopicTagState(id: nil, name: $0, slug: nil) },
                posters: [],
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: nil,
                highestPostNumber: 0,
                bookmarkedPostNumber: nil,
                bookmarkId: nil,
                bookmarkName: nil,
                bookmarkReminderAt: nil,
                bookmarkableType: nil,
                hasAcceptedAnswer: hasAcceptedAnswer,
                canHaveAnswer: false
            ),
            excerptText: excerptText,
            originalPosterUsername: nil,
            originalPosterAvatarTemplate: nil,
            tagNames: tagNames,
            statusLabels: statusLabels,
            isPinned: isPinned,
            isClosed: isClosed,
            isArchived: isArchived,
            hasAcceptedAnswer: hasAcceptedAnswer,
            hasUnreadPosts: hasUnreadPosts,
            createdTimestampUnixMs: nil,
            activityTimestampUnixMs: nil,
            lastPosterUsername: nil
        )
    }
}
