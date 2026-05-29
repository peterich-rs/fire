package com.fire.app.data.repository

import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryState

class UserRepository(private val sessionStore: FireSessionStore) {

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
}
