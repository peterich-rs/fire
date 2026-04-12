import SwiftUI

struct FireAppRouteDestinationView: View {
    let viewModel: FireAppViewModel
    let route: FireAppRoute

    var body: some View {
        switch route {
        case .topic(let topicId, let postNumber):
            FireTopicDetailView(
                viewModel: viewModel,
                row: TopicRowState.stub(
                    topicId: topicId,
                    title: "",
                    slug: "",
                    categoryId: nil
                ),
                scrollToPostNumber: postNumber
            )
        case .profile(let username):
            FirePublicProfileView(viewModel: viewModel, username: username)
        case .badge(let badgeID, _):
            FireBadgeDetailView(viewModel: viewModel, badgeID: badgeID)
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
        TopicRowState(
            topic: TopicSummaryState(
                id: topicId,
                title: title,
                slug: slug,
                postsCount: 0,
                replyCount: 0,
                views: 0,
                likeCount: 0,
                excerpt: nil,
                createdAt: nil,
                lastPostedAt: nil,
                lastPosterUsername: nil,
                categoryId: categoryId,
                pinned: false,
                visible: true,
                closed: false,
                archived: false,
                tags: [],
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
                hasAcceptedAnswer: false,
                canHaveAnswer: false
            ),
            excerptText: nil,
            originalPosterUsername: nil,
            originalPosterAvatarTemplate: nil,
            tagNames: [],
            statusLabels: [],
            isPinned: false,
            isClosed: false,
            isArchived: false,
            hasAcceptedAnswer: false,
            hasUnreadPosts: false,
            createdTimestampUnixMs: nil,
            activityTimestampUnixMs: nil,
            lastPosterUsername: nil
        )
    }
}
