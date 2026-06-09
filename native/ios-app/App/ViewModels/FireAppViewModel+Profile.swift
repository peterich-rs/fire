import Foundation

@MainActor
extension FireAppViewModel {
    func fetchUserProfile(username: String) async throws -> UserProfileState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchUserProfile(username: username)
    }

    func fetchUserSummary(username: String) async throws -> UserSummaryState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchUserSummary(username: username)
    }

    func fetchUserActions(
        username: String,
        offset: UInt32?,
        filter: String?
    ) async throws -> [UserActionState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchUserActions(
            username: username,
            offset: offset,
            filter: filter
        )
    }

    func fetchBookmarks(
        username: String,
        page: UInt32? = nil
    ) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchBookmarks(username: username, page: page)
    }

    func fetchFollowing(username: String) async throws -> [FollowUserState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchFollowing(username: username)
    }

    func fetchFollowers(username: String) async throws -> [FollowUserState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchFollowers(username: username)
    }

    func followUser(username: String) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.followUser(username: username)
        }
    }

    func unfollowUser(username: String) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.unfollowUser(username: username)
        }
    }

    func fetchPendingInvites(username: String) async throws -> [InviteLinkState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchPendingInvites(username: username)
    }

    func createInviteLink(
        maxRedemptionsAllowed: UInt32,
        expiresAt: String? = nil,
        description: String? = nil,
        email: String? = nil
    ) async throws -> InviteLinkState {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.createInviteLink(
                maxRedemptionsAllowed: maxRedemptionsAllowed,
                expiresAt: expiresAt,
                description: description,
                email: email
            )
        }
    }

    func fetchBadgeDetail(badgeID: UInt64) async throws -> BadgeState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchBadgeDetail(badgeID: badgeID)
    }

    func ldcAuthorizationUrl() async throws -> LdcAuthorizationUrlState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.ldcAuthorizationUrl()
    }

    func ldcApprovalLink(authorizationURL: String) async throws -> String {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.ldcApprovalLink(authorizationURL: authorizationURL)
    }

    func ldcApprove(approvePath: String) async throws -> LdcApprovalStatusState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.ldcApprove(approvePath: approvePath)
    }

    func ldcCallback(code: String, state: String) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.ldcCallback(code: code, state: state)
    }

    func ldcUserInfo() async throws -> LdcUserInfoState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.ldcUserInfo()
    }

    func ldcLogout() async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.ldcLogout()
    }

    func cdkAuthorizationUrl() async throws -> CdkAuthorizationUrlState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.cdkAuthorizationUrl()
    }

    func cdkApprovalLink(authorizationURL: String) async throws -> String {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.cdkApprovalLink(authorizationURL: authorizationURL)
    }

    func cdkApprove(approvePath: String) async throws -> LdcApprovalStatusState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.cdkApprove(approvePath: approvePath)
    }

    func cdkCallback(code: String, state: String) async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.cdkCallback(code: code, state: state)
    }

    func cdkUserInfo() async throws -> CdkUserInfoState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.cdkUserInfo()
    }

    func cdkLogout() async throws {
        let sessionStore = try await sessionStoreValue()
        try await sessionStore.cdkLogout()
    }
}
