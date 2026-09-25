import Foundation

extension FireSessionStore {
    public func fetchBookmarks(
        username: String,
        page: UInt32? = nil
    ) async throws -> TopicListState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchBookmarks(username: username, page: page)
        }
    }

    public func createBoost(postID: UInt64, raw: String) async throws -> TopicPostBoostState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().createBoost(postId: postID, raw: raw)
        }
    }

    public func deleteBoost(boostID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().deleteBoost(boostId: boostID)
        }
    }

    public func flagPost(
        postID: UInt64,
        flagTypeID: UInt32,
        message: String? = nil
    ) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().flagPost(
                input: PostFlagRequestState(
                    postId: postID,
                    flagTypeId: flagTypeID,
                    message: message
                )
            )
        }
    }

    public func fetchPostActionTypes() async throws -> [PostActionTypeState] {
        try await runPersistingSessionChanges {
            try await core.topics().fetchPostActionTypes()
        }
    }

    public func reportTopicTimings(
        input: TopicTimingsRequestState
    ) async throws -> Bool {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().reportTopicTimings(input: input)
        }
    }

    public func likePost(postID: UInt64) async throws -> PostReactionUpdateState? {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().likePost(postId: postID)
        }
    }

    public func unlikePost(postID: UInt64) async throws -> PostReactionUpdateState? {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().unlikePost(postId: postID)
        }
    }

    public func togglePostReaction(
        postID: UInt64,
        reactionID: String
    ) async throws -> PostReactionUpdateState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().togglePostReaction(postId: postID, reactionId: reactionID)
        }
    }

    public func fetchReactionUsers(postID: UInt64) async throws -> [ReactionUsersGroupState] {
        try await runPersistingSessionChanges {
            try await core.topics().fetchReactionUsers(postId: postID)
        }
    }

    public func votePoll(
        postID: UInt64,
        pollName: String,
        options: [String]
    ) async throws -> PollState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().votePoll(postId: postID, pollName: pollName, options: options)
        }
    }

    public func unvotePoll(
        postID: UInt64,
        pollName: String
    ) async throws -> PollState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().unvotePoll(postId: postID, pollName: pollName)
        }
    }

    public func voteTopic(topicID: UInt64) async throws -> VoteResponseState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().voteTopic(topicId: topicID)
        }
    }

    public func unvoteTopic(topicID: UInt64) async throws -> VoteResponseState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().unvoteTopic(topicId: topicID)
        }
    }

    public func fetchTopicVoters(topicID: UInt64) async throws -> [VotedUserState] {
        try await runPersistingSessionChanges {
            try await core.topics().fetchTopicVoters(topicId: topicID)
        }
    }

    public func createBookmark(
        bookmarkableID: UInt64,
        bookmarkableType: String,
        name: String? = nil,
        reminderAt: String? = nil,
        autoDeletePreference: Int32? = nil
    ) async throws -> UInt64 {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.notifications().createBookmark(
                bookmarkableId: bookmarkableID,
                bookmarkableType: bookmarkableType,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
        }
    }

    public func updateBookmark(
        bookmarkID: UInt64,
        name: String? = nil,
        reminderAt: String? = nil,
        autoDeletePreference: Int32? = nil
    ) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.notifications().updateBookmark(
                bookmarkId: bookmarkID,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
        }
    }

    public func deleteBookmark(bookmarkID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.notifications().deleteBookmark(bookmarkId: bookmarkID)
        }
    }

    public func setTopicNotificationLevel(
        topicID: UInt64,
        notificationLevel: Int32
    ) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.notifications().setTopicNotificationLevel(
                topicId: topicID,
                notificationLevel: notificationLevel
            )
        }
    }
}
