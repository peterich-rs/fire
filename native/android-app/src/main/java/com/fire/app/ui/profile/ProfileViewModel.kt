package com.fire.app.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.cloudflare.CloudflareChallengeDetector
import com.fire.app.data.repository.UserRepository
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryState

class ProfileViewModel(
    private val repository: UserRepository,
) : ViewModel() {

    private val _profile = MutableStateFlow<UserProfileState?>(null)
    val profile = _profile.asStateFlow()

    private val _summary = MutableStateFlow<UserSummaryState?>(null)
    val summary = _summary.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private val _cloudflareChallenge = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val cloudflareChallenge = _cloudflareChallenge.asSharedFlow()

    fun loadProfile(username: String?) {
        val normalized = username.normalizedUsername()
        if (normalized == null) {
            loadCurrentProfile()
        } else {
            loadProfileForUsername(normalized)
        }
    }

    fun loadCurrentProfile() {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            _profile.value = null
            _summary.value = null
            try {
                val username = repository.currentUsername()
                    ?: throw IllegalStateException("无法确定当前登录用户")
                fetchProfile(username)
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun loadProfileForUsername(username: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            _profile.value = null
            _summary.value = null
            try {
                fetchProfile(username)
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    private suspend fun fetchProfile(username: String) {
        _profile.value = repository.fetchUserProfile(username)
        _summary.value = repository.fetchUserSummary(username)
    }

    fun toggleFollow() {
        val profile = _profile.value ?: return
        viewModelScope.launch {
            try {
                if (profile.isFollowed) {
                    repository.unfollowUser(profile.username)
                } else {
                    repository.followUser(profile.username)
                }
                _profile.value = repository.fetchUserProfile(profile.username)
            } catch (e: Exception) {
                handleError(e, showMessage = false)
            }
        }
    }

    private fun handleError(error: Exception, showMessage: Boolean = true) {
        if (CloudflareChallengeDetector.isChallenge(error)) {
            _cloudflareChallenge.tryEmit(Unit)
            if (showMessage) {
                _error.value = null
            }
        } else if (showMessage) {
            _error.value = error.message
        }
    }

    private fun String?.normalizedUsername(): String? {
        val trimmed = this?.trim()
        return trimmed?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): ProfileViewModel {
            val repo = UserRepository(sessionStore)
            return ProfileViewModel(repo)
        }
    }
}
