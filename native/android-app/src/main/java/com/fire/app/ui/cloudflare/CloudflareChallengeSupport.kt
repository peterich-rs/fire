package com.fire.app.ui.cloudflare

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import com.fire.app.cloudflare.CloudflareChallengeDetector
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireWebViewLoginCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

object CloudflareChallengeSupport {
    const val SITE_ROOT_URL = "https://linux.do/"

    private const val CF_CLEARANCE_COOKIE = "cf_clearance="
    private const val LAUNCH_DEBOUNCE_MS = 1_500L
    private var lastActivityLaunchAtMs = 0L

    fun topicUrl(topicId: Long): String = "https://linux.do/t/$topicId"

    fun isChallenge(error: Throwable?): Boolean = CloudflareChallengeDetector.isChallenge(error)

    fun openSiteRoot(context: Context) {
        open(context, SITE_ROOT_URL)
    }

    fun openSiteRootIfChallenge(context: Context, error: Throwable?): Boolean {
        if (!isChallenge(error)) {
            return false
        }
        openSiteRoot(context)
        return true
    }

    fun open(context: Context, url: String) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastActivityLaunchAtMs < LAUNCH_DEBOUNCE_MS) {
            return
        }
        lastActivityLaunchAtMs = now

        val intent = CloudflareChallengeActivity.createIntent(context, url)
        if (context !is android.app.Activity) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun cookieHeader(url: String?): String? {
        return sequenceOf(url, SITE_ROOT_URL)
            .filterNotNull()
            .firstNotNullOfOrNull { candidate ->
                CookieManager.getInstance().getCookie(candidate)?.takeIf {
                    it.contains(CF_CLEARANCE_COOKIE)
                }
            }
    }

    fun hasClearance(url: String?): Boolean = cookieHeader(url) != null

    @Suppress("DEPRECATION")
    @SuppressLint("SetJavaScriptEnabled")
    fun configureWebView(webView: WebView) {
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            setGeolocationEnabled(false)
        }

        if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) {
            WebSettingsCompat.setSafeBrowsingEnabled(webView.settings, true)
        }
    }
}

class CloudflareWebViewCookieSyncer(
    private val sessionStore: FireSessionStore,
    private val scope: CoroutineScope,
) {
    private var syncing = false
    private var lastSyncedCookieHeader: String? = null

    fun syncIfClearanceAvailable(webView: WebView, url: String?) {
        val cookieHeader = CloudflareChallengeSupport.cookieHeader(url) ?: return
        if (syncing || cookieHeader == lastSyncedCookieHeader) {
            return
        }

        syncing = true
        scope.launch {
            try {
                CookieManager.getInstance().flush()
                FireWebViewLoginCoordinator(sessionStore).syncBrowserContext(webView)
                lastSyncedCookieHeader = cookieHeader
            } catch (_: Exception) {
                // The WebView remains visible; later page events can retry cookie sync.
            } finally {
                syncing = false
            }
        }
    }
}
