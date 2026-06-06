package com.fire.app.session

import android.webkit.CookieManager
import android.webkit.WebView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject
import kotlin.coroutines.resume
import uniffi.fire_uniffi_session.LoginPhaseState
import uniffi.fire_uniffi_session.PlatformCookieState
import uniffi.fire_uniffi_session.SessionState

data class FireLoginSyncReadiness(
    val isReady: Boolean,
    val username: String?,
    val hasAuthCookies: Boolean,
    val hasBootstrapHtml: Boolean,
    val preferredBootstrapScore: Int,
)

class FireWebViewLoginCoordinator(
    private val sessionStore: FireSessionStore,
    private val loginBaseUrl: String = "https://linux.do",
) {
    suspend fun restorePersistedSessionIfAvailable(): SessionState? {
        return sessionStore.restorePersistedSessionIfAvailable()
    }

    suspend fun completeLogin(webView: WebView): SessionState {
        val captured = captureLoginState(webView)
        val readiness = loginSyncReadiness(captured)
        check(readiness.isReady) { "登录状态尚未准备完成" }
        return completeLogin(captured)
    }

    suspend fun completeLogin(captured: FireCapturedLoginState): SessionState {
        val finalization = sessionStore.finalizeLoginFromWebView(
            captured = captured,
            allowLowConfidenceSessionCookies = true,
        )
        if (finalization.session.loginPhase == LoginPhaseState.READY) {
            return finalization.session
        }

        return sessionStore.refreshBootstrapIfNeeded()
    }

    suspend fun logout(): SessionState {
        return sessionStore.logout()
    }

    suspend fun syncBrowserContext(webView: WebView): SessionState {
        return applyPlatformCookiesIfAuthoritative(relevantCookies(webView))
    }

    suspend fun probeLoginSyncReadiness(webView: WebView): FireLoginSyncReadiness {
        val captured = captureLoginState(webView)
        return loginSyncReadiness(captured)
    }

    suspend fun captureLoginState(webView: WebView): FireCapturedLoginState = withContext(Dispatchers.Main) {
        val currentUrl = webView.url ?: loginBaseUrl
        val usernameJson = webView.evaluateJavascriptSuspend(FireLoginScripts.readCurrentUsername)
        val csrfJson = webView.evaluateJavascriptSuspend(FireLoginScripts.readCsrfToken)
        val preloadedJson = webView.evaluateJavascriptSuspend(FireLoginScripts.readPreloadedData)

        val preloadedHtml = preloadedJson.decodeJsonStringOrNull()
        val resolvedUsername = usernameJson.decodeJsonStringOrNull()
            ?: FireBootstrapHtmlMetadataParser.currentUsername(preloadedHtml)
        val resolvedCsrfToken = csrfJson.decodeJsonStringOrNull()
            ?: FireBootstrapHtmlMetadataParser.csrfToken(preloadedHtml)

        FireCapturedLoginState(
            currentUrl = currentUrl,
            username = resolvedUsername,
            csrfToken = resolvedCsrfToken,
            homeHtml = preloadedHtml,
            browserUserAgent = webView.settings.userAgentString?.takeIf { it.isNotBlank() },
            cookies = relevantCookies(currentUrl),
        )
    }

    private suspend fun relevantCookies(webView: WebView): List<PlatformCookieState> = withContext(Dispatchers.Main) {
        relevantCookies(webView.url)
    }

    private fun relevantCookies(currentUrl: String?): List<PlatformCookieState> {
        val candidateUrls = linkedSetOf<String>()
        currentUrl?.takeIf { it.isNotBlank() }?.let(candidateUrls::add)
        candidateUrls.add(loginBaseUrl)
        candidateUrls.add("$loginBaseUrl/")

        val merged = LinkedHashMap<String, PlatformCookieState>()
        for (url in candidateUrls) {
            CookieManager.getInstance()
                .getCookie(url)
                .orEmpty()
                .parsePlatformCookies()
                .forEach { cookie ->
                    if (cookie.name !in merged) {
                        merged[cookie.name] = cookie
                    }
                }
        }
        return merged.values.toList()
    }

    private suspend fun applyPlatformCookiesIfAuthoritative(
        cookies: List<PlatformCookieState>,
    ): SessionState {
        if (!containsActiveAuthCookies(cookies)) {
            return sessionStore.snapshot()
        }
        return sessionStore.applyPlatformCookies(cookies)
    }

    private fun loginSyncReadiness(captured: FireCapturedLoginState): FireLoginSyncReadiness {
        return loginSyncReadiness(
            username = captured.username,
            cookies = captured.cookies,
            preferredBootstrapScore = FireBootstrapHtmlHeuristics.score(captured.homeHtml),
        )
    }

    private fun loginSyncReadiness(
        username: String?,
        cookies: List<PlatformCookieState>,
        preferredBootstrapScore: Int,
    ): FireLoginSyncReadiness {
        val normalizedUsername = username?.trim()?.takeIf { it.isNotEmpty() }
        val hasAuthCookies = containsActiveAuthCookies(cookies)
        val hasBootstrapHtml =
            preferredBootstrapScore >= FireBootstrapHtmlHeuristics.REUSABLE_LOGIN_BOOTSTRAP_SCORE_THRESHOLD
        return FireLoginSyncReadiness(
            isReady = normalizedUsername != null && hasAuthCookies && hasBootstrapHtml,
            username = normalizedUsername,
            hasAuthCookies = hasAuthCookies,
            hasBootstrapHtml = hasBootstrapHtml,
            preferredBootstrapScore = preferredBootstrapScore,
        )
    }

    private suspend fun WebView.evaluateJavascriptSuspend(script: String): String =
        suspendCancellableCoroutine { continuation ->
            evaluateJavascript(script) { value ->
                continuation.resume(value ?: "null")
            }
        }

    private fun String.decodeJsonStringOrNull(): String? {
        if (this == "null") {
            return null
        }

        return runCatching {
            JSONObject("""{"value":$this}""")
                .optString("value")
                .trim()
                .takeIf { it.isNotEmpty() }
        }.getOrNull()
    }

    private fun String.parsePlatformCookies(): List<PlatformCookieState> {
        return split(";")
            .mapNotNull { segment ->
                val trimmed = segment.trim()
                if (trimmed.isEmpty()) {
                    return@mapNotNull null
                }
                val separator = trimmed.indexOf('=')
                if (separator <= 0) {
                    return@mapNotNull null
                }

                PlatformCookieState(
                    name = trimmed.substring(0, separator),
                    value = trimmed.substring(separator + 1).trim(),
                    domain = null,
                    path = null,
                    expiresAtUnixMs = null,
                    sameSite = null,
                )
            }
            .filter { it.value.isNotEmpty() }
    }

    companion object {
        fun containsActiveAuthCookies(cookies: List<PlatformCookieState>): Boolean {
            val nowUnixMs = System.currentTimeMillis()
            val activeCookies = cookies.filter { cookie ->
                val value = cookie.value.trim()
                value.isNotEmpty() && (cookie.expiresAtUnixMs?.let { it > nowUnixMs } ?: true)
            }
            return activeCookies.any { it.name == "_t" } &&
                activeCookies.any { it.name == "_forum_session" }
        }
    }
}

