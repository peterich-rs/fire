import Foundation

@MainActor
final class FireTopicInteractionService {
    private let host: FireAppServiceHost

    init(host: FireAppServiceHost) {
        self.host = host
    }

    func setPostLiked(
        topicId: UInt64,
        postId: UInt64,
        liked: Bool
    ) async throws {
        guard let topicDetailStore = host.topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        try await topicDetailStore.setPostLiked(
            topicId: topicId,
            postId: postId,
            liked: liked
        )
    }

    func togglePostReaction(
        topicId: UInt64,
        postId: UInt64,
        reactionId: String
    ) async throws {
        guard let topicDetailStore = host.topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        try await topicDetailStore.togglePostReaction(
            topicId: topicId,
            postId: postId,
            reactionId: reactionId
        )
    }

    func fetchReactionUsers(postID: UInt64) async throws -> [ReactionUsersGroupState] {
        let sessionStore = try await host.sessionStoreValue()
        return try await sessionStore.fetchReactionUsers(postID: postID)
    }

    func votePoll(
        topicID: UInt64,
        postID: UInt64,
        pollName: String,
        options: [String],
        recoveryOriginURL: URL? = nil
    ) async throws -> PollState {
        let sessionStore = try await host.sessionStoreValue()
        guard host.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard host.topicDetailStore?.isMutatingPost(postId: postID) != true else {
            throw FireTopicInteractionError.unavailable
        }

        do {
            host.clearErrorMessage()
            let poll = try await host.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
                try await sessionStore.votePoll(
                    postID: postID,
                    pollName: pollName,
                    options: options
                )
            }
            await host.topicDetailStore?.refreshTopicDetailAfterMutation(topicId: topicID)
            return poll
        } catch {
            _ = await host.handleInteractionError(error)
            throw error
        }
    }

    func unvotePoll(
        topicID: UInt64,
        postID: UInt64,
        pollName: String,
        recoveryOriginURL: URL? = nil
    ) async throws -> PollState {
        let sessionStore = try await host.sessionStoreValue()
        guard host.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard host.topicDetailStore?.isMutatingPost(postId: postID) != true else {
            throw FireTopicInteractionError.unavailable
        }

        do {
            host.clearErrorMessage()
            let poll = try await host.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
                try await sessionStore.unvotePoll(postID: postID, pollName: pollName)
            }
            await host.topicDetailStore?.refreshTopicDetailAfterMutation(topicId: topicID)
            return poll
        } catch {
            _ = await host.handleInteractionError(error)
            throw error
        }
    }

    func voteTopic(
        topicID: UInt64,
        voted: Bool,
        recoveryOriginURL: URL? = nil
    ) async throws -> VoteResponseState {
        let sessionStore = try await host.sessionStoreValue()
        guard host.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            host.clearErrorMessage()
            let response = try await host.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
                if voted {
                    try await sessionStore.voteTopic(topicID: topicID)
                } else {
                    try await sessionStore.unvoteTopic(topicID: topicID)
                }
            }
            await host.topicDetailStore?.refreshTopicDetailAfterMutation(topicId: topicID)
            return response
        } catch {
            _ = await host.handleInteractionError(error)
            throw error
        }
    }

    func fetchTopicVoters(topicID: UInt64) async throws -> [VotedUserState] {
        let sessionStore = try await host.sessionStoreValue()
        return try await sessionStore.fetchTopicVoters(topicID: topicID)
    }

    func reportTopicTimings(
        topicId: UInt64,
        topicTimeMs: UInt32,
        timings: [UInt32: UInt32]
    ) async -> Bool {
        let sessionStore: FireSessionStore
        do {
            sessionStore = try await host.sessionStoreValue()
        } catch {
            return false
        }
        guard host.canStartAuthenticatedMutation else { return false }
        guard topicTimeMs > 0 else { return true }

        let timingEntries = timings
            .filter { $0.key > 0 && $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { postNumber, milliseconds in
                TopicTimingEntryState(
                    postNumber: postNumber,
                    milliseconds: milliseconds
                )
            }
        guard !timingEntries.isEmpty else { return true }

        do {
            let accepted = try await sessionStore.reportTopicTimings(
                input: TopicTimingsRequestState(
                    topicId: topicId,
                    topicTimeMs: topicTimeMs,
                    timings: timingEntries
                )
            )
            return accepted
        } catch {
            _ = await host.handleRecoverableSessionErrorIfNeeded(error)
            return false
        }
    }

    func createBookmark(
        bookmarkableID: UInt64,
        bookmarkableType: String,
        name: String? = nil,
        reminderAt: String? = nil,
        autoDeletePreference: Int32? = nil,
        recoveryOriginURL: URL? = nil
    ) async throws -> UInt64 {
        let sessionStore = try await host.sessionStoreValue()
        return try await host.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
            try await sessionStore.createBookmark(
                bookmarkableID: bookmarkableID,
                bookmarkableType: bookmarkableType,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
        }
    }

    func updateBookmark(
        bookmarkID: UInt64,
        name: String? = nil,
        reminderAt: String? = nil,
        autoDeletePreference: Int32? = nil,
        recoveryOriginURL: URL? = nil
    ) async throws {
        let sessionStore = try await host.sessionStoreValue()
        try await host.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
            try await sessionStore.updateBookmark(
                bookmarkID: bookmarkID,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
        }
    }

    func deleteBookmark(bookmarkID: UInt64, recoveryOriginURL: URL? = nil) async throws {
        let sessionStore = try await host.sessionStoreValue()
        try await host.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
            try await sessionStore.deleteBookmark(bookmarkID: bookmarkID)
        }
    }

    func setTopicNotificationLevel(
        topicID: UInt64,
        notificationLevel: Int32,
        recoveryOriginURL: URL? = nil
    ) async throws {
        let sessionStore = try await host.sessionStoreValue()
        try await host.performWriteWithCloudflareRetry(originURL: recoveryOriginURL) {
            try await sessionStore.setTopicNotificationLevel(
                topicID: topicID,
                notificationLevel: notificationLevel
            )
        }
    }
}
