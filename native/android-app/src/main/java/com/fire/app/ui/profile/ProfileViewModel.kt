package com.fire.app.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.data.repository.UserRepository
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryState

class ProfileViewModel(
    private val repository: UserRepository,
    private val sessionStore: FireSessionStore,
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

    private var activeLoadKey: String? = null
    private var loadedProfileKey: String? = null

    fun loadProfile(username: String?) {
        val normalized = username.normalizedUsername()
        val requestKey = normalized?.lowercase() ?: CURRENT_PROFILE_KEY
        if (activeLoadKey == requestKey) return
        if (loadedProfileKey == requestKey && _profile.value != null) return
        if (normalized == null) {
            loadCurrentProfile(requestKey)
        } else {
            loadProfileForUsername(normalized, requestKey)
        }
    }

    private fun loadCurrentProfile(requestKey: String) {
        activeLoadKey = requestKey
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            _profile.value = null
            _summary.value = null
            try {
                val username = repository.currentUsername()
                    ?: throw IllegalStateException("无法确定当前登录用户")
                fetchProfile(username)
                loadedProfileKey = requestKey
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            } finally {
                if (activeLoadKey == requestKey) {
                    activeLoadKey = null
                }
                _isLoading.value = false
            }
        }
    }

    private fun loadProfileForUsername(username: String, requestKey: String) {
        activeLoadKey = requestKey
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            _profile.value = null
            _summary.value = null
            try {
                fetchProfile(username)
                loadedProfileKey = requestKey
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e)
            } finally {
                if (activeLoadKey == requestKey) {
                    activeLoadKey = null
                }
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
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e, showMessage = false)
            }
        }
    }

    private fun handleError(error: Exception, showMessage: Boolean = true) {
        val reported = FireErrorReporter.report(
            operation = "profile.action",
            error = error,
            sessionStore = sessionStore,
        )
        if (reported.isCloudflareChallenge) {
            _cloudflareChallenge.tryEmit(Unit)
            if (showMessage) {
                _error.value = null
            }
        } else if (showMessage) {
            _error.value = reported.displayMessage
        }
    }

    private fun String?.normalizedUsername(): String? {
        val trimmed = this?.trim()
        return trimmed?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
    }

    companion object {
        private const val CURRENT_PROFILE_KEY = "__current__"

        fun create(sessionStore: FireSessionStore): ProfileViewModel {
            val repo = UserRepository(sessionStore)
            return ProfileViewModel(repo, sessionStore)
        }
    }
}