private object FireBootstrapHtmlHeuristics {
    const val REUSABLE_LOGIN_BOOTSTRAP_SCORE_THRESHOLD = 8

    fun score(html: String?): Int {
        if (html.isNullOrBlank()) {
            return 0
        }

        val normalized = html.lowercase()
        var score = 0
        if (
            normalized.contains("id=\"data-discourse-setup\"") ||
            normalized.contains("id='data-discourse-setup'") ||
            normalized.contains("data-preloaded")
        ) {
            score += 8
        }
        if (
            normalized.contains("meta name=\"shared_session_key\"") ||
            normalized.contains("meta name='shared_session_key'")
        ) {
            score += 4
        }
        if (
            normalized.contains("meta name=\"current-username\"") ||
            normalized.contains("meta name='current-username'")
        ) {
            score += 2
        }
        if (
            normalized.contains("meta name=\"csrf-token\"") ||
            normalized.contains("meta name='csrf-token'")
        ) {
            score += 1
        }
        return score
    }
}

private object FireBootstrapHtmlMetadataParser {
    fun currentUsername(html: String?): String? = metaContent("current-username", html)

    fun csrfToken(html: String?): String? = metaContent("csrf-token", html)

    private fun metaContent(name: String, html: String?): String? {
        if (html.isNullOrBlank()) {
            return null
        }

        val escapedName = Regex.escape(name)
        val patterns = listOf(
            """<meta\b[^>]*\bname\s*=\s*["']$escapedName["'][^>]*\bcontent\s*=\s*["']([^"']+)["'][^>]*>""",
            """<meta\b[^>]*\bcontent\s*=\s*["']([^"']+)["'][^>]*\bname\s*=\s*["']$escapedName["'][^>]*>""",
        )
        return patterns.firstNotNullOfOrNull { pattern ->
            Regex(pattern, RegexOption.IGNORE_CASE)
                .find(html)
                ?.groupValues
                ?.getOrNull(1)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        }
    }
}
