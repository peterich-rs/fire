package com.fire.app.ui.auth

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fire.app.R
import com.fire.app.session.FireCredentialStore
import com.fire.app.session.FireLastLoginStore
import com.fire.app.session.FireSavedCredential
import com.fire.app.ui.auth.compose.OnboardingEntry
import com.fire.app.ui.auth.compose.OnboardingPhase
import com.fire.app.ui.auth.compose.OnboardingUiState
import kotlinx.coroutines.Job
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
    private val stringResolver: (Int) -> String = { resId -> appContext.getString(resId) },
) : ViewModel() {

    private val _uiState = MutableStateFlow(OnboardingUiState(entry = entry))
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()

    private val _navigationEvents = MutableSharedFlow<LoginNavigationEvent>(extraBufferCapacity = 1)
    val navigationEvents: SharedFlow<LoginNavigationEvent> = _navigationEvents.asSharedFlow()

    private var errorDismissJob: Job? = null
    private var autoLoginJob: Job? = null

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
                _uiState.update {
                    it.copy(
                        phase = OnboardingPhase.Credential,
                        canCancelAutoLogin = false,
                        isAutoLoginInFlight = false,
                    )
                }
            }

            OnboardingEntry.ColdStart, OnboardingEntry.SessionExpired -> {
                _uiState.update {
                    it.copy(
                        phase = OnboardingPhase.Validating,
                        validatingMessage = stringResolver(R.string.onboarding_checking_login_state),
                        validatingDetail = "",
                        canCancelAutoLogin = false,
                        isAutoLoginInFlight = false,
                    )
                }
                autoLoginJob = viewModelScope.launch {
                    delay(VALIDATE_HOLD_MS)
                    if (_uiState.value.phase != OnboardingPhase.Validating) return@launch
                    routeAutoLogin()
                }
            }
        }
    }

    private suspend fun routeAutoLogin() {
        val lastLogin = lastLoginStore.load(appContext)
        val savedCredential = credentialStore.load(appContext)
        _uiState.update {
            it.copy(
                lastLoginMethod = lastLogin,
                identifier = savedCredential?.username ?: it.identifier,
                password = savedCredential?.password ?: it.password,
                rememberPassword = savedCredential != null || it.rememberPassword,
                isLoginEnabled = computeLoginEnabled(
                    savedCredential?.username ?: it.identifier,
                    savedCredential?.password ?: it.password,
                ),
            )
        }

        val kind = FireAutoLoginPlanner.autoLoginKind(
            entry = entry,
            lastLoginMethod = lastLogin,
            savedCredential = savedCredential,
        )

        when (kind) {
            is FireAutoLoginKind.Password -> startPasswordAutoLogin(kind.credential)
            is FireAutoLoginKind.External -> startExternalAutoLogin(kind.method)
            null -> {
                _uiState.update {
                    it.copy(
                        phase = OnboardingPhase.Credential,
                        canCancelAutoLogin = false,
                        isAutoLoginInFlight = false,
                    )
                }
            }
        }
    }

    private suspend fun startPasswordAutoLogin(credential: FireSavedCredential) {
        _uiState.update {
            it.copy(
                phase = OnboardingPhase.LoggingIn,
                validatingMessage = stringResolver(R.string.login_preparing_secure_verification),
                validatingDetail = stringResolver(R.string.login_will_use_saved_password),
                canCancelAutoLogin = true,
                isAutoLoginInFlight = true,
                identifier = credential.username,
                password = credential.password,
                rememberPassword = true,
                isLoginEnabled = true,
                errorMessage = null,
            )
        }
        // Brief window so the host cancel control is usable before captcha surface opens.
        delay(AUTO_LOGIN_CANCEL_WINDOW_MS)
        if (!_uiState.value.isAutoLoginInFlight) return
        if (_uiState.value.phase != OnboardingPhase.LoggingIn) return
        _uiState.update { it.copy(canCancelAutoLogin = false) }
        _navigationEvents.emit(
            LoginNavigationEvent.PasswordCaptcha(
                identifier = credential.username,
                password = credential.password,
                remember = true,
                isAutoLogin = true,
            ),
        )
    }

    private suspend fun startExternalAutoLogin(method: FireExternalLoginMethod) {
        _uiState.update {
            it.copy(
                phase = OnboardingPhase.LoggingIn,
                validatingMessage = externalLoadingMessage(method),
                validatingDetail = stringResolver(R.string.login_secure_connecting),
                canCancelAutoLogin = true,
                isAutoLoginInFlight = true,
                errorMessage = null,
            )
        }
        delay(AUTO_LOGIN_CANCEL_WINDOW_MS)
        if (!_uiState.value.isAutoLoginInFlight) return
        if (_uiState.value.phase != OnboardingPhase.LoggingIn) return
        _uiState.update { it.copy(canCancelAutoLogin = false) }
        when (method) {
            FireExternalLoginMethod.Passkey -> {
                _navigationEvents.emit(LoginNavigationEvent.Passkey(method.name))
            }
            else -> {
                val provider = method.discourseProviderName ?: return
                _navigationEvents.emit(LoginNavigationEvent.OAuth(provider))
            }
        }
    }

    private fun externalLoadingMessage(method: FireExternalLoginMethod): String = when (method) {
        FireExternalLoginMethod.Google -> stringResolver(R.string.login_via_google)
        FireExternalLoginMethod.GitHub -> stringResolver(R.string.login_via_github)
        FireExternalLoginMethod.X -> stringResolver(R.string.login_via_x)
        FireExternalLoginMethod.Discord -> stringResolver(R.string.login_via_discord)
        FireExternalLoginMethod.Apple -> stringResolver(R.string.login_via_apple)
        FireExternalLoginMethod.Passkey -> stringResolver(R.string.login_via_passkey)
    }

    fun onIdentifierChange(value: String) {
        _uiState.update {
            it.copy(identifier = value, isLoginEnabled = computeLoginEnabled(value, it.password))
        }
    }

    fun onPasswordChange(value: String) {
        _uiState.update {
            it.copy(password = value, isLoginEnabled = computeLoginEnabled(it.identifier, value))
        }
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
        _uiState.update {
            it.copy(
                phase = OnboardingPhase.LoggingIn,
                validatingMessage = stringResolver(R.string.login_preparing_verification),
                validatingDetail = "",
                canCancelAutoLogin = false,
                isAutoLoginInFlight = false,
                errorMessage = null,
            )
        }
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
        _uiState.update {
            it.copy(
                phase = OnboardingPhase.LoggingIn,
                validatingMessage = externalLoadingMessage(method),
                validatingDetail = "",
                canCancelAutoLogin = false,
                isAutoLoginInFlight = false,
                errorMessage = null,
            )
        }
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

    private fun scheduleErrorDismiss() {
        errorDismissJob?.cancel()
        errorDismissJob = viewModelScope.launch {
            delay(ERROR_DISMISS_MS)
            _uiState.update { it.copy(errorMessage = null) }
        }
    }

    fun onCancelAutoLogin() {
        if (!_uiState.value.isAutoLoginInFlight) return
        autoLoginJob?.cancel()
        abortLoginAttempt(
            message = stringResolver(R.string.login_auto_login_cancelled),
            wasAutoLogin = true,
        )
    }

    /**
     * Web / captcha surface dismissed without success.
     * @param failureMessage structured failure from the surface; null means user cancel.
     */
    fun onWebSurfaceDismissed(failureMessage: String? = null) {
        val current = _uiState.value
        if (current.phase != OnboardingPhase.LoggingIn && current.phase != OnboardingPhase.Validating) {
            return
        }
        val wasAuto = current.isAutoLoginInFlight
        val message = when {
            !failureMessage.isNullOrBlank() -> failureMessage
            wasAuto -> stringResolver(R.string.login_auto_login_cancelled)
            else -> stringResolver(R.string.login_manual_cancelled)
        }
        abortLoginAttempt(message = message, wasAutoLogin = wasAuto)
    }

    fun onWebSurfaceCancelled() = onWebSurfaceDismissed(failureMessage = null)

    fun onLoginFailure(message: String?) {
        val resolved = message?.takeIf { it.isNotBlank() }
            ?: stringResolver(R.string.login_failed)
        abortLoginAttempt(message = resolved, wasAutoLogin = _uiState.value.isAutoLoginInFlight)
    }

    fun onLoginSucceeded() {
        autoLoginJob?.cancel()
        errorDismissJob?.cancel()
        _uiState.update {
            it.copy(
                isAutoLoginInFlight = false,
                canCancelAutoLogin = false,
                errorMessage = null,
            )
        }
    }

    private fun abortLoginAttempt(message: String?, wasAutoLogin: Boolean) {
        autoLoginJob?.cancel()
        errorDismissJob?.cancel()
        val savedCredential = credentialStore.load(appContext)
        val lastLogin = lastLoginStore.load(appContext)
        _uiState.update {
            it.copy(
                phase = OnboardingPhase.Credential,
                canCancelAutoLogin = false,
                isAutoLoginInFlight = false,
                validatingMessage = "",
                validatingDetail = "",
                lastLoginMethod = lastLogin,
                identifier = if (wasAutoLogin) {
                    savedCredential?.username ?: it.identifier
                } else {
                    it.identifier
                },
                password = if (wasAutoLogin) {
                    savedCredential?.password ?: it.password
                } else {
                    it.password
                },
                rememberPassword = if (wasAutoLogin) {
                    savedCredential != null
                } else {
                    it.rememberPassword
                },
                isLoginEnabled = computeLoginEnabled(
                    if (wasAutoLogin) savedCredential?.username ?: it.identifier else it.identifier,
                    if (wasAutoLogin) savedCredential?.password ?: it.password else it.password,
                ),
                errorMessage = message,
            )
        }
        if (!message.isNullOrBlank()) scheduleErrorDismiss()
    }

    companion object {
        private const val ERROR_DISMISS_MS = 4_000L
        private const val VALIDATE_HOLD_MS = 400L
        private const val AUTO_LOGIN_CANCEL_WINDOW_MS = 600L

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
