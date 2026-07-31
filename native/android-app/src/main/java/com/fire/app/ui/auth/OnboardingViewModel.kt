package com.fire.app.ui.auth

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fire.app.session.FireCredentialStore
import com.fire.app.session.FireLastLoginStore
import com.fire.app.ui.auth.compose.OnboardingEntry
import com.fire.app.ui.auth.compose.OnboardingPhase
import com.fire.app.ui.auth.compose.OnboardingUiState
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class OnboardingViewModel(
    private val credentialStore: FireCredentialStore,
    private val lastLoginStore: FireLastLoginStore,
    private val appContext: Context,
    private val entry: OnboardingEntry = OnboardingEntry.ColdStart,
) : ViewModel() {

    private val _uiState = MutableStateFlow(OnboardingUiState(entry = entry))
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()

    private var errorDismissJob: kotlinx.coroutines.Job? = null

    init {
        loadPersistedState()
        startPhaseForEntry()
    }

    private fun loadPersistedState() {
        val lastLogin = lastLoginStore.load(appContext)
        val savedCredential = credentialStore.load(appContext)
        _uiState.update { current ->
            current.copy(
                lastLoginMethod = lastLogin,
                identifier = savedCredential?.username ?: "",
                rememberPassword = savedCredential != null,
            )
        }
    }

    private fun startPhaseForEntry() {
        when (entry) {
            OnboardingEntry.SignedOut -> {
                _uiState.update { it.copy(phase = OnboardingPhase.Credential) }
            }

            OnboardingEntry.ColdStart, OnboardingEntry.SessionExpired -> {
                _uiState.update {
                    it.copy(
                        phase = OnboardingPhase.Validating,
                        validatingMessage = "",
                        canCancelAutoLogin = false,
                    )
                }
                viewModelScope.launch {
                    delay(1000)
                    _uiState.update { it.copy(phase = OnboardingPhase.Credential) }
                }
            }
        }
    }

    fun onIdentifierChange(value: String) {
        _uiState.update { it.copy(identifier = value, isLoginEnabled = computeLoginEnabled(value, it.password)) }
    }

    fun onPasswordChange(value: String) {
        _uiState.update { it.copy(password = value, isLoginEnabled = computeLoginEnabled(it.identifier, value)) }
    }

    private fun computeLoginEnabled(identifier: String, password: String): Boolean =
        identifier.isNotBlank() && password.isNotBlank()

    fun onTogglePasswordVisibility() {
        _uiState.update { it.copy(isPasswordVisible = !it.isPasswordVisible) }
    }

    fun onToggleRemember() {
        _uiState.update { it.copy(rememberPassword = !it.rememberPassword) }
    }

    fun onLogin() {
        val current = _uiState.value
        if (!current.isLoginEnabled || current.phase == OnboardingPhase.LoggingIn) return
        _uiState.update { it.copy(phase = OnboardingPhase.LoggingIn) }
        viewModelScope.launch {
            delay(2000)
            _uiState.update {
                it.copy(
                    phase = OnboardingPhase.Credential,
                    errorMessage = "登录测试占位 — 真实登录将在 Batch D 接入。",
                )
            }
            scheduleErrorDismiss()
        }
    }

    fun onForgotPassword() {
        // TODO: open forgot password URL — Batch D
    }

    fun onExternal(method: FireExternalLoginMethod) {
        // TODO: route to WebView login for provider — Batch D
    }

    fun onDismissError() {
        errorDismissJob?.cancel()
        _uiState.update { it.copy(errorMessage = null) }
    }

    fun onCancelAutoLogin() {
        _uiState.update {
            it.copy(
                phase = OnboardingPhase.Credential,
                canCancelAutoLogin = false,
            )
        }
    }

    private fun scheduleErrorDismiss() {
        errorDismissJob?.cancel()
        errorDismissJob = viewModelScope.launch {
            delay(4000)
            _uiState.update { it.copy(errorMessage = null) }
        }
    }

    companion object {
        fun factory(
            context: Context,
            entry: OnboardingEntry = OnboardingEntry.ColdStart,
        ): ViewModelProvider.Factory = OnboardingViewModelFactory(context.applicationContext, entry)
    }
}

private class OnboardingViewModelFactory(
    private val appContext: Context,
    private val entry: OnboardingEntry,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(OnboardingViewModel::class.java)) {
            return OnboardingViewModel(
                credentialStore = FireCredentialStore,
                lastLoginStore = FireLastLoginStore,
                appContext = appContext,
                entry = entry,
            ) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
    }
}
