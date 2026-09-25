package com.fire.app.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.data.repository.UserRepository
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_user.UserActionState
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

    private val _actions = MutableStateFlow<List<UserActionState>>(emptyList())
    val actions = _actions.asStateFlow()

    private val _actionsLoading = MutableStateFlow(false)
    val actionsLoading = _actionsLoading.asStateFlow()

    private val _hasLoadedActionsOnce = MutableStateFlow(false)
    val hasLoadedActionsOnce = _hasLoadedActionsOnce.asStateFlow()

    private val _selfUsername = MutableStateFlow<String?>(null)
    val selfUsername = _selfUsername.asStateFlow()

    private var activeLoadKey: String? = null
    private var loadedProfileKey: String? = null
    private var loadedActionsUsername: String? = null

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
                _selfUsername.value = username
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
                if (_selfUsername.value == null) {
                    _selfUsername.value = repository.currentUsername()
                }
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
        loadActions(username, force = loadedActionsUsername != username.lowercase())
    }

    fun loadActions(username: String, force: Boolean = false) {
        val key = username.trim().lowercase()
        if (!force && loadedActionsUsername == key && _actions.value.isNotEmpty()) return
        if (_actionsLoading.value) return
        viewModelScope.launch {
            _actionsLoading.value = true
            try {
                val fetched = repository.fetchUserActions(username = username, offset = 0u)
                _actions.value = fetched
                loadedActionsUsername = key
                _hasLoadedActionsOnce.value = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e, showMessage = _actions.value.isEmpty())
                _hasLoadedActionsOnce.value = true
            } finally {
                _actionsLoading.value = false
            }
        }
    }

    fun loadMoreActions() {
        val profile = _profile.value ?: return
        if (_actionsLoading.value) return
        viewModelScope.launch {
            _actionsLoading.value = true
            try {
                val offset = _actions.value.size.toUInt()
                val more = repository.fetchUserActions(username = profile.username, offset = offset)
                if (more.isNotEmpty()) {
                    _actions.value = _actions.value + more
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                handleError(e, showMessage = false)
            } finally {
                _actionsLoading.value = false
            }
        }
    }

    fun refresh(username: String?) {
        loadedProfileKey = null
        loadedActionsUsername = null
        loadProfile(username)
    }

    fun dismissError() {
        _error.value = null
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
        if (showMessage) {
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
