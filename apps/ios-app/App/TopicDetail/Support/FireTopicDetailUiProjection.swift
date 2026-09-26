import Foundation

enum FireTopicDetailUiProjection {
    static func posts(from snapshot: FireTopicDetailSnapshot) -> [TopicPostState] {
        snapshot.rows.map(post(from:))
    }

    static func timelineEntry(from row: TopicDetailUiRowState) -> FireTopicTimelineEntry {
        FireTopicTimelineEntry(
            postId: row.postId,
            postNumber: row.postNumber,
            parentPostNumber: row.parentPostNumber,
            depth: UInt32(row.depth),
            isOriginalPost: row.isOriginalPost
        )
    }

    static func post(from row: TopicDetailUiRowState) -> TopicPostState {
        let author = row.author
        return TopicPostState(
            id: row.postId,
            username: author.username,
            name: author.name,
            avatarTemplate: author.avatarTemplate,
            authorMetadata: TopicPostAuthorMetadataState(
                userId: author.userId,
                userTitle: author.userTitle,
                primaryGroupName: author.primaryGroupName,
                flairUrl: author.flairUrl,
                flairName: author.flairName,
                flairBgColor: author.flairBgColor,
                flairColor: author.flairColor,
                flairGroupId: author.flairGroupId,
                moderator: author.moderator,
                admin: author.admin,
                groupModerator: author.groupModerator,
                userStatusEmoji: author.userStatusEmoji,
                userStatusDescription: author.userStatusDescription
            ),
            presentation: row.presentation,
            raw: nil,
            postNumber: row.postNumber,
            postType: row.postType,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            likeCount: row.likeCount,
            replyCount: row.replyCount,
            replyToPostNumber: row.parentPostNumber,
            replyToUser: row.replyToUser.map {
                TopicReplyToUserState(
                    username: $0.username,
                    name: $0.name,
                    avatarTemplate: $0.avatarTemplate
                )
            },
            bookmarked: row.bookmarked,
            bookmarkId: row.bookmarkId,
            bookmarkName: row.bookmarkName,
            bookmarkReminderAt: row.bookmarkReminderAt,
            reactions: row.reactions.map {
                TopicReactionState(id: $0.id, kind: $0.kind, count: $0.count, canUndo: $0.canUndo)
            },
            currentUserReaction: row.currentReactionId.flatMap { id in
                row.reactions.first { $0.id == id }.map {
                    TopicReactionState(id: $0.id, kind: $0.kind, count: $0.count, canUndo: $0.canUndo)
                }
            },
            boosts: row.boosts.map { boost in
                TopicPostBoostState(
                    id: boost.id,
                    presentation: boost.presentation,
                    displayText: boost.displayText,
                    user: TopicPostBoostUserState(
                        id: boost.user.id,
                        username: boost.user.username,
                        name: boost.user.name,
                        avatarTemplate: boost.user.avatarTemplate
                    ),
                    canDelete: boost.canDelete,
                    canFlag: boost.canFlag,
                    userFlagStatus: boost.userFlagStatus,
                    availableFlags: boost.availableFlags
                )
            },
            canBoost: row.canBoost,
            polls: row.polls,
            acceptedAnswer: row.acceptedAnswer,
            canAcceptAnswer: row.canAcceptAnswer,
            canUnacceptAnswer: row.canUnacceptAnswer,
            canEdit: row.canEdit,
            canDelete: row.canDelete,
            canRecover: row.canRecover,
            hidden: row.hidden
        )
    }
}
