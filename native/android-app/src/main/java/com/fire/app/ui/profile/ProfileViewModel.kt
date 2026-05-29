package com.fire.app.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.data.repository.UserRepository
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.MutableStateFlow
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

    fun loadProfile(username: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            try {
                _profile.value = repository.fetchUserProfile(username)
                _summary.value = repository.fetchUserSummary(username)
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _isLoading.value = false
            }
        }
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
            } catch (_: Exception) { }
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): ProfileViewModel {
            val repo = UserRepository(sessionStore)
            return ProfileViewModel(repo)
        }
    }
}
