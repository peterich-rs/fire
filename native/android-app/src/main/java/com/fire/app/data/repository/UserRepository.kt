package com.fire.app.data.repository

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_user.BadgeState
import uniffi.fire_uniffi_user.FollowUserState
import uniffi.fire_uniffi_user.InviteCreateRequestState
import uniffi.fire_uniffi_user.InviteLinkState
import uniffi.fire_uniffi_user.UserActionState
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryState

class UserRepository(private val sessionStore: FireSessionStore) {

    suspend fun currentUsername(): String? =
        withContext(Dispatchers.IO) {
            val refreshed = sessionStore.refreshBootstrapIfNeeded()
            refreshed.bootstrap.currentUsername.normalizedUsername()
                ?: sessionStore.refreshBootstrap().bootstrap.currentUsername.normalizedUsername()
        }

    suspend fun fetchUserProfile(username: String): UserProfileState =
        withContext(Dispatchers.IO) {
            sessionStore.fetchUserProfile(username)
        }

    suspend fun fetchUserSummary(username: String): UserSummaryState =
        withContext(Dispatchers.IO) {
            sessionStore.fetchUserSummary(username)
        }

    suspend fun followUser(username: String) = withContext(Dispatchers.IO) {
        sessionStore.followUser(username)
    }

    suspend fun unfollowUser(username: String) = withContext(Dispatchers.IO) {
        sessionStore.unfollowUser(username)
    }

    suspend fun fetchFollowing(username: String): List<FollowUserState> =
        sessionStore.fetchFollowing(username)

    suspend fun fetchFollowers(username: String): List<FollowUserState> =
        sessionStore.fetchFollowers(username)

    suspend fun fetchUserActions(
        username: String,
        offset: UInt? = null,
        filter: String? = null,
    ): List<UserActionState> = sessionStore.fetchUserActions(username, offset, filter)

    suspend fun fetchBadgeDetail(badgeId: ULong): BadgeState =
        sessionStore.fetchBadgeDetail(badgeId)

    suspend fun fetchPendingInvites(username: String): List<InviteLinkState> =
        sessionStore.fetchPendingInvites(username)

    suspend fun createInviteLink(input: InviteCreateRequestState): InviteLinkState =
        sessionStore.createInviteLink(input)

    private fun String?.normalizedUsername(): String? {
        val trimmed = this?.trim()
        return trimmed?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
    }
}
