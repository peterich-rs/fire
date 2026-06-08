import Foundation

// MARK: - Composer Contexts

struct FireReplyComposerContext: Identifiable, Equatable {
    let topicId: UInt64
    let postId: UInt64?
    let replyToPostNumber: UInt32?
    let replyToUsername: String?

    var id: String {
        "\(topicId)-\(postId ?? 0)-\(replyToPostNumber ?? 0)"
    }

    var targetSummary: String {
        if let replyToUsername, !replyToUsername.isEmpty {
            return "回复 \(replyToUsername)"
        }
        if let replyToPostNumber {
            return "回复 #\(replyToPostNumber)"
        }
        return "回复话题"
    }

    var placeholder: String {
        if let replyToUsername, !replyToUsername.isEmpty {
            return "回复\(replyToUsername):"
        }
        return "快速回复…"
    }
}

// MARK: - Post Management Contexts

struct FirePostEditorContext: Identifiable, Equatable {
    let postID: UInt64
    let postNumber: UInt32

    var id: UInt64 { postID }
}

struct FirePostManagementContext: Identifiable, Equatable {
    let postID: UInt64
    let postNumber: UInt32
    let username: String?

    var id: UInt64 { postID }

    init(postID: UInt64, postNumber: UInt32, username: String? = nil) {
        self.postID = postID
        self.postNumber = postNumber
        self.username = username
    }
}

struct FirePostReplyContext: Identifiable {
    let post: TopicPostState

    var id: UInt64 { post.id }
}

// MARK: - Navigation Route Contexts

struct FireTopicFilterRoute: Identifiable, Hashable {
    let title: String
    let categorySlug: String?
    let categoryId: UInt64?
    let parentCategorySlug: String?
    let tag: String?

    var id: String {
        [
            categoryId.map { "category:\($0)" },
            tag.map { "tag:\($0)" },
            title,
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    static func category(_ category: FireTopicCategoryPresentation) -> Self {
        Self(
            title: category.displayName,
            categorySlug: category.slug,
            categoryId: category.id,
            parentCategorySlug: nil,
            tag: nil
        )
    }

    static func tag(_ tagName: String) -> Self {
        Self(
            title: "#\(tagName)",
            categorySlug: nil,
            categoryId: nil,
            parentCategorySlug: nil,
            tag: tagName
        )
    }
}

// MARK: - Runtime Invalidation Tokens

struct FireTopicDetailFeedInvalidationToken: Hashable {
    let topicID: UInt64
    let topicCollectionRevision: UInt64
    let pendingScrollTarget: UInt32?
    let detailError: String
    let detailNotice: FireTopicDetailStatusMessage?
    let hasDetail: Bool
    let isLoadingTopic: Bool
    let isLoadingMoreTopicPosts: Bool
    let loadMoreTopicPostsError: String
    let hasMoreTopicPosts: Bool
    let canWriteInteractions: Bool
    let currentUsername: String
    let baseURLString: String
    let expandedReplyRootPostIDs: Set<UInt64>
}

struct FireTopicDetailChromeInvalidationToken: Hashable {
    let topicID: UInt64
    let title: String
    let slug: String
    let bookmarked: Bool
    let canWriteInteractions: Bool
    let canEditTopic: Bool
    let archetype: String?
    let notificationLevel: Int32?
    let baseURLString: String
}

struct FireTopicDetailComposerInvalidationToken: Hashable {
    let canWriteInteractions: Bool
    let typingUsernames: [String]
    let composerContextID: String?
    let replyDraft: String
    let quickReplyError: String?
    let isSubmittingReply: Bool
    let minimumReplyLength: Int
}

struct FireTopicDetailSidecarInvalidationToken: Hashable {
    let topicAiSummaryToken: String
    let isLoadingTopicAiSummary: Bool
    let topicAiSummaryError: String
}

struct FireTopicDetailInteractionInvalidationToken: Hashable {
    let mutatingPostIDs: Set<UInt64>
    let loadingPostReplyContextIDs: Set<UInt64>
    let postReplyContextErrorIDs: [UInt64]
    let expandedPostTextIDs: Set<UInt64>
    let expandedReplyRootPostIDs: Set<UInt64>
}

// MARK: - Topic Notification Level

enum FireTopicNotificationLevelOption: Int32, CaseIterable, Identifiable {
    case muted = 0
    case regular = 1
    case tracking = 2
    case watching = 3

    var id: Int32 { rawValue }

    var title: String {
        switch self {
        case .muted: "静音"
        case .regular: "普通"
        case .tracking: "跟踪"
        case .watching: "关注"
        }
    }
}
