package com.fire.app.data.repository

import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import uniffi.fire_uniffi_session.SessionState

class SessionRepository(private val sessionStore: FireSessionStore) {

    private val _session = MutableStateFlow<SessionState?>(null)
    val session: Flow<SessionState?> = _session.asStateFlow()

    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: Flow<Boolean> = _isAuthenticated.asStateFlow()

    suspend fun restoreSession(): SessionState? = withContext(Dispatchers.IO) {
        val restored = sessionStore.restorePersistedSessionIfAvailable()
        if (restored != null) {
            val refreshed = sessionStore.refreshBootstrapIfNeeded()
            _session.value = refreshed
            _isAuthenticated.value = refreshed.readiness.canReadAuthenticatedApi
        }
        _session.value
    }

    suspend fun refreshCsrfIfNeeded(): SessionState = withContext(Dispatchers.Default) {
        val current = _session.value ?: sessionStore.snapshot()
        if (current.readiness.canReadAuthenticatedApi && !current.readiness.hasCsrfToken) {
            val refreshed = sessionStore.refreshCsrfTokenIfNeeded()
            _session.value = refreshed
            _isAuthenticated.value = refreshed.readiness.canReadAuthenticatedApi
            refreshed
        } else {
            current
        }
    }

    suspend fun refreshBootstrap(): SessionState = withContext(Dispatchers.Default) {
        val refreshed = sessionStore.refreshBootstrapIfNeeded()
        _session.value = refreshed
        _isAuthenticated.value = refreshed.readiness.canReadAuthenticatedApi
        refreshed
    }

    suspend fun snapshot(): SessionState = withContext(Dispatchers.Default) {
        val snap = sessionStore.snapshot()
        _session.value = snap
        _isAuthenticated.value = snap.readiness.canReadAuthenticatedApi
        snap
    }

    fun currentSession(): SessionState? = _session.value
}
