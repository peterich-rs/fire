package com.fire.app.session

import android.webkit.CookieManager
import android.webkit.WebView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URI
import kotlin.coroutines.resume
import uniffi.fire_uniffi.PlatformCookieState
import uniffi.fire_uniffi.SessionState

class FireWebViewLoginCoordinator(
    private val sessionStore: FireSessionStore,
    private val loginBaseUrl: String = "https://linux.do/",
) {
    suspend fun restorePersistedSessionIfAvailable(): SessionState? {
        return sessionStore.restorePersistedSessionIfAvailable()
    }

    suspend fun completeLogin(webView: WebView): SessionState {
        val captured = captureLoginState(webView)
        val state = sessionStore.syncLoginContext(captured)
        return if (state.bootstrap.hasPreloadedData) {
            state
        } else {
            sessionStore.refreshBootstrapIfNeeded()
        }
    }

    suspend fun logout(): SessionState {
        return sessionStore.logout()
    }

    suspend fun captureLoginState(webView: WebView): FireCapturedLoginState = withContext(Dispatchers.Main) {
        val currentUrl = webView.url ?: loginBaseUrl
        val urlHost = runCatching { URI(currentUrl).host }.getOrNull()

        val usernameJson = webView.evaluateJavascriptSuspend(
            """
            (function() {
              var meta = document.querySelector('meta[name="current-username"]');
              return JSON.stringify(meta && meta.content ? meta.content : null);
            })();
            """.trimIndent(),
        )
        val csrfJson = webView.evaluateJavascriptSuspend(
            """
            (function() {
              var meta = document.querySelector('meta[name="csrf-token"]');
              return JSON.stringify(meta && meta.content ? meta.content : null);
            })();
            """.trimIndent(),
        )
        val htmlJson = webView.evaluateJavascriptSuspend(
            """JSON.stringify(document.documentElement.outerHTML)""",
        )

        FireCapturedLoginState(
            currentUrl = webView.url,
            username = usernameJson.decodeJsonStringOrNull(),
            csrfToken = csrfJson.decodeJsonStringOrNull(),
            homeHtml = htmlJson.decodeJsonStringOrNull(),
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

                val name = trimmed.substring(0, separator)
                if (name !in setOf("_t", "_forum_session", "cf_clearance")) {
                    return@mapNotNull null
                }

                PlatformCookieState(
                    name = name,
                    value = trimmed.substring(separator + 1),
                    domain = domain,
                    path = "/",
                )
            }
    }
}
