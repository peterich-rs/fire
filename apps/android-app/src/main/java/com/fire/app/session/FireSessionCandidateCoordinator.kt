package com.fire.app.session

import android.webkit.CookieManager
import uniffi.fire_uniffi_session.SessionCandidateCookiesState
import uniffi.fire_uniffi_session.SessionCandidateHandler

class FireSessionCandidateRuntimeHandler(
    private val sessionStore: FireSessionStore,
) : SessionCandidateHandler {
    override fun sessionCandidateCookies(): SessionCandidateCookiesState {
        val header = runCatching {
            val url = sessionStore.cachedBaseUrl() ?: "https://linux.do"
            CookieManager.getInstance().getCookie(url)
        }.getOrNull()
        val pairs = header
            ?.split(';')
            ?.mapNotNull { part ->
                val trimmed = part.trim()
                val separator = trimmed.indexOf('=')
                if (separator <= 0) {
                    null
                } else {
                    trimmed.substring(0, separator) to trimmed.substring(separator + 1)
                }
            }
            .orEmpty()
        return SessionCandidateCookiesState(
            tToken = pairs.lastOrNull { it.first == "_t" && it.second.isNotBlank() }?.second,
            forumSession = pairs.lastOrNull { it.first == "_forum_session" && it.second.isNotBlank() }?.second,
        )
    }
}
