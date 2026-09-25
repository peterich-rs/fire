import Foundation

extension FireSessionStore {
    public func fetchUserProfile(username: String) async throws -> UserProfileState {
        try await runPersistingSessionChanges {
            try await core.user().fetchUserProfile(username: username)
        }
    }

    public func fetchUserSummary(username: String) async throws -> UserSummaryState {
        try await runPersistingSessionChanges {
            try await core.user().fetchUserSummary(username: username)
        }
    }

    public func fetchUserActions(
        username: String,
        offset: UInt32?,
        filter: String?
    ) async throws -> [UserActionState] {
        try await runPersistingSessionChanges {
            try await core.user().fetchUserActions(username: username, offset: offset, filter: filter)
        }
    }

    public func fetchFollowing(username: String) async throws -> [FollowUserState] {
        try await runPersistingSessionChanges {
            try await core.user().fetchFollowing(username: username)
        }
    }

    public func fetchFollowers(username: String) async throws -> [FollowUserState] {
        try await runPersistingSessionChanges {
            try await core.user().fetchFollowers(username: username)
        }
    }

    public func followUser(username: String) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.user().followUser(username: username)
        }
    }

    public func unfollowUser(username: String) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.user().unfollowUser(username: username)
        }
    }

    public func fetchPendingInvites(username: String) async throws -> [InviteLinkState] {
        try await runPersistingSessionChanges {
            try await core.user().fetchPendingInvites(username: username)
        }
    }

    public func createInviteLink(
        maxRedemptionsAllowed: UInt32,
        expiresAt: String? = nil,
        description: String? = nil,
        email: String? = nil
    ) async throws -> InviteLinkState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.user().createInviteLink(
                input: InviteCreateRequestState(
                    maxRedemptionsAllowed: maxRedemptionsAllowed,
                    expiresAt: expiresAt,
                    description: description,
                    email: email
                )
            )
        }
    }

    public func fetchBadgeDetail(badgeID: UInt64) async throws -> BadgeState {
        try await runPersistingSessionChanges {
            try await core.user().fetchBadgeDetail(badgeId: badgeID)
        }
    }
}
