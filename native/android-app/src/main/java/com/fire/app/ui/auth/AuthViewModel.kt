package com.fire.app.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.core.error.FireErrorReporter
import com.fire.app.data.repository.SessionRepository
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireWebViewLoginCoordinator
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_session.SessionState

class AuthViewModel(
    private val sessionRepository: SessionRepository,
    private val sessionStore: FireSessionStore,
) : ViewModel() {

    private val _session = MutableStateFlow<SessionState?>(null)
    val session = _session.asStateFlow()

    private val _isBootstrapping = MutableStateFlow(false)
    val isBootstrapping = _isBootstrapping.asStateFlow()

    private val _isPreparingLogin = MutableStateFlow(false)
    val isPreparingLogin = _isPreparingLogin.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    val isAuthenticated: Boolean
        get() = _session.value?.readiness?.canReadAuthenticatedApi == true

    fun restoreSession() {
        viewModelScope.launch {
            _isBootstrapping.value = true
            _errorMessage.value = null
            try {
                val restored = sessionRepository.restoreSession()
                _session.value = restored
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _errorMessage.value = reportError(e, "auth.restore_session", "恢复会话失败")
            } finally {
                _isBootstrapping.value = false
            }
        }
    }

    fun completeLogin(coordinator: FireWebViewLoginCoordinator, webView: android.webkit.WebView) {
        viewModelScope.launch {
            _isPreparingLogin.value = true
            _errorMessage.value = null
            try {
                val session = coordinator.completeLogin(webView)
                _session.value = session
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _errorMessage.value = reportError(e, "auth.complete_login", "登录失败")
            } finally {
                _isPreparingLogin.value = false
            }
        }
    }

    fun dismissError() {
        _errorMessage.value = null
    }

    fun refreshBootstrap() {
        viewModelScope.launch {
            try {
                val refreshed = sessionRepository.refreshBootstrap()
                _session.value = refreshed
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _errorMessage.value = reportError(e, "auth.refresh_bootstrap", null)
            }
        }
    }

    private fun reportError(error: Exception, operation: String, fallbackMessage: String?): String {
        return FireErrorReporter.report(
            operation = operation,
            error = error,
            sessionStore = sessionStore,
            fallbackMessage = fallbackMessage,
        ).displayMessage
    }

    companion object {
        fun create(sessionStore: FireSessionStore): AuthViewModel {
            val sessionRepo = SessionRepository(sessionStore)
            return AuthViewModel(sessionRepo, sessionStore)
        }
    }
}
