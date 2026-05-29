package com.fire.app.session

import android.webkit.CookieManager
import android.webkit.WebView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URI
import kotlin.coroutines.resume
import uniffi.fire_uniffi_session.PlatformCookieState
import uniffi.fire_uniffi_session.SessionState

class FireWebViewLoginCoordinator(
    private val sessionStore: FireSessionStore,
    private val loginBaseUrl: String = "https://linux.do/",
) {
    suspend fun restorePersistedSessionIfAvailable(): SessionState? {
        return sessionStore.restorePersistedSessionIfAvailable()
    }

    suspend fun completeLogin(webView: WebView): SessionState {
        val captured = captureLoginState(webView)
        sessionStore.syncLoginContext(captured)
        val bootstrapped = sessionStore.refreshBootstrapIfNeeded()
        val ready = if (bootstrapped.readiness.hasCsrfToken) {
            bootstrapped
        } else {
            sessionStore.refreshCsrfTokenIfNeeded()
        }
        val resolved = if (ready.readiness.hasCurrentUser) {
            ready
        } else {
            sessionStore.refreshBootstrap()
        }
        val csrfReady = if (resolved.readiness.hasCsrfToken) {
            resolved
        } else {
            sessionStore.refreshCsrfTokenIfNeeded()
        }
        check(csrfReady.readiness.hasCurrentUser) { "登录会话缺少当前用户" }
        return csrfReady
    }

    suspend fun logout(): SessionState {
        return sessionStore.logout()
    }

    suspend fun syncBrowserContext(webView: WebView): SessionState {
        return sessionStore.syncLoginContext(captureLoginState(webView))
    }

    suspend fun captureLoginState(webView: WebView): FireCapturedLoginState = withContext(Dispatchers.Main) {
        val currentUrl = webView.url ?: loginBaseUrl
        val urlHost = runCatching { URI(currentUrl).host }.getOrNull()

        val usernameJson = webView.evaluateJavascriptSuspend(
            """
            (function() {
              var meta = document.querySelector('meta[name="current-username"]');
              if (meta && meta.content) return meta.content;
              try {
                var currentUser = window.Discourse && Discourse.User && Discourse.User.current && Discourse.User.current();
                if (currentUser && currentUser.username) return currentUser.username;
              } catch (e) {}
              return null;
            })();
            """.trimIndent(),
        )
        val csrfJson = webView.evaluateJavascriptSuspend(
            """
            (function() {
              var meta = document.querySelector('meta[name="csrf-token"]');
              return meta && meta.content ? meta.content : null;
            })();
            """.trimIndent(),
        )
        val htmlJson = webView.evaluateJavascriptSuspend(
            """document.documentElement ? document.documentElement.outerHTML : null""",
        )

        FireCapturedLoginState(
            currentUrl = currentUrl,
            username = usernameJson.decodeJsonStringOrNull(),
            csrfToken = csrfJson.decodeJsonStringOrNull(),
            homeHtml = htmlJson.decodeJsonStringOrNull(),
            browserUserAgent = webView.settings.userAgentString?.takeIf { it.isNotBlank() },
            cookies = CookieManager.getInstance()
                .getCookie(currentUrl)
                .orEmpty()
                .parsePlatformCookies(urlHost),
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
            JSONObject("{\"value\":$this}").optString("value").takeIf { it.isNotEmpty() }
        }.getOrNull()
    }

    private fun String.parsePlatformCookies(domain: String?): List<PlatformCookieState> {
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
                    value = trimmed.substring(separator + 1),
                    domain = domain,
                    path = "/",
                    expiresAtUnixMs = null,
                )
            }
    }
}
