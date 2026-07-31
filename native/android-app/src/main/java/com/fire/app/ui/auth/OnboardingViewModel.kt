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
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

sealed class LoginNavigationEvent {
    data class PasswordCaptcha(
        val identifier: String,
        val password: String,
        val remember: Boolean,
        val isAutoLogin: Boolean = false,
    ) : LoginNavigationEvent()

    data class OAuth(val provider: String) : LoginNavigationEvent()
    data class Passkey(val provider: String) : LoginNavigationEvent()
    data object ForgotPassword : LoginNavigationEvent()
}

class OnboardingViewModel(
    private val credentialStore: FireCredentialStore,
    private val lastLoginStore: FireLastLoginStore,
    private val appContext: Context,
    private val entry: OnboardingEntry = OnboardingEntry.ColdStart,
) : ViewModel() {

    private val _uiState = MutableStateFlow(OnboardingUiState(entry = entry))
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()

    private val _navigationEvents = MutableSharedFlow<LoginNavigationEvent>(extraBufferCapacity = 1)
    val navigationEvents: SharedFlow<LoginNavigationEvent> = _navigationEvents.asSharedFlow()

    private var errorDismissJob: kotlinx.coroutines.Job? = null
    private var autoLoginJob: kotlinx.coroutines.Job? = null

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
                password = savedCredential?.password ?: "",
                rememberPassword = savedCredential != null,
                isLoginEnabled = savedCredential != null,
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
                autoLoginJob = viewModelScope.launch {
                    delay(800)
                    val savedCredential = credentialStore.load(appContext)
                    if (savedCredential != null) {
                        _uiState.update {
                            it.copy(
                                validatingMessage = "将使用已保存的账号密码",
                                canCancelAutoLogin = true,
                                identifier = savedCredential.username,
                                password = savedCredential.password,
                            )
                        }
                        _navigationEvents.emit(
                            LoginNavigationEvent.PasswordCaptcha(
                                identifier = savedCredential.username,
                                password = savedCredential.password,
                                remember = true,
                                isAutoLogin = true,
                            ),
                        )
                    } else {
                        _uiState.update { it.copy(phase = OnboardingPhase.Credential) }
                    }
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
        _uiState.update { it.copy(phase = OnboardingPhase.LoggingIn, errorMessage = null) }
        viewModelScope.launch {
            _navigationEvents.emit(
                LoginNavigationEvent.PasswordCaptcha(
                    identifier = current.identifier.trim(),
                    password = current.password,
                    remember = current.rememberPassword,
                ),
            )
        }
    }

    fun onForgotPassword() {
        viewModelScope.launch {
            _navigationEvents.emit(LoginNavigationEvent.ForgotPassword)
        }
    }

    fun onExternal(method: FireExternalLoginMethod) {
        val current = _uiState.value
        if (current.phase == OnboardingPhase.LoggingIn) return
        _uiState.update { it.copy(phase = OnboardingPhase.LoggingIn, errorMessage = null) }
        viewModelScope.launch {
            when (method) {
                FireExternalLoginMethod.Passkey -> {
                    _navigationEvents.emit(LoginNavigationEvent.Passkey(method.name))
                }
                else -> {
                    val provider = method.discourseProviderName ?: return@launch
                    _navigationEvents.emit(LoginNavigationEvent.OAuth(provider))
                }
            }
        }
    }

    fun onDismissError() {
        errorDismissJob?.cancel()
        _uiState.update { it.copy(errorMessage = null) }
    }

    fun onCancelAutoLogin() {
        autoLoginJob?.cancel()
        _uiState.update {
            it.copy(
                phase = OnboardingPhase.Credential,
                canCancelAutoLogin = false,
            )
        }
    }

    fun onWebSurfaceCancelled() {
        val current = _uiState.value
        if (current.phase != OnboardingPhase.LoggingIn && current.phase != OnboardingPhase.Validating) return
        errorDismissJob?.cancel()
        _uiState.update {
            it.copy(
                phase = OnboardingPhase.Credential,
                canCancelAutoLogin = false,
                errorMessage = if (current.phase == OnboardingPhase.LoggingIn) "登录未完成，请重试。" else null,
            )
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
